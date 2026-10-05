"""Train the KYC-specific EfficientNet-B0 document risk classifier.

The CSV manifest must contain ``path``, ``label`` (normal/risky), and
``base_document_id``. Every derivative of one base document is kept in one
split to prevent identity-document leakage across train/validation/test.
"""

import argparse
import csv
import json
import os
from pathlib import Path

import numpy as np
import torch
from PIL import Image
from sklearn.metrics import (
    accuracy_score,
    confusion_matrix,
    f1_score,
    precision_score,
    recall_score,
    roc_auc_score,
)
from sklearn.model_selection import GroupShuffleSplit
from torch import nn
from torch.utils.data import DataLoader, Dataset
from torchvision import models, transforms


CLASSES = ('normal', 'risky')


class ManifestDataset(Dataset):
    def __init__(self, rows, transform):
        self.rows = rows
        self.transform = transform

    def __len__(self):
        return len(self.rows)

    def __getitem__(self, index):
        row = self.rows[index]
        with Image.open(row['path']) as source:
            image = source.convert('RGB')
        return self.transform(image), CLASSES.index(row['label'])


def load_rows(manifest: Path):
    rows = []
    with manifest.open(newline='', encoding='utf-8-sig') as source:
        for row in csv.DictReader(source):
            missing = {'path', 'label', 'base_document_id'} - row.keys()
            if missing:
                raise ValueError(f'Manifest columns missing: {sorted(missing)}')
            image_path = Path(row['path'])
            if not image_path.is_absolute():
                image_path = (manifest.parent / image_path).resolve()
            if row['label'] not in CLASSES:
                raise ValueError(f"Unsupported label: {row['label']}")
            if not row['base_document_id'].strip() or not image_path.is_file():
                raise ValueError(f'Invalid manifest row for {image_path}')
            rows.append({
                'path': image_path,
                'label': row['label'],
                'base_document_id': row['base_document_id'].strip(),
            })
    if len(rows) < 60 or len({row['base_document_id'] for row in rows}) < 20:
        raise ValueError('At least 60 images from 20 base documents are required')
    return rows


def split_rows(rows, seed):
    groups = np.array([row['base_document_id'] for row in rows])
    indexes = np.arange(len(rows))
    outer = GroupShuffleSplit(n_splits=1, test_size=0.30, random_state=seed)
    train_index, holdout_index = next(outer.split(indexes, groups=groups))
    holdout_groups = groups[holdout_index]
    inner = GroupShuffleSplit(n_splits=1, test_size=0.50, random_state=seed)
    validation_relative, test_relative = next(
        inner.split(holdout_index, groups=holdout_groups)
    )
    split_indexes = {
        'train': train_index,
        'validation': holdout_index[validation_relative],
        'test': holdout_index[test_relative],
    }
    splits = {
        name: [rows[int(index)] for index in selected]
        for name, selected in split_indexes.items()
    }
    group_sets = {
        name: {row['base_document_id'] for row in selected}
        for name, selected in splits.items()
    }
    if group_sets['train'] & group_sets['validation'] or \
            group_sets['train'] & group_sets['test'] or \
            group_sets['validation'] & group_sets['test']:
        raise RuntimeError('Base-document leakage detected between splits')
    for name, selected in splits.items():
        if {row['label'] for row in selected} != set(CLASSES):
            raise ValueError(f'{name} split must contain both classes')
    return splits


def evaluate(model, loader):
    labels, predictions, probabilities = [], [], []
    model.eval()
    with torch.inference_mode():
        for inputs, targets in loader:
            logits = model(inputs)
            risk = torch.softmax(logits, dim=1)[:, 1]
            labels.extend(targets.tolist())
            predictions.extend(logits.argmax(1).tolist())
            probabilities.extend(risk.tolist())
    return {
        'accuracy': float(accuracy_score(labels, predictions)),
        'precision': float(precision_score(labels, predictions, zero_division=0)),
        'recall': float(recall_score(labels, predictions, zero_division=0)),
        'f1': float(f1_score(labels, predictions, zero_division=0)),
        'rocAuc': float(roc_auc_score(labels, probabilities)),
        'confusionMatrix': confusion_matrix(labels, predictions).tolist(),
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('manifest', type=Path)
    parser.add_argument('--epochs', type=int, default=10)
    parser.add_argument('--seed', type=int, default=42)
    args = parser.parse_args()
    torch.manual_seed(args.seed)
    np.random.seed(args.seed)

    rows = load_rows(args.manifest)
    splits = split_rows(rows, args.seed)
    normalize = transforms.Normalize(
        [0.485, 0.456, 0.406], [0.229, 0.224, 0.225]
    )
    train_transform = transforms.Compose([
        transforms.Resize((224, 224)),
        transforms.RandomHorizontalFlip(),
        transforms.ColorJitter(brightness=0.15, contrast=0.15),
        transforms.ToTensor(),
        normalize,
    ])
    evaluation_transform = transforms.Compose([
        transforms.Resize((224, 224)), transforms.ToTensor(), normalize,
    ])
    loaders = {
        name: DataLoader(
            ManifestDataset(
                selected,
                train_transform if name == 'train' else evaluation_transform,
            ),
            batch_size=16,
            shuffle=name == 'train',
        )
        for name, selected in splits.items()
    }

    model = models.efficientnet_b0(weights=models.EfficientNet_B0_Weights.DEFAULT)
    for parameter in model.features.parameters():
        parameter.requires_grad = False
    model.classifier[1] = nn.Linear(model.classifier[1].in_features, 2)
    optimizer = torch.optim.AdamW(model.classifier.parameters(), lr=1e-3)
    loss_function = nn.CrossEntropyLoss()
    epochs = []
    for epoch in range(args.epochs):
        model.train()
        total_loss = 0.0
        for inputs, labels in loaders['train']:
            optimizer.zero_grad()
            outputs = model(inputs)
            loss = loss_function(outputs, labels)
            loss.backward()
            optimizer.step()
            total_loss += float(loss.item()) * inputs.size(0)
        epochs.append({
            'epoch': epoch + 1,
            'trainLoss': total_loss / len(splits['train']),
            'validation': evaluate(model, loaders['validation']),
        })

    root = Path(__file__).resolve().parents[2]
    models_dir, metrics_dir = root / 'models', root / 'metrics'
    models_dir.mkdir(exist_ok=True)
    metrics_dir.mkdir(exist_ok=True)
    artifact = models_dir / 'document_risk_efficientnet.pt'
    temporary = artifact.with_suffix('.tmp')
    model.eval()
    torch.jit.script(model).save(str(temporary))
    torch.jit.load(str(temporary), map_location='cpu').eval()
    os.replace(temporary, artifact)
    metrics = {
        'model': 'ImageNet-pretrained EfficientNet-B0',
        'classes': CLASSES,
        'seed': args.seed,
        'leakagePolicy': 'grouped by base_document_id',
        'splitCounts': {
            name: {
                'images': len(selected),
                'baseDocuments': len({row['base_document_id'] for row in selected}),
            }
            for name, selected in splits.items()
        },
        'epochs': epochs,
        'test': evaluate(model, loaders['test']),
    }
    (metrics_dir / 'document_risk_metrics.json').write_text(
        json.dumps(metrics, indent=2), encoding='utf-8'
    )


if __name__ == '__main__':
    main()

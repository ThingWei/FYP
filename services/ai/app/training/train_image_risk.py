"""Train and export the EfficientNet-B0 risk classifier.

Input is a CSV: path,label,item_id,split,source_type. Keep all photos and
derivatives of an item in one split. Labels are normal/risky; provenance is
reviewed_real/synthetic_manipulation. Splits are train/validation/test.
No accuracy is claimed until a curated, independently reviewed dataset is used.
"""

import argparse
import copy
import json
from pathlib import Path

import torch
from torch import nn
from torch.utils.data import DataLoader, Dataset
from torchvision import models, transforms
from PIL import Image
from sklearn.metrics import accuracy_score, confusion_matrix, f1_score

from .item_risk_data import load_manifest
from ..services.item_verification import RISK_CONTRACT


class ManifestImages(Dataset):
    classes = ['normal', 'risky']

    def __init__(self, rows, transform):
        self.rows, self.transform = rows, transform

    def __len__(self):
        return len(self.rows)

    def __getitem__(self, index):
        row = self.rows[index]
        with Image.open(row['path']) as image:
            tensor = self.transform(image.convert('RGB'))
        return tensor, int(row['label'] == 'risky')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('dataset', type=Path)
    parser.add_argument('--epochs', type=int, default=8)
    parser.add_argument('--seed', type=int, default=42)
    parser.add_argument('--acknowledge-source-permission', action='store_true')
    args = parser.parse_args()
    if not args.acknowledge_source_permission:
        parser.error('Acknowledge permission to use the reviewed source images')
    if args.epochs < 1:
        parser.error('epochs must be positive')
    splits = load_manifest(args.dataset)
    torch.manual_seed(args.seed)
    transform = transforms.Compose([
        transforms.Resize((224, 224)),
        transforms.ToTensor(),
        transforms.Normalize([0.485, 0.456, 0.406], [0.229, 0.224, 0.225]),
    ])
    loaders = {name: DataLoader(ManifestImages(rows, transform), batch_size=16,
                               shuffle=name == 'train') for name, rows in splits.items()}
    model = models.efficientnet_b0(weights=models.EfficientNet_B0_Weights.DEFAULT)
    for parameter in model.features.parameters():
        parameter.requires_grad = False
    model.classifier[1] = nn.Linear(model.classifier[1].in_features, 2)
    optimizer = torch.optim.AdamW(model.classifier.parameters(), lr=1e-3)
    loss_function = nn.CrossEntropyLoss()
    metrics, best_loss, best_state = [], float('inf'), None
    for epoch in range(args.epochs):
        epoch_result = {'epoch': epoch + 1}
        for phase in ('train', 'validation'):
            model.eval()  # Do not update frozen feature-extractor BatchNorm.
            model.classifier.train(phase == 'train')
            correct = count = 0
            loss_total = 0.0
            for inputs, labels in loaders[phase]:
                optimizer.zero_grad()
                with torch.set_grad_enabled(phase == 'train'):
                    outputs = model(inputs)
                    loss = loss_function(outputs, labels)
                    if phase == 'train':
                        loss.backward()
                        optimizer.step()
                loss_total += float(loss.item()) * inputs.size(0)
                correct += int((outputs.argmax(1) == labels).sum())
                count += inputs.size(0)
            epoch_result[f'{phase}Loss'] = loss_total / count
            epoch_result[f'{phase}Accuracy'] = correct / count
        metrics.append(epoch_result)
        if epoch_result['validationLoss'] < best_loss:
            best_loss = epoch_result['validationLoss']
            best_state = copy.deepcopy(model.state_dict())
    model.load_state_dict(best_state)
    model.eval()
    actual, predicted = [], []
    with torch.inference_mode():
        for inputs, labels in loaders['test']:
            actual.extend(labels.tolist())
            predicted.extend(model(inputs).argmax(1).tolist())
    metadata = {
        'contract': RISK_CONTRACT, 'architecture': 'efficientnet_b0',
        'purpose': 'item_photo_risk_assistance', 'classes': ManifestImages.classes,
        'preprocessing': 'rgb-224-imagenet-v1',
        'seed': args.seed,
        'sourceTypes': sorted({r['source_type'] for rows in splits.values() for r in rows}),
        'splitImageCounts': {name: len(rows) for name, rows in splits.items()},
        'splitItemCounts': {name: len({r['item_id'] for r in rows}) for name, rows in splits.items()},
        'testMetrics': {
            'accuracy': float(accuracy_score(actual, predicted)),
            'macroF1': float(f1_score(actual, predicted, average='macro', zero_division=0)),
            'confusionMatrix': confusion_matrix(actual, predicted, labels=[0, 1]).tolist(),
            'samples': len(actual),
        },
        'limitations': ['Caller-supplied grouping and labels are not independently verified',
                       'Synthetic evaluation is not real-world tamper accuracy',
                       'Normal is not proof of authenticity or ownership'],
    }
    root = Path(__file__).resolve().parents[2]
    (root / 'models').mkdir(exist_ok=True)
    (root / 'metrics').mkdir(exist_ok=True)
    model.eval()
    scripted = torch.jit.script(model)
    output = root / 'models' / 'image_risk_efficientnet.pt'
    temporary = output.with_suffix('.pending.pt')
    scripted.save(str(temporary), _extra_files={'metadata.json': json.dumps(metadata)})
    extra = {'metadata.json': ''}
    loaded = torch.jit.load(str(temporary), map_location='cpu', _extra_files=extra).eval()
    with torch.inference_mode():
        sample = next(iter(loaders['test']))[0][:1]
        if not torch.allclose(loaded(sample), model(sample), atol=1e-5):
            raise ValueError('Export smoke test failed; previous artifact preserved')
    temporary.replace(output)
    (root / 'metrics' / 'image_risk_metrics.json').write_text(
        json.dumps({**metadata, 'epochs': metrics}, indent=2),
        encoding='utf-8',
    )
    print(json.dumps(metadata, indent=2))


if __name__ == '__main__':
    main()

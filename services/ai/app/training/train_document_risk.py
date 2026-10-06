"""Train the KYC-specific EfficientNet-B0 document risk classifier.

The CSV manifest must contain ``path``, ``label`` (normal/risky), and
``base_document_id``. Every derivative of one base document is kept in one
split to prevent identity-document leakage across train/validation/test.
"""

import argparse
import csv
import hashlib
import json
import math
import os
import random
import re
from pathlib import Path

import numpy as np
import torch
from PIL import Image, ImageOps
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
    def __init__(self, rows, transform, input_mode='full', crop_padding=0.25):
        self.rows = rows
        self.transform = transform
        self.input_mode = input_mode
        self.crop_padding = crop_padding

    def __len__(self):
        return len(self.rows)

    def __getitem__(self, index):
        row = self.rows[index]
        with Image.open(row['path']) as source:
            image = source.convert('RGB')
        if self.input_mode == 'fields':
            image = crop_field(image, row['region_xyxy'], self.crop_padding)
        return self.transform(image), CLASSES.index(row['label'])


def parse_region(value, image_size):
    """Validate coordinates against the encoded image, never invent a region."""
    try:
        box = json.loads(value) if isinstance(value, str) else value
        if not isinstance(box, (list, tuple)) or len(box) != 4 or any(
            isinstance(v, bool) or not isinstance(v, (int, float)) or not math.isfinite(v)
            for v in box
        ):
            raise ValueError
        x1, y1, x2, y2 = box
        width, height = image_size
        if not (0 <= x1 < x2 <= width and 0 <= y1 < y2 <= height):
            raise ValueError
        return tuple(box)
    except (ValueError, TypeError, json.JSONDecodeError):
        raise ValueError('Invalid or missing field region_xyxy') from None


def crop_field(image, box, padding):
    x1, y1, x2, y2 = parse_region(box, image.size)
    dx, dy = (x2 - x1) * padding, (y2 - y1) * padding
    return image.crop((max(0, math.floor(x1 - dx)), max(0, math.floor(y1 - dy)),
                       min(image.width, math.ceil(x2 + dx)),
                       min(image.height, math.ceil(y2 + dy))))


class Letterbox:
    """Preserve text aspect ratio; the same padding is used for both labels."""

    def __init__(self, size):
        self.size = size

    def __call__(self, image):
        return ImageOps.pad(image, (self.size, self.size),
                            method=Image.Resampling.BILINEAR, color=(127, 127, 127))


def validate_field_pairs(rows):
    """Synthetic oracle boxes are research inputs, not automatic localization."""
    pairs = {}
    for row in rows:
        if not row.get('region_xyxy'):
            raise ValueError('Field input requires region_xyxy for every row')
        if row['source_type'] != 'synthetic_manipulation':
            continue
        if not row.get('variant_id'):
            raise ValueError('Synthetic field input requires paired variant_id')
        pairs.setdefault(row['variant_id'], []).append(row)
    for pair in pairs.values():
        if len(pair) != 2 or {r['label'] for r in pair} != set(CLASSES) or any(
            len({tuple(r[key]) if key == 'region_xyxy' else r[key] for r in pair}) != 1
            for key in ('region_xyxy', 'base_document_id', 'split', 'side',
                        'region_class', 'capture_profile', 'image_size')
        ):
            raise ValueError('Synthetic pair must share its field crop, group, side and capture controls')


def load_rows(manifest: Path):
    rows = []
    seen_paths = set()
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
            image_path = image_path.resolve()
            if image_path in seen_paths:
                raise ValueError('Duplicate image path in risk manifest')
            seen_paths.add(image_path)
            image_hash = hashlib.sha256(image_path.read_bytes()).hexdigest()
            if row.get('image_sha256') and row['image_sha256'] != image_hash:
                raise ValueError('Generated image hash differs from risk manifest')
            with Image.open(image_path) as image:
                image.load()
                image_size = image.size
            region = parse_region(row['region_xyxy'], image_size) if row.get('region_xyxy') else None
            rows.append({
                'path': image_path,
                'label': row['label'],
                'base_document_id': row['base_document_id'].strip(),
                'split': {'val': 'validation'}.get(row.get('split', ''), row.get('split', '')),
                'source_type': row.get('source_type') or 'unreported',
                'side': row.get('side') or 'unknown',
                'manipulation_type': row.get('manipulation_type') or 'unreported',
                'content_hash': image_hash,
                'region_xyxy': region,
                'image_size': image_size,
                'region_class': row.get('region_class') or 'unreported',
                'variant_id': row.get('variant_id') or '',
                'capture_profile': row.get('capture_profile') or '',
            })
    if len(rows) < 60 or len({row['base_document_id'] for row in rows}) < 20:
        raise ValueError('At least 60 images from 20 base documents are required')
    return rows


def split_rows(rows, seed):
    declared = [row.get('split') for row in rows]
    if any(declared):
        if any(split not in ('train', 'validation', 'test') for split in declared):
            raise ValueError('All declared risk splits must be train/validation/test')
        splits = {name: [row for row in rows if row['split'] == name]
                  for name in ('train', 'validation', 'test')}
        validate_splits(splits)
        return splits
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
    validate_splits(splits)
    return splits


def validate_splits(splits):
    group_sets = {
        name: {row['base_document_id'] for row in selected}
        for name, selected in splits.items()
    }
    if group_sets['train'] & group_sets['validation'] or \
            group_sets['train'] & group_sets['test'] or \
            group_sets['validation'] & group_sets['test']:
        raise RuntimeError('Base-document leakage detected between splits')
    hashes = {}
    hash_labels = {}
    for name, selected in splits.items():
        for row in selected:
            if row.get('content_hash'):
                previous = hashes.setdefault(row['content_hash'], name)
                if previous != name:
                    raise RuntimeError('Exact-image leakage detected between splits')
                previous_label = hash_labels.setdefault(row['content_hash'], row['label'])
                if previous_label != row['label']:
                    raise ValueError('Conflicting risk labels for identical image bytes')
    for name, selected in splits.items():
        if {row['label'] for row in selected} != set(CLASSES):
            raise ValueError(f'{name} split must contain both classes')


def risk_training_provenance(rows):
    from collections import Counter

    sources = Counter(row.get('source_type', 'unreported') for row in rows)
    synthetic = sources.get('synthetic_manipulation', 0) > 0
    return {
        'purpose': 'synthetic_manipulation_risk_research' if synthetic else 'document_risk_research',
        'containsSyntheticManipulations': synthetic,
        'sourceCounts': dict(sources),
        'operationCounts': dict(Counter(row.get('manipulation_type', 'unreported') for row in rows
                                       if row['label'] == 'risky')),
        'sideCounts': dict(Counter(row.get('side', 'unknown') for row in rows)),
        'labelDefinitions': {
            'normal': 'Baseline/non-altered under source labelling; not government-confirmed genuine.',
            'risky': 'Labelled manipulation risk; not a definitive counterfeit verdict.',
        },
        'limitations': [
            'Source permission and holder-group assertions require review.',
            'Synthetic held-out metrics do not establish real-world MyKad authenticity performance.',
            'Independent real-world evaluation and administrator decisions remain necessary.',
        ],
    }


def risk_output_names(provenance, input_mode='full', output_tag=None):
    if output_tag and not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_-]{0,48}', output_tag):
        raise ValueError('Output tag must be a short alphanumeric name, not a path')
    suffix = ('_fields' if input_mode == 'fields' else '') + (f'_{output_tag}' if output_tag else '')
    if provenance['containsSyntheticManipulations']:
        return f'document_risk_synthetic{suffix}_efficientnet.pt', f'document_risk_synthetic{suffix}_metrics.json'
    return f'document_risk{suffix}_efficientnet.pt', f'document_risk{suffix}_metrics.json'


def evaluate(model, loader, device='cpu'):
    labels, predictions, probabilities = [], [], []
    model.eval()
    with torch.inference_mode():
        for inputs, targets in loader:
            logits = model(inputs.to(device))
            risk = torch.softmax(logits, dim=1)[:, 1]
            labels.extend(targets.tolist())
            predictions.extend(logits.argmax(1).cpu().tolist())
            probabilities.extend(risk.cpu().tolist())
    return {
        'accuracy': float(accuracy_score(labels, predictions)),
        'precision': float(precision_score(labels, predictions, zero_division=0)),
        'recall': float(recall_score(labels, predictions, zero_division=0)),
        'f1': float(f1_score(labels, predictions, zero_division=0)),
        'rocAuc': float(roc_auc_score(labels, probabilities)),
        'confusionMatrix': confusion_matrix(labels, predictions).tolist(),
    }


def configure_fine_tuning(model, blocks, head_lr, backbone_lr):
    for parameter in model.features.parameters():
        parameter.requires_grad = False
    groups = [{'params': list(model.classifier.parameters()), 'lr': head_lr}]
    if blocks:
        if not isinstance(model.features, nn.Sequential) or blocks > len(model.features):
            raise ValueError('Fine-tune blocks exceed available sequential feature blocks')
        parameters = list(model.features[-blocks:].parameters())
        for parameter in parameters:
            parameter.requires_grad = True
        groups.append({'params': parameters, 'lr': backbone_lr})
    return torch.optim.AdamW(groups)


def set_training_mode(model, blocks):
    model.train()
    # requires_grad=False does not freeze BatchNorm statistics or stochastic depth.
    model.features.eval()
    if blocks:
        model.features[-blocks:].train()
    for module in model.features.modules():
        if isinstance(module, nn.modules.batchnorm._BatchNorm):
            module.eval()


def validation_score(metrics):
    return metrics['rocAuc'], metrics['f1']


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('manifest', type=Path)
    parser.add_argument('--epochs', type=int, default=10)
    parser.add_argument('--seed', type=int, default=42)
    parser.add_argument('--input-mode', choices=('full', 'fields'), default='full')
    parser.add_argument('--image-size', type=int, default=224)
    parser.add_argument('--crop-padding', type=float, default=0.25)
    parser.add_argument('--warmup-epochs', type=int, default=2)
    parser.add_argument('--fine-tune-blocks', type=int, default=2)
    parser.add_argument('--head-lr', type=float, default=1e-3)
    parser.add_argument('--backbone-lr', type=float, default=1e-5)
    parser.add_argument('--patience', type=int, default=5)
    parser.add_argument('--batch-size', type=int, default=16)
    parser.add_argument('--device', choices=('auto', 'cpu', 'cuda'), default='auto')
    parser.add_argument('--output-tag')
    parser.add_argument('--overwrite', action='store_true')
    parser.add_argument('--dry-run', action='store_true')
    args = parser.parse_args()
    if args.epochs < 1 or args.batch_size < 1 or args.patience < 1:
        parser.error('epochs, batch size and patience must be positive')
    if args.image_size < 64 or args.image_size > 1024:
        parser.error('image size must be between 64 and 1024')
    if not math.isfinite(args.crop_padding) or not 0 <= args.crop_padding <= 1:
        parser.error('crop padding must be between zero and one')
    if args.warmup_epochs < 0 or not 0 <= args.fine_tune_blocks <= 9:
        parser.error('warmup must be nonnegative; fine-tune blocks must be 0..9')
    if not all(math.isfinite(v) and v > 0 for v in (args.head_lr, args.backbone_lr)) or args.backbone_lr > args.head_lr:
        parser.error('learning rates must be positive; backbone LR cannot exceed head LR')
    torch.manual_seed(args.seed)
    np.random.seed(args.seed)
    random.seed(args.seed)

    rows = load_rows(args.manifest)
    splits = split_rows(rows, args.seed)
    provenance = risk_training_provenance(rows)
    if args.input_mode == 'fields':
        validate_field_pairs(rows)
    root = Path(__file__).resolve().parents[2]
    models_dir, metrics_dir = root / 'models', root / 'metrics'
    artifact_name, metrics_name = risk_output_names(provenance, args.input_mode, args.output_tag)
    artifact = models_dir / artifact_name
    metrics_path = metrics_dir / metrics_name
    contract = {
        'inputMode': args.input_mode, 'imageSize': args.image_size,
        'resize': 'aspect_preserving_letterbox' if args.input_mode == 'fields' else 'square_resize',
        'cropPadding': args.crop_padding if args.input_mode == 'fields' else None,
        'normalizationMean': [0.485, 0.456, 0.406],
        'normalizationStd': [0.229, 0.224, 0.225],
        'regionSource': 'manifest_annotations_not_automatic_detection' if args.input_mode == 'fields' else None,
        'runtimeCompatibleWithoutAdapter': args.input_mode == 'full' and args.image_size == 224,
    }
    provenance['inputContract'] = contract
    if args.input_mode == 'fields':
        provenance['limitations'].append('Field-crop metrics use annotated locations; they do not measure end-to-end detection.')
    split_counts = {name: {'images': len(selected),
                          'baseDocuments': len({r['base_document_id'] for r in selected})}
                    for name, selected in splits.items()}
    if args.dry_run:
        print(json.dumps({'dryRun': True, 'artifact': artifact_name, 'splitCounts': split_counts,
                          'inputContract': contract, 'provenance': provenance}, indent=2))
        return
    if not args.overwrite and (artifact.exists() or metrics_path.exists()):
        raise FileExistsError('Training output already exists; use a new --output-tag or explicit --overwrite')
    device = 'cuda' if args.device == 'auto' and torch.cuda.is_available() else args.device
    if device == 'auto':
        device = 'cpu'
    if device == 'cuda' and not torch.cuda.is_available():
        parser.error('CUDA requested but unavailable')
    normalize = transforms.Normalize(
        [0.485, 0.456, 0.406], [0.229, 0.224, 0.225]
    )
    resize = Letterbox(args.image_size) if args.input_mode == 'fields' else transforms.Resize((args.image_size, args.image_size))
    train_transform = transforms.Compose([
        resize,
        # No horizontal flips/random crops that reverse text or erase alterations.
        transforms.ColorJitter(brightness=0.10, contrast=0.10),
        transforms.ToTensor(),
        normalize,
    ])
    evaluation_transform = transforms.Compose([
        resize, transforms.ToTensor(), normalize,
    ])
    loaders = {
        name: DataLoader(
            ManifestDataset(
                selected,
                train_transform if name == 'train' else evaluation_transform,
                args.input_mode, args.crop_padding,
            ),
            batch_size=args.batch_size,
            shuffle=name == 'train',
        )
        for name, selected in splits.items()
    }

    model = models.efficientnet_b0(weights=models.EfficientNet_B0_Weights.DEFAULT)
    model.classifier[1] = nn.Linear(model.classifier[1].in_features, 2)
    model.to(device)
    optimizer = configure_fine_tuning(model, 0, args.head_lr, args.backbone_lr)
    loss_function = nn.CrossEntropyLoss()
    epochs = []
    best_state, best_score, best_epoch, stale = None, (-1.0, -1.0), 0, 0
    active_blocks = 0
    for epoch in range(args.epochs):
        if epoch == args.warmup_epochs and args.fine_tune_blocks:
            active_blocks = args.fine_tune_blocks
            optimizer = configure_fine_tuning(model, active_blocks, args.head_lr, args.backbone_lr)
            stale = 0
        set_training_mode(model, active_blocks)
        total_loss = 0.0
        for inputs, labels in loaders['train']:
            inputs, labels = inputs.to(device), labels.to(device)
            optimizer.zero_grad()
            outputs = model(inputs)
            loss = loss_function(outputs, labels)
            loss.backward()
            optimizer.step()
            total_loss += float(loss.item()) * inputs.size(0)
        validation = evaluate(model, loaders['validation'], device)
        epochs.append({
            'epoch': epoch + 1,
            'trainLoss': total_loss / len(splits['train']),
            'phase': 'fine_tune' if active_blocks else 'head_warmup',
            'validation': validation,
        })
        score = validation_score(validation)
        if score > best_score:
            best_score, best_epoch, stale = score, epoch + 1, 0
            best_state = {key: value.detach().cpu().clone() for key, value in model.state_dict().items()}
        else:
            stale += 1
        print(f'Epoch {epoch + 1}/{args.epochs}: validation AUC={validation["rocAuc"]:.4f}, '
              f'F1={validation["f1"]:.4f}', flush=True)
        if epoch >= args.warmup_epochs and stale >= args.patience:
            break

    model.load_state_dict(best_state)
    model.to('cpu').eval()
    models_dir.mkdir(exist_ok=True)
    metrics_dir.mkdir(exist_ok=True)
    temporary = artifact.with_suffix('.tmp')
    model.eval()
    torch.jit.script(model).save(str(temporary), _extra_files={
        'renthub_provenance.json': json.dumps(provenance),
    })
    embedded = {'renthub_provenance.json': ''}
    exported = torch.jit.load(str(temporary), map_location='cpu', _extra_files=embedded).eval()
    if json.loads(embedded['renthub_provenance.json']) != provenance:
        raise RuntimeError('Risk model provenance did not survive artifact reload')
    metrics = {
        'model': 'ImageNet-pretrained EfficientNet-B0',
        'classes': CLASSES,
        'seed': args.seed,
        'artifact': artifact_name,
        'provenance': provenance,
        'training': {'warmupEpochs': args.warmup_epochs, 'fineTuneBlocks': args.fine_tune_blocks,
                     'headLearningRate': args.head_lr, 'backboneLearningRate': args.backbone_lr,
                     'batchNormStatistics': 'frozen', 'device': device,
                     'checkpointSelection': 'validation_roc_auc_then_f1', 'bestEpoch': best_epoch,
                     'patience': args.patience, 'decisionThreshold': 0.5},
        'splitStrategy': 'declared_grouped_splits' if any(row.get('split') for row in rows)
                         else 'group_shuffle_split',
        'leakagePolicy': 'grouped by base_document_id',
        'splitCounts': split_counts,
        'epochs': epochs,
        'test': evaluate(exported, loaders['test']),
    }
    # Evaluate the saved selected checkpoint, not the last epoch or test-selected settings.
    slices = {}
    for side in sorted({r['side'] for r in splits['test']}):
        selected = [r for r in splits['test'] if r['side'] == side]
        if {r['label'] for r in selected} == set(CLASSES):
            loader = DataLoader(ManifestDataset(selected, evaluation_transform, args.input_mode,
                                               args.crop_padding), batch_size=args.batch_size)
            slices[side] = {'images': len(selected), **evaluate(exported, loader)}
    metrics['testBySide'] = slices
    operations = {}
    for operation in sorted({r['manipulation_type'] for r in splits['test'] if r['label'] == 'risky'}):
        selected = [r for r in splits['test'] if r['label'] == 'risky' and r['manipulation_type'] == operation]
        loader = DataLoader(ManifestDataset(selected, evaluation_transform, args.input_mode,
                                           args.crop_padding), batch_size=args.batch_size)
        hits = 0
        with torch.inference_mode():
            for inputs, _targets in loader:
                hits += int((exported(inputs).argmax(1) == 1).sum())
        operations[operation] = {'images': len(selected), 'detected': hits, 'recall': hits / len(selected)}
    metrics['testRiskRecallByOperation'] = operations
    os.replace(temporary, artifact)
    metrics_path.write_text(
        json.dumps(metrics, indent=2), encoding='utf-8'
    )
    print(json.dumps(metrics, indent=2))


if __name__ == '__main__':
    main()

"""Train and export the EfficientNet-B0 risk classifier.

Input is a CSV: path,label,item_id,split,source_type. Keep all photos and
derivatives of an item in one split. Labels are normal/risky; provenance is
reviewed_real/synthetic_manipulation. Splits are train/validation/test.
No accuracy is claimed until a curated, independently reviewed dataset is used.
"""

import argparse
import copy
import hashlib
import json
from pathlib import Path
from urllib.parse import urlparse

import torch
from torch import nn
from torch.utils.data import DataLoader, Dataset
from torchvision import models, transforms
from PIL import Image
from sklearn.metrics import accuracy_score, confusion_matrix, precision_recall_fscore_support

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


ROOT = Path(__file__).resolve().parents[2]


def classification_metrics(actual, predicted):
    if not actual:
        return {'status': 'not_evaluated', 'samples': 0, 'accuracy': None,
                'macroF1': None, 'precision': None, 'recall': None, 'confusionMatrix': None}
    precision, recall, f1, support = precision_recall_fscore_support(
        actual, predicted, labels=[0, 1], zero_division=0)
    return {'status': 'evaluated', 'samples': len(actual),
            'accuracy': float(accuracy_score(actual, predicted)),
            'macroF1': float(f1.mean()), 'precision': float(precision.mean()),
            'recall': float(recall.mean()),
            'perClass': {label: {'precision': float(precision[i]), 'recall': float(recall[i]),
                                 'f1': float(f1[i]), 'samples': int(support[i])}
                         for i, label in enumerate(ManifestImages.classes)},
            'confusionMatrix': confusion_matrix(actual, predicted, labels=[0, 1]).tolist()}


def initialization_model(allow_download=False):
    weights = models.EfficientNet_B0_Weights.DEFAULT
    cached = Path(torch.hub.get_dir()) / 'checkpoints' / Path(urlparse(weights.url).path).name
    if not cached.is_file() and not allow_download:
        raise ValueError('Cached EfficientNet initialization weights missing; explicit --allow-download is required')
    # With a cached file, load locally ourselves: torchvision cannot silently
    # download after a corrupt/missing-cache check. Untrusted weights are refused.
    if cached.is_file():
        expected = cached.stem.rsplit('-', 1)[-1]
        if not hashlib.sha256(cached.read_bytes()).hexdigest().startswith(expected):
            raise ValueError('Cached EfficientNet initialization checksum mismatch')
        model = models.efficientnet_b0(weights=None)
        model.load_state_dict(torch.load(cached, map_location='cpu', weights_only=True))
        return model
    return models.efficientnet_b0(weights=weights)  # Explicitly authorized download only.


def candidate_directory(output):
    output = output.resolve()
    if any(output.is_relative_to((ROOT / name).resolve()) for name in ('models', 'metrics', 'data')):
        raise ValueError('Candidate output must be outside deployed models, metrics and data')
    if output.exists():
        raise ValueError('Candidate directory already exists; never overwrite a candidate')
    return output


def train_candidate(dataset, output, *, epochs=8, seed=42,
                    acknowledge_source_permission=False, allow_download=False):
    if not acknowledge_source_permission:
        raise ValueError('Acknowledge permission to use the reviewed source images')
    if not 1 <= epochs <= 1000:
        raise ValueError('epochs must be 1-1000')
    output = candidate_directory(output)
    splits = load_manifest(dataset)
    fingerprint = hashlib.sha256()
    fingerprint.update(dataset.read_bytes())
    for phase, rows in splits.items():
        for row in rows:
            fingerprint.update(phase.encode())
            fingerprint.update(hashlib.sha256(row['path'].read_bytes()).digest())
    torch.manual_seed(seed)
    transform = transforms.Compose([
        transforms.Resize((224, 224)),
        transforms.ToTensor(),
        transforms.Normalize([0.485, 0.456, 0.406], [0.229, 0.224, 0.225]),
    ])
    loaders = {name: DataLoader(ManifestImages(rows, transform), batch_size=16,
                               shuffle=name == 'train') for name, rows in splits.items()}
    model = initialization_model(allow_download)
    for parameter in model.features.parameters():
        parameter.requires_grad = False
    model.classifier[1] = nn.Linear(model.classifier[1].in_features, 2)
    optimizer = torch.optim.AdamW(model.classifier.parameters(), lr=1e-3)
    loss_function = nn.CrossEntropyLoss()
    metrics, best_loss, best_state = [], float('inf'), None
    for epoch in range(epochs):
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
        'seed': seed, 'datasetFingerprintSha256': fingerprint.hexdigest(),
        'artifactWritten': 'candidate_only', 'deployed': False,
        'sourceTypes': sorted({r['source_type'] for rows in splits.values() for r in rows}),
        'evaluationScope': (
            'synthetic_only' if all(r['source_type'] == 'synthetic_manipulation' for rows in splits.values() for r in rows)
            else 'reviewed_real_only' if all(r['source_type'] == 'reviewed_real' for rows in splits.values() for r in rows)
            else 'mixed_provenance'),
        'labelDefinitions': {
            'normal': 'No labelled alteration; NOT proof of authenticity, ownership or condition',
            'risky': 'Labelled photo-risk signal; synthetic edits are NOT real counterfeit evidence'},
        'itemLevelGroupingVerified': False,
        'splitImageCounts': {name: len(rows) for name, rows in splits.items()},
        'splitItemCounts': {name: len({r['item_id'] for r in rows}) for name, rows in splits.items()},
        'testMetrics': classification_metrics(actual, predicted),
        'limitations': ['Caller-supplied grouping and labels are not independently verified',
                       'Synthetic evaluation is not real-world tamper accuracy',
                       'Normal is not proof of authenticity or ownership'],
    }
    test_rows = splits['test']
    metadata['testMetricsBySourceType'] = {}
    for source in ('synthetic_manipulation', 'reviewed_real'):
        positions = [i for i, row in enumerate(test_rows) if row['source_type'] == source]
        observed, inferred = [actual[i] for i in positions], [predicted[i] for i in positions]
        metadata['testMetricsBySourceType'][source] = classification_metrics(observed, inferred)
    metadata['datasetNames'] = sorted({row.get('dataset_name') or 'unspecified'
                                       for rows in splits.values() for row in rows})
    metadata['testMetricsByDataset'] = {}
    for dataset_name in metadata['datasetNames']:
        positions = [i for i, row in enumerate(test_rows)
                     if (row.get('dataset_name') or 'unspecified') == dataset_name]
        metadata['testMetricsByDataset'][dataset_name] = classification_metrics(
            [actual[i] for i in positions], [predicted[i] for i in positions])
    output.mkdir(parents=True, exist_ok=False)
    model.eval()
    scripted = torch.jit.script(model)
    artifact = output / 'image_risk_efficientnet.pt'
    temporary = artifact.with_suffix('.pending.pt')
    scripted.save(str(temporary), _extra_files={'metadata.json': json.dumps(metadata)})
    extra = {'metadata.json': ''}
    loaded = torch.jit.load(str(temporary), map_location='cpu', _extra_files=extra).eval()
    with torch.inference_mode():
        sample = next(iter(loaders['test']))[0][:1]
        inferred = loaded(sample)
        if inferred.shape != (1, 2) or not torch.isfinite(inferred).all() or not torch.allclose(inferred, model(sample), atol=1e-5):
            raise ValueError('Export smoke test failed; previous artifact preserved')
    temporary.replace(artifact)
    (output / 'image_risk_metrics.json').write_text(
        json.dumps({**metadata, 'epochs': metrics}, indent=2),
        encoding='utf-8',
    )
    configuration = {'architecture': 'efficientnet_b0', 'seed': seed, 'epochs': epochs,
                     'batchSize': 16, 'learningRate': .001, 'frozenFeatures': True,
                     'allowDownload': allow_download, 'sourcePermissionAcknowledgedByCaller': True,
                     'datasetFingerprintSha256': fingerprint.hexdigest(), 'deployed': False}
    (output / 'configuration.json').write_text(json.dumps(configuration, indent=2), encoding='utf-8')
    return metadata


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('dataset', type=Path)
    parser.add_argument('--output', type=Path, required=True, help='NEW isolated candidate directory under .data')
    parser.add_argument('--epochs', type=int, default=8)
    parser.add_argument('--seed', type=int, default=42)
    parser.add_argument('--acknowledge-source-permission', action='store_true')
    parser.add_argument('--allow-download', action='store_true')
    args = parser.parse_args()
    if not args.output.resolve().is_relative_to((ROOT / '.data').resolve()):
        parser.error('Candidate output must stay under services/ai/.data')
    try:
        report = train_candidate(args.dataset, args.output, epochs=args.epochs, seed=args.seed,
                                 acknowledge_source_permission=args.acknowledge_source_permission,
                                 allow_download=args.allow_download)
    except ValueError as error:
        parser.error(str(error))
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()

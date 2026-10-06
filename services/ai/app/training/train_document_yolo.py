"""Train and export the KYC-specific YOLOv8 document detector."""

import argparse
import json
import os
import re
from pathlib import Path

from .prepare_mykad_dataset import inspect_dataset, validate_detector_domain


def train_detector(dataset_yaml, epochs=80, seed=42, domain='document',
                   output_tag=None, require_front_back=False, dry_run=False, overwrite=False):
    # Validate before loading weights/downloading anything. Field models must
    # never replace the whole-card model used by live-scanner geometry checks.
    if not dataset_yaml.is_file():
        raise FileNotFoundError(dataset_yaml)
    names = validate_detector_domain(dataset_yaml, domain)
    if epochs < 1:
        raise ValueError('Epochs must be positive')
    if output_tag and not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_-]{0,48}', output_tag):
        raise ValueError('Output tag must be a short alphanumeric name, not a path')
    field_model = domain == 'fields'
    side_counts = None
    if require_front_back:
        if not field_model or not all(any(name.startswith(f'{side}_') for name in names)
                                      for side in ('front', 'back')):
            raise ValueError('Front/back training requires side-specific front_ and back_ field classes')
        source = dataset_yaml.resolve().parent
        import yaml
        config = yaml.safe_load(dataset_yaml.read_text(encoding='utf-8'))
        if Path(config.get('path', '')).resolve() != source or any(
            config.get(key) != value for key, value in
            (('train', 'train/images'), ('val', 'val/images'), ('test', 'test/images'))
        ):
            raise ValueError('Front/back training requires a self-contained prepared dataset YAML')
        if not (source / 'groups.csv').is_file():
            raise ValueError('Front/back training requires the prepared groups.csv')
        _names, rows, audit = inspect_dataset(source, source / 'groups.csv')
        if audit['originalCrossSplitGroups'] or audit['originalCrossSplitExactDuplicates']:
            raise ValueError('Front/back dataset contains cross-split leakage')
        side_counts = {split: {side: sum(
            row['original_split'] == split and any(names[c].startswith(f'{side}_') for c in row['classes'])
            for row in rows) for side in ('front', 'back')}
            for split in ('train', 'val', 'test')}
        if any(not count for counts in side_counts.values() for count in counts.values()):
            raise ValueError('Every prepared split must contain front and back field examples')
    tag = f'_{output_tag}' if output_tag else ''
    model_name = f'mykad_fields{tag}_yolo' if field_model else f'document{tag}_yolo'
    root = Path(__file__).resolve().parents[2]
    output = root / 'models' / f'{model_name}.pt'
    metrics_path = root / 'metrics' / f'{model_name}_metrics.json'
    if dry_run:
        report = {'dryRun': True, 'artifact': output.name, 'classes': names,
                  'sideSplitImageCounts': side_counts, 'automaticRuntimeActivation': False}
        print(json.dumps(report, indent=2))
        return report
    if not overwrite and (output.exists() or metrics_path.exists()):
        raise FileExistsError('Detector output already exists; use a new --output-tag or explicit --overwrite')
    from ultralytics import YOLO

    result = YOLO('yolov8n.pt').train(
        data=str(dataset_yaml.resolve()),
        epochs=epochs,
        imgsz=640,
        seed=seed,
        project='.data/training_runs',
        name=('renthub_mykad_fields' if field_model else 'renthub_documents') + tag,
        exist_ok=False,
    )
    best = Path(result.save_dir) / 'weights' / 'best.pt'
    output.parent.mkdir(exist_ok=True)
    temporary = output.with_name(f'{output.stem}.tmp.pt')
    temporary.write_bytes(best.read_bytes())
    YOLO(str(temporary))
    os.replace(temporary, output)
    metrics = {}
    for key, value in result.results_dict.items():
        try:
            metrics[key] = float(value)
        except (TypeError, ValueError):
            continue
    (root / 'metrics').mkdir(exist_ok=True)
    metrics_path.write_text(
        json.dumps({
            'model': 'YOLOv8n MyKad field detector' if field_model else 'YOLOv8n document detector',
            'purpose': 'field_localization' if field_model else 'whole_document_detection',
            'seed': seed,
            'artifact': output.name,
            'classes': names,
            'sideSplitImageCounts': side_counts,
            'evaluationSplit': 'validation',
            'automaticRuntimeActivation': False,
            'metrics': metrics,
            'requiredEvaluationSlices': [
                'rotation', 'perspective', 'partial_misalignment',
                'distance_scale', 'lighting',
            ],
            'limitations': 'Detection is not proof of document authenticity. Test-set evaluation is separate.',
        }, indent=2),
        encoding='utf-8',
    )


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('dataset_yaml', type=Path)
    parser.add_argument('--epochs', type=int, default=80)
    parser.add_argument('--seed', type=int, default=42)
    args = parser.parse_args()
    train_detector(args.dataset_yaml, args.epochs, args.seed)


if __name__ == '__main__':
    main()

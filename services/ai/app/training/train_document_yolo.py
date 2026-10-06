"""Train and export the KYC-specific YOLOv8 document detector."""

import argparse
import json
import os
from pathlib import Path

from .prepare_mykad_dataset import validate_detector_domain


def train_detector(dataset_yaml, epochs=80, seed=42, domain='document'):
    # Validate before loading weights/downloading anything. Field models must
    # never replace the whole-card model used by live-scanner geometry checks.
    if not dataset_yaml.is_file():
        raise FileNotFoundError(dataset_yaml)
    validate_detector_domain(dataset_yaml, domain)
    from ultralytics import YOLO

    field_model = domain == 'fields'
    model_name = 'mykad_fields_yolo' if field_model else 'document_yolo'
    result = YOLO('yolov8n.pt').train(
        data=str(dataset_yaml.resolve()),
        epochs=epochs,
        imgsz=640,
        seed=seed,
        project='.data/training_runs',
        name='renthub_mykad_fields' if field_model else 'renthub_documents',
        exist_ok=False,
    )
    best = Path(result.save_dir) / 'weights' / 'best.pt'
    root = Path(__file__).resolve().parents[2]
    output = root / 'models' / f'{model_name}.pt'
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
    (root / 'metrics' / f'{model_name}_metrics.json').write_text(
        json.dumps({
            'model': 'YOLOv8n MyKad field detector' if field_model else 'YOLOv8n document detector',
            'purpose': 'field_localization' if field_model else 'whole_document_detection',
            'seed': seed,
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

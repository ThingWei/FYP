"""Train and export the KYC-specific YOLOv8 document detector."""

import argparse
import json
import os
from pathlib import Path

from ultralytics import YOLO


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('dataset_yaml', type=Path)
    parser.add_argument('--epochs', type=int, default=80)
    parser.add_argument('--seed', type=int, default=42)
    args = parser.parse_args()
    if not args.dataset_yaml.is_file():
        raise FileNotFoundError(args.dataset_yaml)
    result = YOLO('yolov8n.pt').train(
        data=str(args.dataset_yaml),
        epochs=args.epochs,
        imgsz=640,
        seed=args.seed,
        project='training_runs',
        name='renthub_documents',
        exist_ok=True,
    )
    best = Path(result.save_dir) / 'weights' / 'best.pt'
    root = Path(__file__).resolve().parents[2]
    output = root / 'models' / 'document_yolo.pt'
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
    (root / 'metrics' / 'document_yolo_metrics.json').write_text(
        json.dumps({
            'model': 'YOLOv8n document detector',
            'seed': args.seed,
            'datasetYaml': str(args.dataset_yaml),
            'metrics': metrics,
            'requiredEvaluationSlices': [
                'rotation', 'perspective', 'partial_misalignment',
                'distance_scale', 'lighting',
            ],
        }, indent=2),
        encoding='utf-8',
    )


if __name__ == '__main__':
    main()

"""Train the RentHub item detector from an Ultralytics dataset YAML."""

import argparse
import json
from pathlib import Path

from ultralytics import YOLO


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('dataset_yaml', type=Path)
    parser.add_argument('--epochs', type=int, default=60)
    parser.add_argument('--seed', type=int, default=42)
    args = parser.parse_args()
    if not args.dataset_yaml.is_file():
        raise FileNotFoundError(args.dataset_yaml)
    report = args.dataset_yaml.parent / 'preparation_result.json'
    if (args.dataset_yaml.parent / 'selection.json').is_file() and (
        not report.is_file() or not json.loads(report.read_text(encoding='utf-8')).get('trainingReady')
    ):
        raise ValueError('Open Images preparation is incomplete; inspect preparation_result.json before training')
    result = YOLO('yolov8n.pt').train(
        data=str(args.dataset_yaml), epochs=args.epochs, imgsz=640,
        seed=args.seed, project='training_runs', name='renthub_items', exist_ok=True,
    )
    best = Path(result.save_dir) / 'weights' / 'best.pt'
    output = Path(__file__).resolve().parents[2] / 'models' / 'item_yolo.pt'
    output.parent.mkdir(exist_ok=True)
    output.write_bytes(best.read_bytes())


if __name__ == '__main__':
    main()

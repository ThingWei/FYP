"""Train a separate research MyKad field detector, never the card scanner."""

import argparse
from pathlib import Path

from .train_document_yolo import train_detector


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('dataset_yaml', type=Path)
    parser.add_argument('--epochs', type=int, default=80)
    parser.add_argument('--seed', type=int, default=42)
    parser.add_argument('--output-tag')
    parser.add_argument('--require-front-back', action='store_true')
    parser.add_argument('--dry-run', action='store_true')
    parser.add_argument('--overwrite', action='store_true')
    args = parser.parse_args()
    train_detector(args.dataset_yaml, args.epochs, args.seed, domain='fields',
                   output_tag=args.output_tag, require_front_back=args.require_front_back,
                   dry_run=args.dry_run, overwrite=args.overwrite)


if __name__ == '__main__':
    main()

"""Train a separate research MyKad field detector, never the card scanner."""

import argparse
from pathlib import Path

from .train_document_yolo import train_detector


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('dataset_yaml', type=Path)
    parser.add_argument('--epochs', type=int, default=80)
    parser.add_argument('--seed', type=int, default=42)
    args = parser.parse_args()
    train_detector(args.dataset_yaml, args.epochs, args.seed, domain='fields')


if __name__ == '__main__':
    main()

"""Read-only runtime vocabulary audit; does not evaluate real-photo accuracy."""

import argparse
import json

from app.services.item_verification import CONTRACT, models_status


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--require-labels-for-every-category', action='store_true')
    args = parser.parse_args()
    _, _, status = models_status()
    matrix = status['categoryCoverage']
    missing = [f"{row['category']}/{row['subcategory']}" for row in matrix
               if not row['matchingLabels']]
    print(json.dumps({'contract': CONTRACT, 'detectors': status['detectors'],
                      'riskClassifierAvailable': status['riskClassifierAvailable'],
                      'categoryCount': len(matrix), 'categoriesWithoutLabels': missing,
                      'coverage': matrix,
                      'warning': 'Label coverage is not real-photo accuracy or authenticity verification.'},
                     indent=2))
    return 2 if args.require_labels_for_every_category and missing else 0


if __name__ == '__main__':
    raise SystemExit(main())

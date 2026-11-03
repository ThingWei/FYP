"""Evaluate an existing item-risk artifact without fitting, downloads or deployment.

Benchmark mode reuses only the test split of the artifact's fingerprinted source
manifest. Reviewed mode accepts separately reviewed test photos and requires the
original training manifest to check exact-image and declared item-group overlap.
Neither mode establishes document/item authenticity or rightful ownership.
"""

import argparse
import csv
import hashlib
import json
from pathlib import Path

import torch
from PIL import Image
from torchvision import transforms

from .item_risk_data import load_manifest
from .train_image_risk import classification_metrics, ManifestImages
from ..services.item_verification import artifact_path, valid_risk_metadata

ROOT = Path(__file__).resolve().parents[2]
SOURCES = ('synthetic_manipulation', 'reviewed_real')


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def source_splits(path, metadata):
    splits = load_manifest(path)
    fingerprint = hashlib.sha256(path.read_bytes())
    for phase, rows in splits.items():
        for row in rows:
            fingerprint.update(phase.encode())
            fingerprint.update(hashlib.sha256(row['path'].read_bytes()).digest())
    if fingerprint.hexdigest() != metadata.get('datasetFingerprintSha256'):
        raise ValueError('Source manifest does not match the fitted artifact fingerprint')
    return splits, fingerprint.hexdigest()


def read_reviewed(path, splits):
    with path.open(encoding='utf-8-sig', newline='') as stream:
        reader = csv.DictReader(stream)
        rows = []
        for row in reader:
            rows.append(row)
            if len(rows) > 10000:
                raise ValueError('Reviewed evaluation is bounded to 10000 photos')
    if not rows:
        raise ValueError('No reviewed photos supplied; real-photo evaluation is not completed')
    # Exclude every original source item, including the old benchmark test set:
    # reviewing that benchmark again is not independent rental-photo evidence.
    original = [row for selected in splits.values() for row in selected]
    groups = {row['item_id'] for row in original}
    hashes = {digest(row['path']) for row in original}
    seen = set()
    for row in rows:
        if (row.get('reviewed') != 'true' or row.get('permission_confirmed') != 'true'
                or row.get('source_type') != 'reviewed_real' or row.get('split') != 'test'):
            raise ValueError('Each real photo needs review, permission and reviewed_real/test provenance')
        if row.get('label') not in ManifestImages.classes or not row.get('item_id', '').strip():
            raise ValueError('Each photo needs a reviewed item group and normal/risky label')
        if not row.get('label_evidence', '').strip():
            raise ValueError('Each label needs evidence; appearance alone does not establish manipulation')
        if not row.get('path', '').strip():
            raise ValueError('A reviewed image is missing')
        row['path'] = (path.parent / row['path']).resolve()
        content = digest(row['path'])
        if row['item_id'] in groups or content in hashes:
            raise ValueError('Reviewed evaluation overlaps the original artifact dataset')
        if content in seen:
            raise ValueError('Duplicate reviewed image content')
        if row.get('sha256') and row['sha256'] != content:
            raise ValueError('Reviewed image changed after annotation')
        seen.add(content)
    return rows


def metric_cohort(rows, probabilities, threshold):
    if not rows:
        return classification_metrics([], [])
    actual = [int(row['label'] == 'risky') for row in rows]
    report = classification_metrics(actual, [int(p >= threshold) for p in probabilities])
    if len(set(actual)) < 2:
        report['status'] = 'insufficient_class_coverage'
    return report


def evaluate(artifact, training_manifest, reviewed_manifest=None, *, batch_size=16, cpu_threads=4):
    if not 1 <= batch_size <= 64 or not 1 <= cpu_threads <= 64:
        raise ValueError('Batch size and CPU threads must be 1-64')
    artifact, training_manifest = Path(artifact).resolve(), Path(training_manifest).resolve()
    before = digest(artifact)
    torch.set_num_threads(cpu_threads)
    extra = {'metadata.json': ''}
    model = torch.jit.load(str(artifact), map_location='cpu', _extra_files=extra).eval()
    metadata = json.loads(extra['metadata.json'])
    if not valid_risk_metadata(metadata):
        raise ValueError('Incompatible item-risk artifact')
    splits, fingerprint = source_splits(training_manifest, metadata)
    rows = read_reviewed(Path(reviewed_manifest).resolve(), splits) if reviewed_manifest else splits['test']
    if len(rows) > 10000:
        raise ValueError('Evaluation is bounded to 10000 photos')
    transform = transforms.Compose([
        transforms.Resize((224, 224)), transforms.ToTensor(),
        transforms.Normalize([.485, .456, .406], [.229, .224, .225]),
    ])
    probabilities = []
    with torch.inference_mode():
        for start in range(0, len(rows), batch_size):
            tensors = []
            for row in rows[start:start + batch_size]:
                with Image.open(row['path']) as image:
                    tensors.append(transform(image.convert('RGB')))
            logits = model(torch.stack(tensors))
            if logits.shape != (len(tensors), 2) or not torch.isfinite(logits).all():
                raise ValueError('Model must return two finite logits per photo')
            probabilities.extend(logits.softmax(1)[:, 1].tolist())
            if start == 0 or (start + batch_size) % 256 == 0 or start + batch_size >= len(rows):
                print(f'Assessed {min(start + batch_size, len(rows))}/{len(rows)} photos', flush=True)
    def selected_metrics(positions, threshold):
        return metric_cohort([rows[i] for i in positions], [probabilities[i] for i in positions], threshold)

    all_positions = list(range(len(rows)))
    unchanged = digest(artifact) == before
    if not unchanged:
        raise ValueError('Artifact changed during evaluation; report discarded')
    return {
        'mode': 'frozen_artifact_evaluation', 'artifactWritten': False, 'databaseWrites': 0,
        'artifactSha256': before, 'artifactUnchanged': unchanged,
        'sourceManifestFingerprintVerified': True, 'sourceManifestFingerprintSha256': fingerprint,
        'inputManifestSha256': digest(Path(reviewed_manifest)) if reviewed_manifest else digest(training_manifest),
        'evaluationScope': 'reviewed_rental_photos' if reviewed_manifest else 'existing_benchmark_test_only',
        'independence': 'declared_groups_and_exact_hashes_checked_not_independently_verified',
        'thresholds': {'classification': .5, 'productionElevatedRisk': .65},
        'samples': len(rows), 'itemGroups': len({row['item_id'] for row in rows}),
        'classification': selected_metrics(all_positions, .5),
        'productionElevatedRisk': selected_metrics(all_positions, .65),
        'cohorts': {source: {
            'classification': selected_metrics([i for i, r in enumerate(rows) if r['source_type'] == source], .5),
            'productionElevatedRisk': selected_metrics([i for i, r in enumerate(rows) if r['source_type'] == source], .65),
        } for source in SOURCES},
        'datasets': {name: selected_metrics([i for i, r in enumerate(rows)
                                           if r.get('dataset_name', 'unspecified') == name], .5)
                     for name in sorted({r.get('dataset_name', 'unspecified') for r in rows})},
        'limitations': [
            'No fitting, threshold tuning, download or deployment was performed',
            'Normal means no labelled alteration, not verified genuine, owned or good condition',
            'Synthetic/public benchmark results do not establish real rental-photo risk accuracy',
            'Exact hashes and supplied groups cannot detect every related image or mislabeled group',
            'Rights and ground-truth evidence are caller-reviewed, not established by this evaluator',
            'Administrator review remains mandatory; no authenticity/counterfeit claim is supported',
        ],
    }


def new_report(path):
    path = path.resolve()
    if not path.is_relative_to((ROOT / '.data').resolve()) or path.exists():
        raise ValueError('Use a NEW private report under services/ai/.data')
    return path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--training-manifest', type=Path, required=True)
    parser.add_argument('--reviewed-manifest', type=Path)
    parser.add_argument('--artifact', type=Path, default=artifact_path('IMAGE_RISK_MODEL_PATH', 'models/image_risk_efficientnet.pt'))
    parser.add_argument('--report', type=Path, required=True)
    parser.add_argument('--batch-size', type=int, default=16)
    parser.add_argument('--cpu-threads', type=int, default=4)
    args = parser.parse_args()
    try:
        report_path = new_report(args.report)
        report = evaluate(args.artifact, args.training_manifest, args.reviewed_manifest,
                          batch_size=args.batch_size, cpu_threads=args.cpu_threads)
        report_path.parent.mkdir(parents=True, exist_ok=True)
        with report_path.open('x', encoding='utf-8') as stream:
            json.dump(report, stream, indent=2, allow_nan=False)
    except (ValueError, OSError, KeyError, RuntimeError):
        parser.error('Risk evaluation failed; check the artifact, reviewed manifest and source fingerprint. No model was written')
    print(json.dumps(report, indent=2, allow_nan=False))


if __name__ == '__main__':
    main()

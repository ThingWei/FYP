"""Preview/generate paired synthetic ITEM alterations from local YOLO annotations.

No authenticity labels are inferred from object names. Default is read-only.
Original split boundaries are retained. Source-image hashes are proxy groups,
NOT verified physical-item identities; independent real evaluation is required.
"""

import argparse
import csv
import hashlib
import io
import json
import random
from collections import Counter
from pathlib import Path

import yaml
from PIL import Image, ImageDraw, ImageEnhance, ImageStat

from app.training.evaluate_item_recognition import LABEL_DOMAINS
from app.services.item_verification import DOMAINS

OPERATIONS = ('object_patch_erase', 'object_patch_copy_move')
ROOT = Path(__file__).resolve().parents[2]


def plan_dataset(dataset, per_class=10):
    config = yaml.safe_load(dataset.read_text(encoding='utf-8-sig'))
    root = Path(config.get('path', dataset.parent))
    if not root.is_absolute():
        root = dataset.parent / root
    names = config['names']
    names = names if isinstance(names, list) else [names[i] for i in range(len(names))]
    counts, hashes, rows = Counter(), {}, []
    for key, split in (('train', 'train'), ('val', 'validation'), ('test', 'test')):
        directory = root / config[key]
        if directory.parent.name != 'images' or not directory.is_dir():
            raise ValueError('Expected local YOLO images/train, images/val and images/test directories')
        labels = directory.parent.parent / 'labels' / directory.name
        for annotation in sorted(labels.glob('*.txt')):
            candidates = []
            for line in annotation.read_text().splitlines():
                if not line.strip():
                    continue
                class_id, x, y, width, height = map(float, line.split())
                if class_id != int(class_id) or not 0 <= class_id < len(names):
                    raise ValueError('Invalid annotation class')
                label = names[int(class_id)]
                if label not in LABEL_DOMAINS:
                    continue  # Never use KYC/document fields as item-risk sources.
                box = (x - width / 2, y - height / 2, x + width / 2, y + height / 2)
                # YOLO decimal text can round a boundary by ~1e-10. Tolerate only
                # serialization noise, never an actually out-of-image region.
                if not (all(-1e-7 <= v <= 1 + 1e-7 for v in box) and width > 0 and height > 0):
                    raise ValueError('Invalid object box')
                box = tuple(max(0, min(1, v)) for v in box)
                candidates.append((width * height, label, box))
            if not candidates:
                continue
            _, label, box = max(candidates)
            if counts[split, label] >= per_class:
                continue
            image = next((directory / (annotation.stem + ext) for ext in ('.jpg', '.jpeg', '.png')
                          if (directory / (annotation.stem + ext)).is_file()), None)
            if image is None:
                raise ValueError('Missing item source image')
            digest = hashlib.sha256(image.read_bytes()).hexdigest()
            if digest in hashes:
                if hashes[digest] != split:
                    raise ValueError('Source image leakage across original splits')
                continue
            hashes[digest] = split
            category, subcategory = LABEL_DOMAINS[label]
            rows.append({'path': image, 'group': digest, 'split': split,
                         'category': category, 'subcategory': subcategory, 'box': box})
            counts[split, label] += 1
    represented = {(row['category'].lower(), row['subcategory'].lower()) for row in rows}
    report = {'purpose': 'synthetic_item_manipulation_research_not_authenticity',
              'sourceGroups': len(rows), 'plannedImages': len(rows) * len(OPERATIONS) * 2,
              'splitGroups': dict(Counter(row['split'] for row in rows)),
              'categoryGroups': dict(Counter(f"{row['category']}/{row['subcategory']}" for row in rows)),
              'unrepresentedDomains': [f'{category}/{sub}' for category, subs in DOMAINS.items()
                                       for sub in subs if (category, sub) not in represented],
              'itemLevelGroupingVerified': False, 'sourceAuthenticityVerified': False,
              'labelDefinitions': {
                  'normal': 'No controlled local edit; NOT verified genuine, owned or risk-free',
                  'risky': 'Known procedural object-region edit; NOT real-world counterfeit evidence'},
              'warnings': ['Source hashes cannot identify the same physical item across different photos',
                           'Review rights, source groups, near duplicates and generated edits before training',
                           'Both labels have shared capture transforms and research watermarks',
                           'Synthetic held-out performance is not real-world manipulation accuracy']}
    return rows, report


def generate(rows, output, seed=42):
    if len(rows) < 20 or {r['split'] for r in rows} != {'train', 'validation', 'test'}:
        raise ValueError('Need at least 20 source groups spanning all three splits')
    if output.exists() and any(output.iterdir()):
        raise ValueError('Use a new empty output directory; existing datasets are never overwritten')
    output.mkdir(parents=True, exist_ok=True)
    manifest, seen = [], set()
    for row in rows:
        with Image.open(row['path']) as original:
            if original.width * original.height > 60_000_000:
                raise ValueError('Source exceeds pixel safety limit')
            original = original.convert('RGB')
            original.thumbnail((1024, 1024))
        for operation in OPERATIONS:
            rng = random.Random(f"{seed}:{row['group']}:{operation}")
            baseline, changed = original.copy(), original.copy()
            w, h = original.size
            x1, y1, x2, y2 = row['box']
            left, top = int(w * (x1 + (x2 - x1) * .35)), int(h * (y1 + (y2 - y1) * .35))
            pw, ph = max(4, int(w * (x2 - x1) * .22)), max(4, int(h * (y2 - y1) * .22))
            bounds = (left, top, min(w, left + pw), min(h, top + ph))
            if bounds[2] <= left or bounds[3] <= top or (operation == 'object_patch_copy_move' and (left <= 0 or top <= 0)):
                continue
            if operation == 'object_patch_erase':
                mean = tuple(round(v) for v in ImageStat.Stat(changed.crop(bounds)).mean)
                ImageDraw.Draw(changed).rectangle(bounds, fill=mean)
            else:
                source = (max(0, left - pw), max(0, top - ph), left, top)
                patch = changed.crop(source).resize((bounds[2] - left, bounds[3] - top))
                changed.paste(patch, (left, top))
            brightness, angle = rng.uniform(.9, 1.1), rng.uniform(-2, 2)
            quality = rng.randint(82, 94)
            pair = []
            for image in (baseline, changed):
                image = ImageEnhance.Brightness(image).enhance(brightness).rotate(angle)
                ImageDraw.Draw(image).text((8, 8), 'RENTHUB SYNTHETIC RESEARCH', fill=(240, 240, 240))
                buffer = io.BytesIO()
                image.save(buffer, format='JPEG', quality=quality)
                pair.append(buffer.getvalue())
            if pair[0] == pair[1]:
                continue  # Never label a no-op risky.
            if any(hashlib.sha256(data).hexdigest() in seen for data in pair):
                continue
            for label, data in zip(('normal', 'risky'), pair):
                seen.add(hashlib.sha256(data).hexdigest())
                name = f"{row['group'][:24]}-{operation}-{label}.jpg"
                path = output / row['split'] / name
                path.parent.mkdir(exist_ok=True)
                path.write_bytes(data)
                manifest.append({'path': path.relative_to(output).as_posix(), 'label': label,
                                 'item_id': row['group'], 'split': row['split'],
                                 'source_type': 'synthetic_manipulation', 'category': row['category'],
                                 'subcategory': row['subcategory'], 'operation': operation,
                                 'grouping_scope': 'source_image_proxy_not_verified_item'})
    if len(manifest) < 40 or {row['split'] for row in manifest} != {'train', 'validation', 'test'}:
        raise ValueError('Insufficient non-no-op pairs; do not train this output')
    with (output / 'manifest.csv').open('w', encoding='utf-8', newline='') as stream:
        writer = csv.DictWriter(stream, fieldnames=list(manifest[0]))
        writer.writeheader()
        writer.writerows(manifest)
    return {'generatedImages': len(manifest), 'source_type': 'synthetic_manipulation',
            'independentRealEvaluationPerformed': False, 'trained': False}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('dataset_yaml', type=Path)
    parser.add_argument('--output', type=Path, default=ROOT / '.data/datasets/item_synthetic_risk_v1')
    parser.add_argument('--per-class', type=int, default=10)
    parser.add_argument('--seed', type=int, default=42)
    parser.add_argument('--generate', action='store_true')
    parser.add_argument('--acknowledge-source-permission', action='store_true')
    args = parser.parse_args()
    if not 1 <= args.per_class <= 100:
        parser.error('per-class must be 1–100')
    if args.generate and not args.acknowledge_source_permission:
        parser.error('Generation requires --acknowledge-source-permission after reviewing source rights')
    rows, report = plan_dataset(args.dataset_yaml.resolve(), args.per_class)
    report['mode'] = 'read_only_preview'
    if args.generate:
        report.update(generate(rows, args.output.resolve(), args.seed), mode='generated_not_trained')
        (args.output / 'preparation_result.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()

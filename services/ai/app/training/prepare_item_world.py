"""Explicit one-time download/embedding, never run from the API or launcher."""

import argparse
import hashlib
import json
from pathlib import Path
import os
from urllib.parse import urlparse

from app.services import item_world as world
from app.training.prepare_open_images import fetch

BASE_URL = 'https://github.com/ultralytics/assets/releases/download/v8.3.0/yolov8s-worldv2.pt'


def output_path():
    output = world.artifact_path()
    protected = set()
    for key, default in (
        ('YOLO_MODEL_PATH', 'models/item_yolo.pt'),
        ('ITEM_PRETRAINED_YOLO_PATH', 'yolov8n.pt'),
        ('DOCUMENT_YOLO_MODEL_PATH', 'models/document_yolo.pt'),
        ('MYKAD_FIELD_MODEL_PATH', 'models/mykad_fields_front_back_yolo.pt'),
        ('MYKAD_FIELD_RISK_MODEL_PATH', 'models/document_risk_synthetic_fields_v2_efficientnet.pt'),
        ('IMAGE_RISK_MODEL_PATH', 'models/image_risk_efficientnet.pt'),
        ('DOCUMENT_RISK_MODEL_PATH', 'models/document_risk_efficientnet.pt')):
        path = Path(os.getenv(key, default))
        protected.add((path if path.is_absolute() else world.ROOT / path).resolve())
    if output.suffix != '.pt' or output.resolve() in protected:
        raise ValueError('Use a separate .pt output; existing trained detectors/risk models are protected')
    return output


def sha256(path):
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        while block := stream.read(1024 * 1024):
            digest.update(block)
    return digest.hexdigest()


def prepare(download=False):
    output = output_path()
    import clip
    import torch
    from ultralytics import YOLOWorld

    root = world.ROOT / '.data/item-world'
    base = root / 'yolov8s-worldv2.pt'
    clip_url = clip.clip._MODELS['ViT-B/32']
    parsed = urlparse(clip_url)
    if parsed.scheme != 'https' or parsed.hostname != 'openaipublic.azureedge.net':
        raise ValueError('Unexpected CLIP download origin')
    clip_path = root / 'ViT-B-32.pt'
    for path, url, cap in ((base, BASE_URL, 100 * 1024**2),
                           (clip_path, clip_url, 425 * 1024**2)):
        if not path.is_file():
            if not download:
                raise ValueError('Missing preparation weights; use --download explicitly')
            fetch(url, path, cap)
    expected_clip_hash = parsed.path.split('/')[-2]
    if sha256(clip_path) != expected_clip_hash:
        raise ValueError('CLIP checksum mismatch; artifact was not replaced')
    model = YOLOWorld(str(base))
    # Supplying a local model avoids hidden CLIP package/weight downloads.
    model.model.clip_model = clip.load(str(clip_path), device='cpu', jit=False)[0].eval()
    with torch.inference_mode():
        model.set_classes([text for text, _ in world.PROMPTS])
    model.model.names = [label for _, label in world.PROMPTS]
    model.model.clip_model = None  # Runtime contains embeddings, not the CLIP encoder.
    model.ckpt['renthub_item_world'] = {
        'contract': world.CONTRACT, 'vocabularyHash': world.vocabulary_hash(),
        'baseSource': BASE_URL, 'baseSha256': sha256(base),
        'clipSource': clip_url, 'clipSha256': expected_clip_hash,
        'purpose': 'advisory_object_type_not_authenticity',
        'evaluationStatus': 'real_photo_evaluation_required',
    }
    output.parent.mkdir(parents=True, exist_ok=True)
    pending = output.with_name(output.stem + '.pending.pt')
    model.save(str(pending))
    world.load_world.cache_clear()
    loaded = world.load_world(pending, pending.stat().st_mtime_ns)
    import numpy as np
    result = loaded.predict(np.full((320, 320, 3), 128, dtype=np.uint8),
                            conf=.55, verbose=False, device='cpu', max_det=20)
    if len(result) != 1:
        raise ValueError('Export inference smoke test failed; previous artifact preserved')
    pending.replace(output)
    world.load_world.cache_clear()
    return {'contract': world.CONTRACT, 'artifact': output.name,
            'sha256': sha256(output), 'promptCount': len(world.PROMPTS),
            'prepared': True, 'realPhotoEvaluationPerformed': False,
            'advisoryOnly': True}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--download', action='store_true')
    args = parser.parse_args()
    print(json.dumps(prepare(args.download), indent=2))


if __name__ == '__main__':
    main()

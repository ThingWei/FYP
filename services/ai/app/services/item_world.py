"""Optional frozen-vocabulary YOLO-World. Runtime never encodes/downloads text."""

import hashlib
import json
import os
from functools import lru_cache
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CONTRACT = 'renthub-item-world-offline-v1'
SOURCE = 'yolo_world_pretrained'
# All domains compete in ONE fixed vocabulary. Never force only the requested
# category at inference, which could turn unrelated objects into target matches.
OBJECTS = (
    'cell phone', 'camera', 'laptop', 'desktop computer', 'speaker', 'headphones',
    'microphone', 'amplifier', 'game console', 'game controller', 'tv', 'projector',
    'tablet', 'printer', 'car', 'motorcycle', 'scooter', 'bicycle', 'truck', 'bus',
    'van', 'boat', 'drill', 'hammer', 'saw', 'wrench', 'screwdriver', 'sports ball',
    'tennis racket', 'baseball bat', 'baseball glove', 'skateboard', 'surfboard',
    'skis', 'snowboard', 'kayak', 'dumbbell', 'chair', 'table', 'tent', 'stage light',
    'generator', 'ladder', 'pressure washer', 'vacuum cleaner', 'book', 'suit',
    'tuxedo', 'dress', 'costume', 'baju melayu', 'baju kurung', 'kebaya', 'sari',
    'shirt', 'coat', 'jacket',
)
PROMPTS = tuple((label, label) for label in OBJECTS) + (
    ('open book', 'book'),
    # Competing/non-item classes are retained as context, never item evidence.
    ('book page', 'detail page'), ('poster', 'poster'), ('cartoon illustration', 'illustration'),
    ('computer screen', 'screen'), ('photograph', 'photograph'),
    ('person', 'person'), ('sheet of paper', 'paper'), ('credit card', 'credit card'),
)


def vocabulary_hash():
    return hashlib.sha256(json.dumps(PROMPTS, separators=(',', ':')).encode()).hexdigest()


def artifact_path():
    path = Path(os.getenv('ITEM_WORLD_MODEL_PATH', 'models/item_world_offline.pt'))
    return path if path.is_absolute() else ROOT / path


@lru_cache(maxsize=2)
def load_world(path, stamp):
    import torch
    from ultralytics import YOLOWorld
    from ultralytics.nn.tasks import WorldModel

    if not path.is_file():
        raise ValueError('Prepared local artifact required')
    model = YOLOWorld(str(path))
    metadata = model.ckpt.get('renthub_item_world', {})
    expected = [label for _, label in PROMPTS]
    names = model.names
    names = list(names.values()) if isinstance(names, dict) else list(names)
    features = getattr(model.model, 'txt_feats', None)
    if (model.task != 'detect' or not isinstance(model.model, WorldModel) or
            metadata.get('contract') != CONTRACT or
            metadata.get('vocabularyHash') != vocabulary_hash() or names != expected or
            not isinstance(features, torch.Tensor) or features.shape != (1, len(PROMPTS), 512) or
            not torch.isfinite(features).all() or
            not torch.all(features.norm(dim=-1) > 0)):
        raise ValueError('Unprepared or incompatible YOLO-World artifact')
    # No set_classes(), clip.load(), mutable per-request prompts or downloads.
    model.model.clip_model = None
    return model


def availability():
    path = artifact_path()
    status = {'enabled': os.getenv('ITEM_WORLD_ENABLED', 'true').lower() == 'true',
              'available': False, 'source': SOURCE, 'version': None,
              'contract': CONTRACT, 'vocabularyHash': vocabulary_hash(),
              'evaluationStatus': 'real_photo_evaluation_required',
              'advisoryOnly': True, 'issue': None}
    if not status['enabled']:
        status['issue'] = 'disabled'
        return None, status
    if not path.is_file():
        status['issue'] = 'prepared_artifact_missing'
        return None, status
    try:
        model = load_world(path, path.stat().st_mtime_ns)
        status.update(available=True, version=path.name)
        return model, status
    except Exception:
        status['issue'] = 'incompatible_or_load_failed'
        return None, status

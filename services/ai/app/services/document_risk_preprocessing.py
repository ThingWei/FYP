"""Shared training/inference field crops; never infer a label-dependent region."""

import json
import math

from PIL import Image, ImageOps


def parse_region(value, image_size):
    try:
        box = json.loads(value) if isinstance(value, str) else value
        if not isinstance(box, (list, tuple)) or len(box) != 4 or any(
            isinstance(v, bool) or not isinstance(v, (int, float)) or not math.isfinite(v)
            for v in box
        ):
            raise ValueError
        x1, y1, x2, y2 = box
        width, height = image_size
        if not (0 <= x1 < x2 <= width and 0 <= y1 < y2 <= height):
            raise ValueError
        return tuple(box)
    except (ValueError, TypeError, json.JSONDecodeError):
        raise ValueError('Invalid or missing field region_xyxy') from None


def crop_field(image, box, padding):
    x1, y1, x2, y2 = parse_region(box, image.size)
    dx, dy = (x2 - x1) * padding, (y2 - y1) * padding
    return image.crop((max(0, math.floor(x1 - dx)), max(0, math.floor(y1 - dy)),
                       min(image.width, math.ceil(x2 + dx)),
                       min(image.height, math.ceil(y2 + dy))))


class Letterbox:
    def __init__(self, size):
        self.size = size

    def __call__(self, image):
        return ImageOps.pad(image, (self.size, self.size),
                            method=Image.Resampling.BILINEAR, color=(127, 127, 127))


def validate_field_contract(provenance):
    """Reject missing/unknown preprocessing rather than misusing a whole-image model."""
    if not isinstance(provenance, dict) or provenance.get('containsSyntheticManipulations') is not True:
        raise ValueError('A labelled synthetic research artifact is required')
    if provenance.get('purpose') != 'synthetic_manipulation_risk_research':
        raise ValueError('Unexpected risk artifact purpose')
    contract = provenance.get('inputContract')
    if not isinstance(contract, dict) or contract.get('inputMode') != 'fields' or \
            contract.get('resize') != 'aspect_preserving_letterbox' or \
            contract.get('runtimeCompatibleWithoutAdapter') is not False or \
            contract.get('regionSource') != 'manifest_annotations_not_automatic_detection':
        raise ValueError('Incompatible field risk preprocessing contract')
    size, padding = contract.get('imageSize'), contract.get('cropPadding')
    if type(size) is not int or not 64 <= size <= 1024 or \
            isinstance(padding, bool) or not isinstance(padding, (float, int)) or \
            not math.isfinite(padding) or not 0 <= padding <= 1:
        raise ValueError('Invalid field risk dimensions or context padding')
    if contract.get('normalizationMean') != [0.485, 0.456, 0.406] or \
            contract.get('normalizationStd') != [0.229, 0.224, 0.225]:
        raise ValueError('Unsupported field risk normalization')
    return contract


def field_tensor(rgb_image, box, contract):
    from torchvision import transforms

    transform = transforms.Compose([
        Letterbox(contract['imageSize']), transforms.ToTensor(),
        transforms.Normalize(contract['normalizationMean'], contract['normalizationStd']),
    ])
    return transform(crop_field(rgb_image, box, contract['cropPadding']))

"""Conservative photo-context warnings, never authenticity or rejection verdicts.

No OCR text, identity data, network requests or additional models are used.
Line-art heuristics are diagnostic only; ordinary photographs and cropped copies
can remain indistinguishable. Book pages can legitimately be supporting views.
"""
import math

from .item_domains import PRODUCT_TYPES


# Explicit existing object-type aliases, never fuzzy similarity or expected-only
# prompts. The same type used in several domains retains one semantic identity.
LABEL_TYPES = {}
for subcategories in PRODUCT_TYPES.values():
    for types in subcategories.values():
        for kind, aliases in types.items():
            for alias in aliases:
                LABEL_TYPES.setdefault(alias, set()).add(kind)


DEPICTED_CONTEXT = {'paper', 'poster', 'illustration', 'screen',
                    'credit card', 'detail page'}


def document_layout(image):
    """Flag strongly flat, monochrome, multi-box layouts for human inspection.

    This is NOT a general screenshot detector. Several independent layout signals
    are required; grayscale alone, text alone or one rectangle is insufficient.
    """
    import cv2
    import numpy as np

    height, width = image.shape[:2]
    if min(height, width) < 96:
        return {'status': 'not_assessed', 'reason': 'insufficient_layout_resolution'}
    scale = min(1., 960. / max(height, width))
    scene = cv2.resize(image, (round(width * scale), round(height * scale))) if scale < 1 else image
    gray = cv2.cvtColor(scene, cv2.COLOR_BGR2GRAY)
    monochrome = float((scene.max(axis=2).astype('int16') - scene.min(axis=2) <= 12).mean())
    flat = float((np.abs(cv2.Laplacian(gray, cv2.CV_32F)) <= 3).mean())
    if monochrome < .97 or flat < .80:
        return {'status': 'not_detected', 'absenceProvesPhotograph': False}
    edges = cv2.Canny(gray, 60, 160)
    h, w = gray.shape
    horizontal = cv2.morphologyEx(edges, cv2.MORPH_OPEN,
                                  cv2.getStructuringElement(cv2.MORPH_RECT, (max(20, w // 12), 1)))
    vertical = cv2.morphologyEx(edges, cv2.MORPH_OPEN,
                                cv2.getStructuringElement(cv2.MORPH_RECT, (1, max(20, h // 12))))
    line_fraction = float(np.count_nonzero(horizontal | vertical) / max(1, np.count_nonzero(edges)))
    contours, _ = cv2.findContours(edges, cv2.RETR_LIST, cv2.CHAIN_APPROX_SIMPLE)
    rectangles = 0
    for contour in contours:
        area = cv2.contourArea(contour) / (h * w)
        if .0015 <= area <= .90:
            polygon = cv2.approxPolyDP(contour, .025 * cv2.arcLength(contour, True), True)
            if len(polygon) == 4 and cv2.isContourConvex(polygon):
                rectangles += 1
    detected = rectangles >= 6 and line_fraction >= .20
    return {'status': 'possible_document_layout' if detected else 'not_detected',
            'signals': {'flatMonochrome': True, 'multipleRectangles': rectangles >= 6,
                        'longStraightLines': line_fraction >= .20},
            'absenceProvesPhotograph': False}


def valid_box(value):
    return (isinstance(value, (list, tuple)) and len(value) == 4
            and all(isinstance(v, (int, float)) and math.isfinite(v) and 0 <= v <= 1 for v in value)
            and value[0] < value[2] and value[1] < value[3])


def overlapping_region(first, second):
    """The same or contained region, not an unrelated nearby object."""
    if not valid_box(first) or not valid_box(second):
        return False
    overlap = max(0., min(first[2], second[2]) - max(first[0], second[0])) * max(
        0., min(first[3], second[3]) - max(first[1], second[1]))
    area = min((first[2] - first[0]) * (first[3] - first[1]),
               (second[2] - second[0]) * (second[3] - second[1]))
    return overlap / area >= .80


def upright_regions(detection):
    values = detection.get('uprightEvidence', [])
    if not isinstance(values, list):
        values = []
    result = [row['boundingBox'] for row in values[:20] if isinstance(row, dict)
              and valid_box(row.get('boundingBox'))]
    if detection.get('rotationDegrees') == 0 and valid_box(detection.get('boundingBox')):
        result.append(detection['boundingBox'])
    return result


def rotation_conflicts(detection, detections):
    """Rotation-only matches with overlapping, different upright hypotheses.

    Scores from different models are not calibrated against each other. This
    marks ambiguous evidence for review, not a finding of wrong/fake content.
    Legitimately sideways photos with no contradictory upright object still work.
    """
    if detection.get('rotationDegrees', 0) == 0 or not valid_box(detection.get('boundingBox')):
        return []
    family = LABEL_TYPES.get(detection['label'].casefold(), set())
    if not family:
        return []
    box = detection['boundingBox']
    if any(family & LABEL_TYPES.get(other['label'].casefold(), set()) and
           any(overlapping_region(box, region) for region in upright_regions(other))
           for other in detections):
        return []
    return sorted({other['label'] for other in detections
                   if LABEL_TYPES.get(other['label'].casefold(), set()) and
                   not family & LABEL_TYPES[other['label'].casefold()] and
                   any(overlapping_region(box, region) for region in upright_regions(other))})


def annotate_context(detections, layout):
    """Retain raw scores, but don't count a depicted/document region as a match."""
    conflicts = [d for d in detections if d['label'].casefold() in DEPICTED_CONTEXT
                 and valid_box(d.get('boundingBox'))]
    flagged = False
    rotation_flagged = False
    for detection in detections:
        if not detection.get('matchesCategory'):
            continue
        detection['matchesExpectedLabel'] = True
        box = detection.get('boundingBox')
        conflict = layout.get('status') == 'possible_document_layout'
        if valid_box(box):
            area = (box[2] - box[0]) * (box[3] - box[1])
            for context in conflicts:
                other = context['boundingBox']
                overlap = max(0., min(box[2], other[2]) - max(box[0], other[0])) * max(
                    0., min(box[3], other[3]) - max(box[1], other[1]))
                # A nearby sheet/display must not invalidate an unrelated item.
                if overlap / area >= .80:
                    conflict = True
        competing = rotation_conflicts(detection, detections)
        if competing:
            detection['rotationReviewRequired'] = True
            detection['competingUprightLabels'] = competing
            rotation_flagged = True
        if conflict or competing:
            detection['matchesCategory'] = False
            detection['contextReviewRequired'] = True
        if conflict:
            flagged = True
    depicted = flagged or layout.get('status') == 'possible_document_layout'
    return {'status': 'needs_review' if depicted or rotation_flagged
            else 'not_established', 'layout': layout,
            'rotationEvidenceReviewRequired': rotation_flagged,
            'depictedContentReviewRequired': depicted,
            'listingRelevanceVerified': False, 'physicalItemVerified': False}

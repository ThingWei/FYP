"""Conservative photo-context warnings, never authenticity or rejection verdicts.

No OCR text, identity data, network requests or additional models are used.
Line-art heuristics are diagnostic only; ordinary photographs and cropped copies
can remain indistinguishable. Book pages can legitimately be supporting views.
"""
import math


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


def annotate_context(detections, layout):
    """Retain raw scores, but don't count a depicted/document region as a match."""
    conflicts = [d for d in detections if d['label'].casefold() in DEPICTED_CONTEXT
                 and valid_box(d.get('boundingBox'))]
    flagged = False
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
        if conflict:
            detection['matchesCategory'] = False
            detection['contextReviewRequired'] = True
            flagged = True
    return {'status': 'needs_review' if flagged or layout.get('status') == 'possible_document_layout'
            else 'not_established', 'layout': layout,
            'listingRelevanceVerified': False, 'physicalItemVerified': False}

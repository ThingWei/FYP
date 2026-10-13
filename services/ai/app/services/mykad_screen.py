"""Conservative enclosing-device screening; not replay/liveness certification."""
import math
from .item_verification import detector_selection, load_detector, DETECTOR_LOCK, normalize

PHONE_LABELS = {'cell phone', 'mobile phone', 'smartphone', 'phone'}
def enclosing_phone(phone_box, card_box, confidence):
    if not math.isfinite(confidence) or confidence < .85:
        return False, {}
    px1, py1, px2, py2 = phone_box
    cx1, cy1, cx2, cy2 = card_box
    width, height = px2 - px1, py2 - py1
    card_area = (cx2 - cx1) * (cy2 - cy1)
    if min(width, height, card_area) <= 0 or not all(math.isfinite(v) for v in (*phone_box, *card_box)):
        return False, {}
    overlap = max(0, min(px2, cx2) - max(px1, cx1)) * max(0, min(py2, cy2) - max(py1, cy1))
    coverage, area_ratio, aspect = overlap / card_area, width * height / card_area, max(width, height) / min(width, height)
    metrics = {'confidence': round(confidence, 4), 'cardCoverage': round(coverage, 4),
               'areaRatio': round(area_ratio, 4), 'aspectRatio': round(aspect, 4)}
    return coverage >= .90 and area_ratio >= 1.5 and aspect >= 1.8, metrics

def phone_screen_evidence(image, card_box):
    evidence = {'method': 'enclosing-phone-v1', 'status': 'unavailable',
                'absenceProvesPhysicalCard': False}
    try:
        path, source = detector_selection()
        if not path.is_file():
            return evidence
        detector = load_detector(path, path.stat().st_mtime_ns)
        names = detector.names.values() if isinstance(detector.names, dict) else detector.names
        if not PHONE_LABELS.intersection(normalize(str(label)) for label in names):
            return evidence
        with DETECTOR_LOCK:
            prediction = detector.predict(image, verbose=False, conf=.85, max_det=50)[0]
        evidence.update(status='not_detected', source=source)
        if prediction.boxes is None:
            return evidence
        for box in prediction.boxes:
            label = normalize(str(prediction.names[int(box.cls.item())]))
            if label not in PHONE_LABELS:
                continue
            found, metrics = enclosing_phone(box.xyxy[0].tolist(), card_box, float(box.conf.item()))
            if found:
                evidence.update(status='detected', evidence=metrics)
                break
    except Exception:
        evidence.update(status='unavailable')
    return evidence


"""Policy/geometry fixtures, not real-photo recognition accuracy evidence."""
import cv2
import numpy as np
import pytest

from app.services.item_photo_context import document_layout, annotate_context
from app.services import item_verification as items
from test_item_verification import Detector, verify


def diagram():
    scene = np.full((700, 500, 3), 245, dtype=np.uint8)
    for row in range(6):
        for column in range(2):
            x, y = 35 + column * 260, 30 + row * 105
            cv2.rectangle(scene, (x, y), (x + 165, y + 55), (25, 25, 25), 2)
            cv2.putText(scene, 'Action', (x + 10, y + 30), cv2.FONT_HERSHEY_SIMPLEX, .4, (20, 20, 20), 1)
            if row < 5:
                cv2.line(scene, (x + 80, y + 55), (x + 80, y + 105), (25, 25, 25), 1)
    return scene


def detection(label, matched, box):
    return {'label': label, 'matchesCategory': matched, 'confidence': .99,
            'boundingBox': box}


def test_multi_signal_document_layout_is_not_a_quality_or_authenticity_verdict():
    result = document_layout(diagram())
    assert result['status'] == 'possible_document_layout'
    assert all(result['signals'].values())
    assert result['absenceProvesPhotograph'] is False
    assert document_layout(np.full((700, 500, 3), 245, dtype=np.uint8))['status'] == 'not_detected'
    assert document_layout(np.random.default_rng(42).integers(0, 256, (400, 500, 3), dtype=np.uint8))['status'] == 'not_detected'
    assert document_layout(np.zeros((20, 20, 3), dtype=np.uint8))['status'] == 'not_assessed'


@pytest.mark.parametrize('label', ['paper', 'screen', 'illustration', 'poster', 'detail page'])
def test_overlapping_depicted_context_retains_score_but_not_category_match(label):
    guesses = [detection('cell phone', True, [.2, .2, .8, .8]),
               detection(label, False, [.1, .1, .9, .9])]
    context = annotate_context(guesses, {'status': 'not_detected'})
    assert context['status'] == 'needs_review'
    assert not guesses[0]['matchesCategory']
    assert guesses[0]['matchesExpectedLabel'] is True
    assert guesses[0]['confidence'] == .99
    assert not context['physicalItemVerified'] and not context['listingRelevanceVerified']


def test_nearby_screen_or_invalid_box_does_not_disprove_an_item():
    guesses = [detection('cell phone', True, [.1, .1, .4, .8]),
               detection('screen', False, [.6, .1, .9, .8]),
               detection('paper', False, [0, 0, float('nan'), 1])]
    assert annotate_context(guesses, {'status': 'not_detected'})['status'] == 'not_established'
    assert guesses[0]['matchesCategory'] is True


def test_primary_high_score_cannot_skip_competing_context_model():
    class BoxDetector(Detector):
        def predict(self, image, **kwargs):
            result = super().predict(image, **kwargs)
            for box in result[0].boxes:
                box.xyxy = np.array([[1, 1, 9, 9]])
            return result

    primary = BoxDetector(['cell phone'], score=.99)
    context = BoxDetector(['cell phone', 'paper'], detected=['paper'])
    detections, attempts, failures = items.detect_photo(np.zeros((10, 10, 3), dtype=np.uint8),
        {'cell phone'}, [(primary, 'configured_item_model', 'a'),
                        (context, 'yolo_world_pretrained', 'b')])
    assert attempts == 2 and failures == 0
    assert {d['label'] for d in detections} == {'cell phone', 'paper'}
    assert annotate_context(detections, {'status': 'not_detected'})['status'] == 'needs_review'


@pytest.mark.parametrize('category,subcategory,label', [
    (category, subcategory, sorted(labels)[0])
    for category, domains in items.DOMAINS.items() for subcategory, labels in domains.items()
])
def test_document_layout_blocks_positive_match_without_rejecting_detail_uploads(
        monkeypatch, category, subcategory, label):
    # Exercise the actual verifier's context integration with controlled pixels.
    from app.services import item_photo_context as context
    monkeypatch.setattr(context, 'document_layout', lambda _: {'status': 'possible_document_layout'})
    result = verify(monkeypatch, category=category, subcategory=subcategory,
                    detector=Detector([label], score=.99))
    assert result.outcome == 'warning' and not result.accepted
    assert result.confidence == 0
    assert result.extracted_fields['categoryMatched'] is None
    assert result.extracted_fields['categoryMatchStatus'] == 'context_needs_review'
    assert result.extracted_fields['matchingViewCount'] == 0
    assert result.extracted_fields['photoContextReviewRequired'] is True
    assert result.extracted_fields['adminReviewRequired'] is True
    assert all(photo['objectEvidenceStatus'] == 'context_needs_review'
               for photo in result.extracted_fields['images'])
    assert not any('blurry' in reason.lower() for reason in result.reasons)

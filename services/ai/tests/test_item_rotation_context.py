"""Generated policy fixtures, not additional real-photo accuracy evidence."""
from types import SimpleNamespace

import numpy as np
import pytest

from app.services import item_verification as items
from app.services.item_photo_context import annotate_context
from test_item_verification import Detector, verify


def guess(label, matched, box, rotation=0, confidence=.9):
    return {'label': label, 'matchesCategory': matched, 'boundingBox': box,
            'rotationDegrees': rotation, 'confidence': confidence, 'source': 'fixture'}


@pytest.mark.parametrize('target,other', [
    ('mouse', 'headphones'), ('headphones', 'mouse'), ('game controller', 'mouse'),
    ('cell phone', 'book'), ('motorcycle', 'car'), ('camera', 'drill'),
])
def test_rotation_only_overlap_with_other_upright_object_is_reviewable(target, other):
    guesses = [guess(target, True, [.2, .2, .6, .6], 90, .99),
               guess(other, False, [.1, .1, .9, .9], 0, .56)]
    context = annotate_context(guesses, {'status': 'not_detected'})
    assert context['status'] == 'needs_review'
    assert context['rotationEvidenceReviewRequired'] is True
    assert context['depictedContentReviewRequired'] is False
    assert guesses[0]['matchesCategory'] is False
    assert guesses[0]['matchesExpectedLabel'] is True
    assert guesses[0]['confidence'] == .99  # No fabricated lower score.
    assert guesses[0]['competingUprightLabels'] == [other]


def test_sideways_object_without_conflicting_context_and_nearby_objects_remain_usable():
    for others in ([], [guess('headphones', False, [.7, .1, .95, .9])],
                   [guess('person', False, [0, 0, 1, 1])],
                   [guess('headphones', False, [0, 0, float('nan'), 1])]):
        guesses = [guess('mouse', True, [.1, .2, .4, .6], 90), *others]
        assert annotate_context(guesses, {'status': 'not_detected'})['status'] == 'not_established'
        assert guesses[0]['matchesCategory'] is True


def test_existing_upright_match_and_same_type_alias_do_not_become_rotation_only():
    rotated = guess('mouse', True, [.2, .2, .6, .6], 90)
    supporting = guess('computer mouse', True, [.2, .2, .6, .6])
    other = guess('headphones', False, [.1, .1, .9, .9])
    assert not annotate_context([rotated, supporting, other], {'status': 'not_detected'})['rotationEvidenceReviewRequired']
    assert rotated['matchesCategory']
    # A single retained detection can carry its earlier original-orientation box.
    rotated['uprightEvidence'] = [{'boundingBox': [.2, .2, .6, .6], 'confidence': .6}]
    assert not annotate_context([rotated, other], {'status': 'not_detected'})['rotationEvidenceReviewRequired']


def test_rotation_and_document_checks_remain_separate_and_can_both_apply():
    guesses = [guess('mouse', True, [.2, .2, .6, .6], 90),
               guess('headphones', False, [.1, .1, .9, .9]),
               guess('illustration', False, [.1, .1, .9, .9])]
    context = annotate_context(guesses, {'status': 'not_detected'})
    assert context['rotationEvidenceReviewRequired'] and context['depictedContentReviewRequired']


def test_original_non_target_fixed_model_is_not_skipped_and_work_stays_bounded():
    original = np.arange(10 * 12 * 3, dtype=np.uint8).reshape(10, 12, 3)
    calls = []
    class Directional(Detector):
        def __init__(self, label, rotation):
            super().__init__([label])
            self.label, self.rotation = label, rotation
        def predict(self, image, **options):
            assert options['conf'] == items.THRESHOLD == .55
            assert options['max_det'] == 20
            calls.append((self.label, np.array_equal(image, original)))
            result = super().predict(image, **options)
            if not np.array_equal(image, np.rot90(original, self.rotation)):
                result[0].boxes = []
            else:
                h, w = image.shape[:2]
                result[0].boxes[0].xyxy = np.array([[.1*w, .1*h, .9*w, .9*h]])
            return result
    target, competitor = Directional('game controller', 1), Directional('mouse', 0)
    detections, attempts, failures = items.detect_photo(original, {'game controller'},
        [(target, 'yolo_world_pretrained', 'a'), (competitor, 'general_pretrained', 'b')])
    assert calls[0] == ('mouse', True)
    assert any(row['label'] == 'mouse' and row['rotationDegrees'] == 0 for row in detections)
    assert 0 < attempts <= 8 and failures == 0
    assert annotate_context(detections, {'status': 'not_detected'})['rotationEvidenceReviewRequired']


def test_higher_rotated_score_keeps_original_box_evidence():
    original = np.arange(10 * 12 * 3, dtype=np.uint8).reshape(10, 12, 3)
    class Context(Detector):
        def predict(self, image, **options):
            result = super().predict(image, **options)
            h, w = image.shape[:2]
            for box in result[0].boxes:
                box.xyxy = np.array([[.1*w, .1*h, .9*w, .9*h]])
                box.conf = np.array(.6 if np.array_equal(image, original) else .99)
            return result
    class Target(Detector):
        def predict(self, image, **options):
            result = super().predict(image, **options)
            if np.array_equal(image, original):
                result[0].boxes = []
            else:
                h, w = image.shape[:2]
                result[0].boxes[0].xyxy = np.array([[.1*w, .1*h, .9*w, .9*h]])
            return result
    detections, _, _ = items.detect_photo(original, {'game controller'},
        [(Target(['game controller']), 'yolo_world_pretrained', 'a'),
         (Context(['mouse']), 'general_pretrained', 'b')])
    competitor = next(d for d in detections if d['label'] == 'mouse')
    assert competitor['rotationDegrees'] != 0 and competitor['confidence'] == .99
    assert competitor['uprightEvidence'][0]['confidence'] == .6
    assert annotate_context(detections, {'status': 'not_detected'})['rotationEvidenceReviewRequired']


def test_ambiguous_rotated_views_cannot_become_category_consistent_or_blur_claim(monkeypatch):
    monkeypatch.setattr(items, 'detect_photo', lambda *_: ([
        guess('headphones', True, [.2, .2, .8, .8], 180, .99),
        guess('mouse', False, [.2, .2, .8, .8]),
    ], 3, 0))
    result = verify(monkeypatch, category='Devices', subcategory='Audio', detector=Detector(['headphones']))
    assert result.accepted is False and result.outcome == 'warning'
    assert result.confidence == 0
    assert result.extracted_fields['categoryMatched'] is None
    assert result.extracted_fields['matchingViewCount'] == 0
    assert result.extracted_fields['categoryMatchStatus'] == 'context_needs_review'
    assert all(p['photoContext']['rotationEvidenceReviewRequired'] for p in result.extracted_fields['images'])
    assert any('conflicting' in note for note in result.risk_indicators)
    assert not any('document' in note or 'blurry' in note for note in result.risk_indicators)

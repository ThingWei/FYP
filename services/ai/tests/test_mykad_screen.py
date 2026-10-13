"""Synthetic geometry and OCR fixtures only; not screen-detection accuracy claims."""
from types import SimpleNamespace
import numpy as np
import pytest
from app.services import mykad_screen as screen, mykad_readability as gate
from app.services import image_intelligence as intelligence
from app.schemas import VerificationRequest
from test_mykad_readability import IMAGE, FRONT, ocr, install_submission, accepted_check


@pytest.mark.parametrize('phone,card,confidence,expected', [
    ((0, 0, 100, 200), (10, 50, 90, 100), .85, True),
    ((0, 0, 100, 200), (10, 50, 90, 100), .84999, False),
    ((0, 0, 100, 200), (10, 50, 90, 100), float('nan'), False),
    ((0, 0, 100, 200), (110, 50, 190, 100), .99, False),
    ((0, 0, 100, 200), (90, 50, 190, 100), .99, False),
    # Exact containment boundary; below it fails.
    ((0, 0, 100, 200), (10, 50, 110, 100), .99, True),
    ((0, 0, 100, 200), (10.01, 50, 110.01, 100), .99, False),
    # Exact area ratio; don't compare rounded metrics for the decision.
    ((0, 0, 100, 300), (0, 0, 100, 200), .99, True),
    ((0, 0, 100, 299.99), (0, 0, 100, 200), .99, False),
    ((0, 0, 100, 180), (10, 10, 90, 60), .99, True),
    ((0, 0, 100, 179.99), (10, 10, 90, 60), .99, False),
    ((0, 0, 0, 200), (10, 50, 90, 100), .99, False),
    ((0, 0, 100, 200), (0, 0, 100, 200), .99, False),
])
def test_enclosing_phone_boundaries(phone, card, confidence, expected):
    assert screen.enclosing_phone(phone, card, confidence)[0] is expected


def detector_fixture(monkeypatch, tmp_path, *, names=None, phone=(0, 0, 100, 200), fail=False):
    artifact = tmp_path / 'installed.pt'
    artifact.touch()
    names = names or {0: 'cell phone'}
    box = SimpleNamespace(cls=np.array(0), conf=np.array(.99), xyxy=np.array([phone]))
    def predict(*args, **kwargs):
        assert kwargs['conf'] == .85 and kwargs['max_det'] == 50
        if fail:
            raise RuntimeError('private path and OCR must not be disclosed')
        return [SimpleNamespace(names=names, boxes=[box])]
    monkeypatch.setattr(screen, 'detector_selection', lambda: (artifact, 'configured'))
    monkeypatch.setattr(screen, 'load_detector', lambda *args: SimpleNamespace(names=names, predict=predict))


def test_phone_evidence_is_safe_and_nearby_phone_does_not_reject(monkeypatch, tmp_path):
    detector_fixture(monkeypatch, tmp_path)
    result = screen.phone_screen_evidence(IMAGE, (10, 50, 90, 100))
    assert result['status'] == 'detected' and result['evidence']['cardCoverage'] == 1
    assert 'box' not in str(result) and result['absenceProvesPhysicalCard'] is False
    result = screen.phone_screen_evidence(IMAGE, (110, 50, 190, 100))
    assert result['status'] == 'not_detected'


@pytest.mark.parametrize('problem', ['missing', 'incompatible', 'inference'])
def test_missing_or_incompatible_artifact_is_unavailable(monkeypatch, tmp_path, problem):
    detector_fixture(monkeypatch, tmp_path, names={0: 'book'} if problem == 'incompatible' else None,
                     fail=problem == 'inference')
    if problem == 'missing':
        monkeypatch.setattr(screen, 'detector_selection', lambda: (tmp_path / 'missing.pt', 'missing'))
    result = screen.phone_screen_evidence(IMAGE, (10, 50, 90, 100))
    assert result['status'] == 'unavailable' and 'private' not in str(result)


def test_fragmented_known_browser_phrases_not_arbitrary_similarity():
    assert gate.screen_evidence(['Search in', 'side image', 'Visit web', 'site'])['status'] == 'detected'
    assert gate.screen_evidence(['G o o g l e', 'I m a g e s', 'Related', 'images'])['status'] == 'detected'
    assert gate.screen_evidence(['FOR RENTHUB ONLY', '12 JALAN TEST'])['status'] == 'not_detected'
    assert gate.screen_evidence(['Searching images', 'Visiting sites'])['status'] == 'not_detected'
    assert gate.confident_lines(ocr('Google Images\nRelated images', .59)) == []


@pytest.mark.parametrize('status', ['detected', 'unavailable'])
def test_final_capture_blocks_before_reading_fields(monkeypatch, status):
    monkeypatch.setattr(gate, 'phone_screen_evidence', lambda *args:
                        {'status': status, 'method': 'enclosing-phone-v1'})
    reader = SimpleNamespace(readtext=lambda *args, **kwargs: ocr(FRONT))
    result, private = gate.check_side(IMAGE, 'front', reader, lambda x: x, None, None,
                                     (0, 0, 1000, 640), 'front')
    assert not result['accepted'] and private == {}
    assert result['status'] == ('screen_copy' if status == 'detected' else 'unavailable')
    if status == 'detected':
        assert result['guidance'] == gate.SCREEN_MESSAGE


def test_final_submission_repeats_screen_checks(monkeypatch):
    install_submission(monkeypatch)
    def blocked(image, side, *args):
        result, private = accepted_check(side)
        result.update(status='screen_copy', accepted=False, guidance=gate.SCREEN_MESSAGE)
        result['screenCopy'].update(status='detected', phoneScreen={'method': 'enclosing-phone-v1', 'status': 'detected'})
        return result, {}  # Identity must not be derived from the rejected capture.
    monkeypatch.setattr(intelligence, 'check_side', blocked)
    result = intelligence.ImageIntelligenceService().verify_document(VerificationRequest(expected_type='mykad'))
    assert result.outcome == 'rescan_required'
    assert not result.extracted_fields.get('identityNumber')

"""Private synthetic OCR/region fixtures; no real identity images or accuracy claim."""
from types import SimpleNamespace
import numpy as np
import pytest
from app.schemas import VerificationRequest, DocumentFrameRequest, EncodedImage
from app.services import mykad_readability as gate
from app.services import image_intelligence as intelligence

FRONT = 'MALAYSIA\nMYKAD\n900101-07-1234\nTEST USER'
BACK = 'MALAYSIA\nKETUA PENGARAH PENDAFTARAN NEGARA'
IMAGE = np.random.default_rng(17).integers(60, 210, (640, 1000, 3), dtype=np.uint8)

def ocr(text, confidence=.95):
    return [(None, line, confidence) for line in text.splitlines()]

def side_fixture(monkeypatch, side='front', number='900101-07-1234', name='测试用户 A/L TEST',
                 address='12 JALAN TEST\n43000 KAJANG SELANGOR', scene=None, low_field=None,
                 missing=None, type_text=None):
    queue = [ocr(scene or (FRONT if side == 'front' else BACK)),
             ocr(type_text or (FRONT if side == 'front' else BACK))]
    required = gate.REQUIRED[side]
    fields = {'front_identity_number': number, 'front_name': name, 'front_address': address,
              'back_identity_number': number}
    for field in required:
        if field != missing:
            queue.append(ocr(fields[field], .2 if field == low_field else .95))
    def regions(card, selected):
        return {field: [] if field == missing else [(.99, (10, 10, 350, 60))]
                for field in gate.REQUIRED[selected]}
    monkeypatch.setattr(gate, '_required_regions', regions)
    monkeypatch.setattr(gate, 'locate_card', lambda *args: ((0, 0, 1000, 640), side))
    monkeypatch.setattr(intelligence, '_nlp', lambda: None)
    reads = []
    def read(image, **kwargs):
        reads.append(image.shape)
        return queue.pop(0)
    reader = SimpleNamespace(readtext=read)
    result = gate.check_side(IMAGE, side, reader, lambda image: image,
                             intelligence._extract_document_fields, lambda: (None, None))
    return result, reads

@pytest.mark.parametrize('field', gate.REQUIRED['front'])
def test_missing_or_low_confidence_required_front_field_blocks(monkeypatch, field):
    result, _ = side_fixture(monkeypatch, missing=field)
    assert not result[0]['accepted']
    assert result[0]['status'] == 'unreadable_fields'
    result, _ = side_fixture(monkeypatch, low_field=field)
    assert not result[0]['accepted']

def test_readable_unicode_fields_are_spatial_and_privacy_watermark_is_not_a_rejection(monkeypatch):
    result, reads = side_fixture(monkeypatch, scene=FRONT + '\nFOR RENTHUB ONLY')
    assert result[0]['accepted']
    assert result[1]['fullName'].startswith('测试')
    assert len(reads) == 5  # full scene, card and three separate fields
    assert result[0]['authenticityVerified'] is False
    assert '900101' not in str(result[0]) and 'JALAN TEST' not in str(result[0])

@pytest.mark.parametrize('address', ['', 'SELANGOR', 'Search inside image'])
def test_address_overlay_or_state_only_is_not_readable_address(monkeypatch, address):
    result, _ = side_fixture(monkeypatch, address=address)
    assert not result[0]['accepted']

def test_address_only_watermark_and_unreadable_name_do_not_supply_required_content(monkeypatch):
    result, _ = side_fixture(monkeypatch, address='FOR RENTHUB ONLY')
    assert not result[0]['accepted']
    result, _ = side_fixture(monkeypatch, name='1234')
    assert not result[0]['accepted']

def test_privacy_notice_on_same_line_does_not_erase_readable_details(monkeypatch):
    result, _ = side_fixture(monkeypatch, name='TEST USER FOR RENTHUB ONLY',
                            address='12 JALAN TEST FOR RENTHUB ONLY\n43000 KAJANG SELANGOR')
    assert result[0]['accepted']
    assert result[1]['fullName'] == 'TEST USER'

@pytest.mark.parametrize('scene', [
    FRONT + '\nSearch inside image\nShare\nSave',
    FRONT + '\nGoogle Images\nRelated images',
    FRONT + '\nhttps://example.invalid\nVisit website',
])
def test_screen_context_is_checked_outside_card_before_field_ocr(monkeypatch, scene):
    result, reads = side_fixture(monkeypatch, scene=scene)
    assert result[0]['status'] == 'screen_copy'
    assert not result[0]['accepted']
    assert len(reads) == 1

@pytest.mark.parametrize('cue', ['Share', 'Save', 'Google Lens', 'FOR RENTHUB ONLY'])
def test_a_single_ui_or_watermark_cue_is_not_screen_proof(cue):
    assert gate.screen_evidence([cue])['status'] == 'not_detected'

def test_fractional_yolo_boxes_are_converted_to_valid_numpy_pixel_slices():
    region = gate.pixel_region([10.2, 11.8, 80.1, 60.9], (100, 100))
    assert region == (10, 11, 81, 61)
    assert IMAGE[region[1]:region[3], region[0]:region[2]].size > 0

def test_mandatory_preprocessing_preserves_scene_and_field_dimensions():
    assert intelligence._ocr_region_preprocess(IMAGE).shape == IMAGE.shape[:2]

@pytest.mark.parametrize('number', ['900101-07-1234\n910101-07-1234', '900101-O7-1234', '9001010712345'])
def test_ambiguous_or_invalid_field_number_does_not_pass(monkeypatch, number):
    result, _ = side_fixture(monkeypatch, number=number)
    assert not result[0]['accepted']

def test_missing_field_detector_or_ocr_never_falls_back_to_card_confidence(monkeypatch):
    def fail(*args):
        raise RuntimeError('private path and identity should never be returned')
    monkeypatch.setattr(gate, '_required_regions', fail)
    queue = iter([ocr(FRONT), ocr(FRONT)])
    result = gate.check_side(IMAGE, 'front', SimpleNamespace(readtext=lambda *a, **k: next(queue)),
                             lambda x: x, intelligence._extract_document_fields, lambda: (None, None),
                             (0, 0, 1000, 640), 'front')
    assert result[0]['status'] == 'unavailable'
    assert 'private path' not in str(result)
    result = gate.check_side(IMAGE, 'front', None, None, None, None)
    assert not result[0]['accepted']

def test_back_requires_a_readable_identity_number(monkeypatch):
    result, _ = side_fixture(monkeypatch, side='back', number='')
    assert not result[0]['accepted']
    result, _ = side_fixture(monkeypatch, side='back', low_field='back_identity_number')
    assert not result[0]['accepted']

def test_pair_preserves_zeroes_and_rejects_invalid_birth_segment_conflicts(monkeypatch):
    front, _ = side_fixture(monkeypatch, number='000101 07 1234')
    back, _ = side_fixture(monkeypatch, side='back', number='000101-07-1234')
    pair, fields = gate.check_pair(front, back)
    assert pair['status'] == 'matched' and fields['identityNumber'] == '000101071234'
    conflict, _ = side_fixture(monkeypatch, side='back', number='991332-07-1234')
    pair, fields = gate.check_pair(front, conflict)
    assert pair['status'] == 'mismatched' and not pair['accepted'] and fields == {}
    assert '991332' not in str(pair)

def accepted_check(side, number='900101071234'):
    fields = {name: {'detected': True, 'readable': True} for name in gate.REQUIRED[side]}
    return ({'method': gate.CONTRACT, 'status': 'validated', 'accepted': True,
             'expectedSide': side, 'detectedSide': side, 'requiredFields': fields,
             'screenCopy': {'status': 'not_detected', 'cues': []}, 'authenticityVerified': False,
             'guidance': 'Required details are readable. Administrator review is still required.'},
            {'identityNumber': number, 'identityNumberFormatValid': True, 'fullName': 'TEST USER'})

def install_submission(monkeypatch, mismatch=False):
    images = [IMAGE.copy(), IMAGE.copy()]
    monkeypatch.setattr(intelligence, '_decode_images', lambda request: ([(None, im) for im in images], []))
    monkeypatch.setattr(intelligence, '_quality', lambda image: {
        'isBlurry': False, 'isTooDark': False, 'isTooBright': False,
        'hasSevereGlare': False, 'hasUsableResolution': True})
    monkeypatch.setattr(intelligence, '_ocr_preprocess', lambda image: image)
    monkeypatch.setattr(intelligence, '_nlp', lambda: None)
    remaining = iter([FRONT, BACK])
    monkeypatch.setattr(intelligence, '_ocr_reader', lambda: SimpleNamespace(
        readtext=lambda *a, **k: ocr(next(remaining))))
    monkeypatch.setattr(intelligence, '_text_region_signals', lambda *args: ('normal', []))
    monkeypatch.setattr(intelligence, 'check_side', lambda image, side, *args:
        accepted_check(side, '910101071234' if mismatch and side == 'back' else '900101071234'))
    monkeypatch.setattr(intelligence, 'analyse_fields', lambda *args: {
        'status': 'unavailable', 'warnings': [], 'riskScore': .1, 'signal': 'no_elevated_signal', 'scoredFieldCount': 0})

def test_final_mismatch_requires_rescan_not_manual_review(monkeypatch):
    install_submission(monkeypatch, mismatch=True)
    result = intelligence.ImageIntelligenceService().verify_document(VerificationRequest(expected_type='mykad'))
    assert result.outcome == 'rescan_required'
    assert result.extracted_fields['mykadSidesConsistent'] is False
    assert '900101' not in str(result.model_dump())
    assert result.extracted_fields['mandatoryMykadValidation']['status'] == 'mismatched'

def test_valid_pair_reaches_admin_not_automatic_approval(monkeypatch):
    install_submission(monkeypatch)
    result = intelligence.ImageIntelligenceService().verify_document(VerificationRequest(expected_type='mykad'))
    assert result.outcome == 'manual_review' and result.accepted is False
    assert result.extracted_fields['mykadSidesConsistent'] is True

@pytest.mark.parametrize('back_number,expected', [('900101071234', True), ('991332071234', False)])
def test_final_frame_back_uses_reference_front_and_never_exposes_number(monkeypatch, back_number, expected):
    from test_document_capture_quality import install_detector, sharp_image
    install_detector(monkeypatch, sharp_image(), side='back')
    monkeypatch.setattr(intelligence, '_ocr_reader', lambda: object())
    monkeypatch.setattr(intelligence, 'check_side', lambda image, side, *args:
        accepted_check(side, back_number if side == 'back' else '900101071234'))
    request = DocumentFrameRequest(content_base64='synthetic', expected_type='mykad',
        expected_side='back', validate_capture=True,
        reference_front=EncodedImage(content_base64='synthetic', content_type='image/jpeg'))
    result = intelligence.ImageIntelligenceService().inspect_document_frame(request)
    assert result.ready is expected
    assert result.capture_validation['pairMatch']['status'] == ('matched' if expected else 'mismatched')
    assert '900101' not in str(result.model_dump())

def test_final_frame_back_without_front_reference_is_blocked(monkeypatch):
    from test_document_capture_quality import install_detector, sharp_image
    install_detector(monkeypatch, sharp_image(), side='back')
    monkeypatch.setattr(intelligence, '_ocr_reader', lambda: object())
    monkeypatch.setattr(intelligence, 'check_side', lambda *args: accepted_check('back'))
    result = intelligence.ImageIntelligenceService().inspect_document_frame(DocumentFrameRequest(
        content_base64='synthetic', expected_type='mykad', expected_side='back', validate_capture=True))
    assert result.ready is False and result.capture_validation['status'] == 'front_required'


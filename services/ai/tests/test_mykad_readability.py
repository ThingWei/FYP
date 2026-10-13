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
                 missing=None, type_text=None, retry_text=None, retry_confidence=.95):
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
    monkeypatch.setattr(gate, 'phone_screen_evidence', lambda *args: {'status': 'not_detected', 'method': 'enclosing-phone-v1'})
    monkeypatch.setattr(gate, '_required_regions', regions)
    monkeypatch.setattr(gate, 'locate_card', lambda *args: ((0, 0, 1000, 640), side))
    monkeypatch.setattr(intelligence, '_nlp', lambda: None)
    reads = []
    last = None
    def read(image, **kwargs):
        nonlocal last
        reads.append(image.shape)
        if 'mag_ratio' in kwargs:
            return ocr(retry_text, retry_confidence) if retry_text is not None else last
        last = queue.pop(0)
        return last
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


@pytest.mark.parametrize('field,retry_text', [
    ('front_identity_number', '900101-07-1234'),
    ('front_name', 'TEST USER'),
    ('front_address', '12 JALAN TEST\n43000 KAJANG SELANGOR'),
])
def test_gentle_field_retry_recovers_confident_details_without_lowering_threshold(monkeypatch, field, retry_text):
    result, reads = side_fixture(monkeypatch, low_field=field, retry_text=retry_text)
    assert result[0]['accepted'] is True
    assert result[0]['requiredFields'][field]['ocrRetryUsed'] is True
    assert len(reads) == 6  # Only one retry, not every successful field.
    assert 'JALAN TEST' not in str(result[0]) and '900101' not in str(result[0])


@pytest.mark.parametrize('field,retry_text', [
    ('front_identity_number', '900101-07-1234'),
    ('front_name', 'TEST USER'),
    ('front_address', '12 JALAN TEST\n43000 KAJANG SELANGOR'),
])
def test_retry_below_existing_confidence_threshold_still_requires_rescan(monkeypatch, field, retry_text):
    result, _ = side_fixture(monkeypatch, low_field=field,
                             retry_text=retry_text, retry_confidence=.59)
    assert not result[0]['accepted'] and result[0]['failedFields'] == [field]


def test_unreadable_address_has_targeted_guidance_and_does_not_merge_weak_text_passes(monkeypatch):
    result, _ = side_fixture(monkeypatch, address='SELANGOR', retry_text='KUALA LUMPUR')
    assert result[0]['accepted'] is False
    assert result[0]['failedFields'] == ['front_address']
    assert 'your address' in result[0]['guidance']


def test_retry_does_not_erase_obstruction_or_ambiguous_numbers(monkeypatch):
    result, reads = side_fixture(monkeypatch, address='Search inside image',
                                  retry_text='12 JALAN TEST\n43000 KAJANG SELANGOR')
    assert not result[0]['accepted'] and len(reads) == 5
    result, reads = side_fixture(monkeypatch, number='900101-07-1234\n910101-07-1234',
                                  retry_text='900101-07-1234')
    assert not result[0]['accepted'] and len(reads) == 5


def test_missing_field_detection_cannot_be_rescued_by_retry_text(monkeypatch):
    result, _ = side_fixture(monkeypatch, missing='front_address',
                             retry_text='12 JALAN TEST\n43000 KAJANG SELANGOR')
    assert not result[0]['accepted']
    assert not result[0]['requiredFields']['front_address']['detected']


def test_retry_image_preserves_field_aspect_and_adds_no_neighbouring_pixels():
    crop = np.full((24, 120, 3), 100, dtype=np.uint8)
    retry = gate.field_retry_image(crop)
    assert retry.shape == (24 * 3 + 16, 120 * 3 + 16)
    assert np.all(retry[8:-8, 8:-8] == 100) and np.all(retry[:8] == 255)


@pytest.mark.parametrize('retry_confidence,found', [(.8, True), (.49, False)])
def test_missing_small_field_retries_detector_without_lowering_detection_floor(monkeypatch, retry_confidence, found):
    calls = []
    labels = {0: 'front_identity_number', 1: 'front_name', 2: 'front_address'}
    def box(index, confidence):
        return SimpleNamespace(cls=np.array(index), conf=np.array(confidence),
            xyxy=np.array([[10., 10., 350., 60.]]))
    def predict(image, **kwargs):
        calls.append(kwargs['imgsz'])
        assert kwargs['conf'] == .5
        boxes = [box(0, .9), box(1, .9)] if kwargs['imgsz'] == 640 else [box(2, retry_confidence)]
        return [SimpleNamespace(boxes=boxes, names=labels)]
    monkeypatch.setattr(gate, '_field_detector', lambda *args: SimpleNamespace(predict=predict))
    monkeypatch.setattr(gate, '_threshold', lambda: .5)
    regions = gate._required_regions(IMAGE, 'front')
    assert calls == [640, 960]
    assert bool(regions['front_address']) is found
    assert len(regions['front_identity_number']) == 1

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
             'screenCopy': {'status': 'not_detected', 'cues': [], 'phoneScreen': {'status': 'not_detected', 'method': 'enclosing-phone-v1'}}, 'authenticityVerified': False,
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


@pytest.mark.parametrize('status', ['unreadable_fields', 'unavailable', 'screen_copy'])
def test_back_scan_identifies_saved_front_failure_without_requiring_back_address(monkeypatch, status):
    from test_document_capture_quality import install_detector, sharp_image
    install_detector(monkeypatch, sharp_image(), side='back')
    monkeypatch.setattr(intelligence, '_ocr_reader', lambda: object())
    def checks(image, side, *args):
        result, private = accepted_check(side)
        if side == 'front':
            result.update(accepted=False, status=status, guidance=gate.READABILITY_MESSAGE)
            result['requiredFields']['front_address']['readable'] = False
            private = {}
        return result, private
    monkeypatch.setattr(intelligence, 'check_side', checks)
    result = intelligence.ImageIntelligenceService().inspect_document_frame(DocumentFrameRequest(
        content_base64='synthetic', expected_type='mykad', expected_side='back', validate_capture=True,
        reference_front=EncodedImage(content_base64='synthetic', content_type='image/jpeg')))
    assert not result.ready
    assert result.capture_validation['failedSide'] == 'front'
    assert 'saved front photo' in result.guidance.lower()
    assert result.capture_validation['requiredFields']['back_identity_number']['readable'] is True
    assert 'front_address' not in result.capture_validation['requiredFields']
    assert '900101' not in str(result.model_dump())


def test_unreadable_back_pair_guidance_names_only_back_number():
    back, _ = accepted_check('back')
    back.update(accepted=False, status='unreadable_fields',
                guidance='Please rescan the back with its IC number fully visible and readable.')
    pair, private = gate.check_pair(accepted_check('front'), (back, {}))
    assert pair['failedSide'] == 'back' and private == {}
    assert 'name' not in pair['guidance'] and 'address' not in pair['guidance']


def test_initial_capture_and_stored_front_recheck_use_identical_card_crop(monkeypatch):
    from test_document_capture_quality import install_detector, sharp_image
    image = sharp_image()
    install_detector(monkeypatch, image, side='front')
    monkeypatch.setattr(intelligence, '_ocr_reader', lambda: object())
    captured_bounds = []
    def checked(*args):
        captured_bounds.append(args[6])
        return accepted_check('front')
    monkeypatch.setattr(intelligence, 'check_side', checked)
    result = intelligence.ImageIntelligenceService().inspect_document_frame(DocumentFrameRequest(
        content_base64='synthetic', expected_type='mykad', expected_side='front', validate_capture=True))
    stored_bounds, side = gate.locate_card(image, 'front', intelligence._document_yolo_model)
    assert result.ready and side == 'front'
    assert captured_bounds == [stored_bounds]


@pytest.mark.parametrize('front_number,expected', [('900101071234', True), ('910101071234', False)])
def test_replacement_front_capture_compares_saved_back_before_use_image(monkeypatch, front_number, expected):
    from test_document_capture_quality import install_detector, sharp_image
    install_detector(monkeypatch, sharp_image(), side='front')
    monkeypatch.setattr(intelligence, '_ocr_reader', lambda: object())
    calls = []
    def checks(image, side, *args):
        calls.append(side)
        return accepted_check(side, front_number if side == 'front' else '900101071234')
    monkeypatch.setattr(intelligence, 'check_side', checks)
    request = DocumentFrameRequest(content_base64='synthetic', expected_type='mykad',
        expected_side='front', validate_capture=True,
        reference_back=EncodedImage(content_base64='synthetic', content_type='image/jpeg'))
    result = intelligence.ImageIntelligenceService().inspect_document_frame(request)
    assert calls == ['front', 'back']
    assert result.ready is expected
    assert result.capture_validation['pairMatch']['status'] == ('matched' if expected else 'mismatched')
    assert '900101' not in str(result.model_dump()) and '910101' not in str(result.model_dump())


@pytest.mark.parametrize('status', ['unreadable_fields', 'unavailable', 'wrong_side', 'screen_copy'])
def test_replacement_front_cannot_bypass_failed_saved_back(monkeypatch, status):
    from test_document_capture_quality import install_detector, sharp_image
    install_detector(monkeypatch, sharp_image(), side='front')
    monkeypatch.setattr(intelligence, '_ocr_reader', lambda: object())
    def checks(image, side, *args):
        result, private = accepted_check(side)
        if side == 'back':
            result.update(accepted=False, status=status,
                guidance='Please rescan the back with its IC number fully visible and readable.')
            private = {}
        return result, private
    monkeypatch.setattr(intelligence, 'check_side', checks)
    result = intelligence.ImageIntelligenceService().inspect_document_frame(DocumentFrameRequest(
        content_base64='synthetic', expected_type='mykad', expected_side='front', validate_capture=True,
        reference_back=EncodedImage(content_base64='synthetic', content_type='image/jpeg')))
    assert not result.ready and result.capture_validation['failedSide'] == 'back'
    assert 'saved back photo' in result.guidance


@pytest.mark.parametrize('front_number,back_number', [(None, None), ('', ''), ('900101071234', None),
    (None, '900101071234'), ('900101071234', '90010107123'), ('O00101071234', 'O00101071234')])
def test_missing_or_invalid_private_numbers_never_compare_as_matched(front_number, back_number):
    pair, fields = gate.check_pair(accepted_check('front', front_number), accepted_check('back', back_number))
    assert not pair['accepted'] and pair['status'] == 'unconfirmed' and fields == {}
    assert '900101' not in str(pair)


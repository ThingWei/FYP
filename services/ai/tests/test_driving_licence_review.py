"""Synthetic text only; no identity photographs or authenticity accuracy claim."""
from datetime import date
from types import SimpleNamespace
import numpy as np
import pytest
from app.services.driving_licence import analyse_licence, validity, CONTRACT
from app.services import image_intelligence as intelligence
from app.schemas import VerificationRequest, EncodedImage

TEXT = 'LESEN MEMANDU MALAYSIA\nNAMA: 测试 A/L TEST\n900101-07-1234\nKELAS: D, B2\n01/01/2025 - 31/12/2035'

def check(monkeypatch, text=TEXT, confidence=.95, source='physical', reader=True):
    monkeypatch.setattr(intelligence, '_nlp', lambda: None)
    ocr = SimpleNamespace(readtext=lambda *args, **kw: [(None, line, confidence) for line in text.splitlines()]) if reader else None
    return analyse_licence([(None, np.zeros((600, 1000, 3), dtype=np.uint8))], ocr,
        lambda image: image, intelligence._extract_document_fields, source, date(2026, 10, 14))

@pytest.mark.parametrize('source', ['physical', 'myjpj'])
def test_valid_licence_is_only_ready_for_admin_review(monkeypatch, source):
    fields, outcome, _ = check(monkeypatch, source=source)
    validation = fields['licenceValidation']
    assert outcome == 'manual_review'
    assert validation['method'] == CONTRACT
    assert validation['acceptedForReview']
    assert validation['status'] == 'ready_for_review'
    assert not validation['authenticityVerified'] and not validation['officialVerification']
    assert fields['fullName'] == '测试 A/L TEST'
    assert fields['licenceClasses'] == ['B2', 'D']
    assert fields['validUntil'] == '2035-12-31'

def test_myjpj_screenshot_not_subject_to_mykad_screen_prohibition(monkeypatch):
    fields, outcome, _ = check(monkeypatch, TEXT + '\nGoogle\nSearch inside image\nMyJPJ', source='myjpj')
    assert fields['licenceValidation']['acceptedForReview'] and outcome == 'manual_review'

@pytest.mark.parametrize('text', ['MYKAD MALAYSIA\n900101-07-1234', 'CREDIT CARD\nVISA\nVALID THRU 12/30', 'STUDENT CARD'])
def test_other_cards_cannot_pass(monkeypatch, text):
    fields, _, _ = check(monkeypatch, text)
    assert not fields['licenceValidation']['acceptedForReview']

def test_unavailable_and_low_confidence_ocr_block(monkeypatch):
    assert check(monkeypatch, reader=False)[1] == 'unavailable'
    assert not check(monkeypatch, confidence=.59)[0]['licenceValidation']['acceptedForReview']

@pytest.mark.parametrize('number,state', [('000101 07 0123', 'readable'),
    ('9001O1-07-1234', 'unavailable'), ('900101-07-1234\n910101-07-1234', 'ambiguous')])
def test_identity_numbers_never_guessed(monkeypatch, number, state):
    fields, _, _ = check(monkeypatch, TEXT.replace('900101-07-1234', number))
    assert fields['licenceValidation']['fieldStates']['ic_number'] == state
    if state != 'readable': assert 'identityNumber' not in fields
    else: assert fields['identityNumber'] == '000101070123'

@pytest.mark.parametrize('replacement', ['NAMA: 测试 A/L TEST', 'KELAS: D, B2', '01/01/2025 - 31/12/2035'])
def test_missing_optional_ocr_details_require_manual_review(monkeypatch, replacement):
    fields, _, _ = check(monkeypatch, TEXT.replace(replacement, ''))
    assert fields['licenceValidation']['acceptedForReview']
    assert fields['licenceValidation']['status'] == 'needs_review'

@pytest.mark.parametrize('period,status', [('01/01/2025 - 13/10/2026', 'expired'),
    ('15/10/2026 - 31/12/2035', 'not_yet_valid'), ('01/01/2025 - 14/10/2026', 'ready_for_review')])
def test_malaysia_calendar_validity(monkeypatch, period, status):
    fields, _, _ = check(monkeypatch, TEXT.replace('01/01/2025 - 31/12/2035', period))
    assert fields['licenceValidation']['status'] == status
    assert fields['licenceValidation']['acceptedForReview'] == (status == 'ready_for_review')

@pytest.mark.parametrize('text', ['DOB 01/01/1990\nISSUED 01/01/2025',
    'VALID UNTIL 31/02/2035', '01/01/2035 - 01/01/2025',
    'VALID UNTIL 01/01/2035\nVALID UNTIL 01/01/2036'])
def test_ambiguous_or_unlabelled_dates_not_guessed(text):
    assert validity(text)[1] is None

def test_labelled_iso_expiry():
    assert validity('VALID UNTIL: 2035-12-31')[1] == date(2035,12,31)

def test_verify_endpoint_uses_licence_checks_not_mykad_models(monkeypatch):
    image = np.zeros((600, 1000, 3), dtype=np.uint8)
    monkeypatch.setattr(intelligence, '_decode_images', lambda *args: ([(None, image)], []))
    monkeypatch.setattr(intelligence, '_quality', lambda *args: {'issues': []})
    monkeypatch.setattr(intelligence, '_quality_issues', lambda *args: [])
    monkeypatch.setattr(intelligence, '_ocr_reader', lambda: None)
    response = intelligence.ImageIntelligenceService().verify_document(VerificationRequest(
        expected_type='driving_licence', licence_source='myjpj',
        images=[EncodedImage(content_base64='eA==', content_type='image/jpeg')]))
    assert response.adapter == CONTRACT and response.outcome == 'unavailable'

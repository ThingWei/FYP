"""Synthetic OCR fixtures only; no real identity documents or OCR accuracy claims."""

from pathlib import Path

import numpy as np
import pytest
from fastapi.testclient import TestClient

from app.main import app
from app.services import image_intelligence as intelligence


MYKAD = 'MALAYSIA\nKAD PENGENALAN\n900101-07-1234\nNAMA TEST USER'
LICENCE = (
    'MALAYSIA\nDRIVING LICENCE\nLESEN MEMANDU\n900101-07-1234\n'
    'NAME TEST USER\nCLASS D\nVALID UNTIL 01/01/2030'
)
PASSPORT = (
    'PASSPORT\nA12345678\nNAME TEST USER\n'
    'P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<\n'
    'L898902C36UTO7408122F1204159ZE184226B<<<<<10'
)
MISMATCH = 'Selected document type does not match extracted document fields'


@pytest.fixture(autouse=True)
def isolate_optional_nlp(monkeypatch):
    monkeypatch.setattr(intelligence, '_nlp', lambda: None)


def test_mykad_heading_and_number_are_separate_evidence():
    fields = intelligence._extract_document_fields(MYKAD, 'mykad')
    assert fields['documentType'] == 'mykad'
    assert fields['identityNumber'] == '900101-07-1234'
    assert fields['identityNumberFormatValid'] is True
    assert fields['dateOfBirth'] == '1990-01-01'
    assert fields['fullName'] == 'TEST USER'
    assert fields['documentTypeSignals']['mykad']['evidence'] == ['identity_card_heading']
    invalid = intelligence._extract_document_fields('MYKAD 991332-10-1234', 'mykad')
    assert invalid['identityNumberFormatValid'] is False
    assert 'dateOfBirth' not in invalid


def test_licence_can_contain_holder_ic_and_extract_labelled_fields():
    fields = intelligence._extract_document_fields(LICENCE, 'driving_licence')
    assert fields['documentType'] == 'driving_licence'
    assert fields['identityNumber'] == '900101-07-1234'
    assert fields['identityNumberFormatValid'] is True
    assert fields['fullName'] == 'TEST USER'
    assert fields['licenceClass'] == 'D'
    assert fields['expiryDateText'] == '01/01/2030'


@pytest.mark.parametrize('heading', [
    'DRIVING LICENSE', 'DR1V1NG L1CENCE', 'LES3N MEM4NDU',
])
def test_noisy_licence_headings_do_not_force_mykad(heading):
    fields = intelligence._extract_document_fields(
        f'{heading}\n900101-07-1234\nKELAS B2', 'driving_licence',
    )
    assert fields['documentType'] == 'driving_licence'
    assert fields['licenceClass'] == 'B2'
    assert 'fullName' not in fields
    assert 'expiryDateText' not in fields


def test_context_requires_structural_licence_evidence():
    text = '900101-07-1234 KELAS D TARIKH LUPUT 01/01/2030'
    fields = intelligence._extract_document_fields(text, 'driving_licence')
    assert fields['documentType'] == 'driving_licence'
    without_context = intelligence._extract_document_fields(text)
    assert 'documentType' not in without_context


@pytest.mark.parametrize('text', [
    '900101-07-1234', 'MALAYSIA 900101-07-1234',
    '900101-07-1234 CLASS D', '900101-07-1234 VALID UNTIL 01/01/2030',
])
def test_ic_number_and_expected_type_cannot_determine_document_type(text):
    for expected in ('mykad', 'driving_licence', None):
        fields = intelligence._extract_document_fields(text, expected)
        assert fields['identityNumber'] == '900101-07-1234'
        assert 'documentType' not in fields
        assert fields['documentTypeResolution'] == 'insufficient_evidence'


def test_wrong_document_and_conflicting_headings_are_not_trusted():
    fields = intelligence._extract_document_fields(MYKAD, 'driving_licence')
    assert fields['documentType'] == 'mykad'
    ambiguous = intelligence._extract_document_fields(MYKAD + '\n' + LICENCE, 'driving_licence')
    assert 'documentType' not in ambiguous
    assert ambiguous['documentTypeResolution'] == 'ambiguous'


def test_passport_number_classification_and_mrz_regression():
    fields = intelligence._extract_document_fields(PASSPORT, 'passport')
    assert fields['documentType'] == 'passport'
    assert fields['identityNumber'] == 'A12345678'
    assert fields['mrz'] == {
        'present': True, 'formatValid': True, 'checkDigitsValid': True,
    }
    assert intelligence._extract_document_fields(PASSPORT, 'driving_licence')['documentType'] == 'passport'


def test_long_printed_passport_fields_are_not_mistaken_for_mrz():
    text = 'PASSPORT NAME SYNTHETIC EXAMPLE NATIONALITY MALAYSIA A12345678'
    fields = intelligence._extract_document_fields(text, 'passport')
    assert fields['documentType'] == 'passport'
    assert fields['mrz']['present'] is False
    assert intelligence._extract_document_fields(text + '\n' + PASSPORT, 'passport')['mrz']['checkDigitsValid'] is True


@pytest.fixture
def analyse_ocr(monkeypatch):
    image = np.zeros((480, 720, 3), dtype=np.uint8)
    monkeypatch.setattr(intelligence, '_decode_images', lambda request: ([(None, image)], []))
    monkeypatch.setattr(intelligence, '_quality', lambda image: {
        'isBlurry': False, 'isTooDark': False, 'isTooBright': False,
        'hasSevereGlare': False, 'hasUsableResolution': True,
    })
    monkeypatch.setattr(intelligence, '_ocr_preprocess', lambda image: image)
    monkeypatch.setattr(intelligence, '_text_region_signals', lambda image, results: ('normal', []))
    monkeypatch.setattr(intelligence, '_document_risk_model', lambda: (None, Path('missing-risk.pt')))

    def analyse(text, expected):
        class SyntheticReader:
            def readtext(self, image, **kwargs):
                return [(None, line, 0.95) for line in text.splitlines()]
        monkeypatch.setattr(intelligence, '_ocr_reader', lambda: SyntheticReader())
        response = TestClient(app).post('/verify/document', json={
            'expected_type': expected, 'profile_name': 'TEST USER',
        })
        assert response.status_code == 200
        return response.json()

    return analyse


def test_licence_endpoint_has_no_false_mismatch_and_missing_risk_stays_manual(analyse_ocr):
    result = analyse_ocr(LICENCE, 'driving_licence')
    assert result['extracted_fields']['documentType'] == 'driving_licence'
    assert MISMATCH not in result['reasons']
    assert result['extracted_fields']['documentRiskModel'] == 'unavailable'
    assert 'documentRiskScore' not in result['extracted_fields']
    assert result['model_versions']['risk'] == 'unavailable'
    assert result['outcome'] == 'manual_review'
    assert result['accepted'] is False
    assert result['confidence'] == 0.95  # Stubbed OCR confidence, not risk confidence.


def test_actual_mykad_submitted_as_licence_retains_mismatch(analyse_ocr):
    result = analyse_ocr(MYKAD, 'driving_licence')
    assert result['extracted_fields']['documentType'] == 'mykad'
    assert MISMATCH in result['reasons']
    assert result['outcome'] == 'manual_review'


def test_inconclusive_ocr_routes_to_manual_without_false_mykad(analyse_ocr):
    result = analyse_ocr('900101-07-1234\nNAME TEST USER', 'driving_licence')
    assert 'documentType' not in result['extracted_fields']
    assert result['labels'] == ['unclassified_document']
    assert any('insufficient or ambiguous' in reason for reason in result['reasons'])
    assert result['outcome'] == 'manual_review'


def test_passport_endpoint_preserves_mrz_line_breaks(analyse_ocr):
    result = analyse_ocr(PASSPORT, 'passport')
    assert result['extracted_fields']['mrz']['checkDigitsValid'] is True
    assert MISMATCH not in result['reasons']


def test_invalid_ic_birth_segment_and_expired_licence_stay_manual(analyse_ocr):
    result = analyse_ocr(LICENCE.replace('900101', '991332').replace('2030', '2000'), 'driving_licence')
    assert result['extracted_fields']['identityNumberFormatValid'] is False
    assert result['extracted_fields']['documentExpired'] is True
    assert any('birth-date segment' in reason for reason in result['reasons'])
    assert any('expiry date is in the past' in reason for reason in result['reasons'])
    assert result['outcome'] == 'manual_review'

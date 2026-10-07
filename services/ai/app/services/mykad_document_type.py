"""Conservative OCR document-type gate, NOT MyKad authenticity verification."""

import re


MYKAD_HEADING = r'\b(?:MY\s*K[A4]D|K[A4]D\s+PENGEN[A4]L[A4]N)\b'


def other_card_evidence(text):
    """Return cue names only; never retain PANs, CVVs or identity values."""
    upper = text.upper()
    payment = []
    patterns = {
        'payment_card_heading': r'\b(?:CREDIT|DEBIT|BANK|PAYMENT)\s+CARD\b',
        'payment_scheme': r'\b(?:VISA|MASTER\s*CARD|AMERICAN\s+EXPRESS|UNION\s*PAY)\b',
        'payment_validity': r'\bVALID\s+(?:THRU|THROUGH)\b',
        'payment_security_code': r'\b(?:CVV|CVC|CVV2|CVC2|CARD\s+SECURITY\s+CODE)\b',
        'payment_signature_panel': r'\b(?:AUTHORI[ZS]ED\s+SIGNATURE|NOT\s+VALID\s+UNLESS\s+SIGNED)\b',
        'payment_expiry': r'\b(?:VALID\s+(?:THRU|THROUGH)|EXPIRY|EXPIRES)\s*[:\-]?\s*\d{2}/\d{2}\b',
        # Keep line boundaries: do not join unrelated address/IC digits across lines.
        'payment_number_shape': r'(?<![\dA-Z])(?:\d[ \t-]?){13,19}(?![\dA-Z])',
    }
    for cue, pattern in patterns.items():
        if re.search(pattern, upper):
            payment.append(cue)
    # A payment logo or long number alone is not sufficient to reject identity evidence.
    structural = set(payment) - {'payment_scheme', 'payment_number_shape'}
    clear_payment = ('payment_card_heading' in payment or
                     ('payment_scheme' in payment and bool(structural) and
                      ('payment_number_shape' in payment or len(structural) >= 2)) or
                     {'payment_security_code', 'payment_signature_panel'}.issubset(payment))
    if clear_payment:
        return 'payment_card', payment
    for kind, pattern in (
        ('other_malaysian_id', r'\b(?:MY\s*PR|MY\s*TENTERA|MY\s*K[A4]S|MY\s*KHAS)\b'),
        ('student_card', r'\bSTUDENT\s+(?:CARD|ID|IDENTITY\s+CARD)\b'),
        ('membership_card', r'\b(?:MEMBERSHIP|EMPLOYEE)\s+(?:CARD|ID)\b'),
    ):
        if re.search(pattern, upper):
            return kind, [f'{kind}_heading']
    return None, []


def assess_mykad_capture(text, certain_text, fields, certain_fields, expected_side, detected_side):
    """Single captured side: positive type evidence, not authenticity proof.

    The closed-set detector's label is necessary but never sufficient. Rear
    evidence needs registration/address text, not merely an arbitrary card.
    Returned metadata never includes OCR strings or document numbers.
    """
    validation = {
        'status': 'unconfirmed', 'accepted': False,
        'expectedSide': expected_side, 'detectedSide': detected_side,
        'method': 'detector-side-and-ocr-v1', 'authenticityVerified': False,
    }
    other_type, cues = other_card_evidence(certain_text)
    detected_type = certain_fields.get('documentType')
    if other_type or (detected_type and detected_type != 'mykad'):
        validation.update(status='wrong_document', evidence=cues)
        return validation, 'This is not MyKad. Scan your MyKad, not another card.'
    if not expected_side or not detected_side:
        return validation, 'MyKad side could not be verified. Rescan or retry the scanner service.'
    if detected_side != expected_side:
        validation['status'] = 'wrong_side'
        return validation, f'This appears to be the MyKad {detected_side}. Scan the {expected_side} instead.'
    upper = text.upper()
    if expected_side == 'front':
        if re.search(r'\bKETUA\s+PENGARAH\b', certain_text.upper()):
            validation['status'] = 'wrong_side'
            return validation, 'This appears to be the MyKad back. Flip the card and scan the front.'
        heading = bool(re.search(MYKAD_HEADING, certain_text.upper())) or (
            certain_fields.get('documentType') == 'mykad' and bool(re.search(r'\bMALAYSIA\b', certain_text.upper())))
        if not heading or certain_fields.get('documentType') != 'mykad' or certain_fields.get('identityNumberFormatValid') is not True:
            return validation, 'MyKad front could not be confirmed. Make the MyKad heading and IC number readable.'
    else:
        # A rear may mention MyKad in its text; registration evidence distinguishes
        # that from a front heading/address when YOLO mislabels a front as rear.
        rear_registration = bool(re.search(r'\bPENDAFTARAN\b', certain_text.upper()))
        if (re.search(MYKAD_HEADING, upper) or fields.get('documentType') == 'mykad') and not rear_registration:
            validation['status'] = 'wrong_side'
            return validation, 'This appears to be the MyKad front. Flip the card and scan the back.'
        if not re.search(r'\b(?:PENDAFTARAN|ALAMAT)\b', certain_text.upper()):
            return validation, 'MyKad back could not be confirmed. Make the registration/address text readable.'
    validation.update(status='validated', accepted=True)
    return validation, 'MyKad side checked. Review the image before using it.'


def assess_mykad_sides(texts, confident_texts, side_fields, confident_fields):
    """Reject clear other documents; require positive front evidence for review.

    Low-confidence OCR never supplies hard wrong-document cues. Absence of a
    heading is unconfirmed/rescan, not a claim that the physical card is fake.
    Rear IC absence is left for manual review, not treated as a holder match.
    """
    sides, wrong_reasons = [], []
    for index, (text, certain, fields, certain_fields) in enumerate(zip(
        texts, confident_texts, side_fields, confident_fields,
    )):
        side = 'front' if index == 0 else 'back'
        other_type, cues = other_card_evidence(certain)
        detected = certain_fields.get('documentType')
        if other_type:
            wrong_reasons.append(f'MyKad {side}: this appears to be a {other_type.replace("_", " ")}, not a MyKad.')
        elif detected and detected != 'mykad':
            wrong_reasons.append(f'MyKad {side}: this appears to be a {detected.replace("_", " ")}, not a MyKad.')
        sides.append({
            'side': side, 'observedType': other_type or detected or 'unconfirmed',
            'evidence': cues or certain_fields.get('documentTypeSignals', {}).get('mykad', {}).get('evidence', []),
            'hasReadableText': bool(text.strip()),
            'hasMykadHeading': bool(re.search(MYKAD_HEADING, text.upper())),
            'hasValidIdentityNumberFormat': fields.get('identityNumberFormatValid') is True,
        })
    validation = {
        'expectedType': 'mykad', 'status': 'plausible_mykad',
        'method': 'ocr_type_evidence_v1', 'authenticityVerified': False,
        'sides': sides,
    }
    if wrong_reasons:
        validation['status'] = 'wrong_document'
        return validation, 'wrong_document', wrong_reasons
    reasons = []
    if len(texts) != 2:
        reasons.append('MyKad identity review requires distinct front and back images. Please scan both sides.')
    if any(not side['hasReadableText'] for side in sides):
        reasons.append('One MyKad side has no readable OCR evidence. Please rescan that side.')
    front = side_fields[0] if side_fields else {}
    has_heading = bool(sides and sides[0]['hasMykadHeading']) or (
        front.get('documentType') == 'mykad' and bool(texts) and
        bool(re.search(r'\bMALAYSIA\b', texts[0].upper()))
    )
    if not has_heading or front.get('documentType') != 'mykad':
        reasons.append('The front image could not be identified as MyKad. Rescan with the MyKad / Kad Pengenalan heading readable.')
    if front.get('identityNumberFormatValid') is not True:
        reasons.append('A valid MyKad identity-number format could not be read on the front image. Please rescan; no authenticity verdict was made.')
    if reasons:
        validation['status'] = 'unconfirmed'
        return validation, 'rescan_required', reasons
    return validation, None, []

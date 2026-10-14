"""Malaysian licence OCR assistance, never JPJ/authenticity verification."""
import re
import math
from datetime import datetime, timedelta, timezone
from .mykad_document_type import other_card_evidence
from .mykad_readability import confident_lines, identity_candidates

CONTRACT = 'malaysian-driving-ocr-v1'
CLASSES = {'A', 'A1', 'B', 'B1', 'B2', 'C', 'D', 'DA', 'E', 'E1', 'E2', 'F', 'G', 'H', 'I'}
DATE = r'(?:\d{4}-\d{2}-\d{2}|\d{1,2}[/.\-]\d{1,2}[/.\-]\d{4})'

def parse_date(value):
    for fmt in ('%Y-%m-%d', '%d/%m/%Y', '%d-%m-%Y', '%d.%m.%Y'):
        try:
            return datetime.strptime(value, fmt).date()
        except ValueError:
            pass
    return None

def validity(text):
    """Only labelled expiry or explicit date ranges; never choose latest date."""
    dates, starts, invalid = set(), set(), False
    for match in re.finditer(r'\b(?:VALID UNTIL|EXPIRY|EXPIRES|TARIKH LUPUT|TARIKH TAMAT|SAH HINGGA)\s*[:\-]?\s*(' + DATE + r')', text, re.I):
        date = parse_date(match[1])
        if date: dates.add(date)
        else: invalid = True
    for match in re.finditer('(' + DATE + r')\s*(?:–|—|-|HINGGA|TO)\s*(' + DATE + ')', text, re.I):
        start, end = parse_date(match[1]), parse_date(match[2])
        if not start or not end or start > end: invalid = True
        else: starts.add(start); dates.add(end)
    if invalid or len(dates) != 1 or len(starts) > 1:
        return None, None, 'ambiguous' if len(dates) > 1 or len(starts) > 1 else 'unavailable'
    return next(iter(starts), None), next(iter(dates)), 'readable'

def analyse_licence(decoded, reader, preprocess, extract, source='physical', today=None):
    validation = {'method': CONTRACT, 'status': 'unavailable', 'acceptedForReview': False,
        'authenticityVerified': False, 'officialVerification': False, 'requiresAdminReview': True,
        'source': source, 'fieldStates': {}}
    if reader is None:
        return {'licenceValidation': validation}, 'unavailable', 'Licence text checks are unavailable. Retry when the AI service is ready.'
    try:
        lines = []
        scores = []
        for _, image in decoded:
            readings = reader.readtext(preprocess(image), detail=1, paragraph=False)
            lines.extend(confident_lines(readings))
            scores.extend(float(row[2]) for row in readings if len(row) >= 3 and
                          math.isfinite(float(row[2])) and 0 <= float(row[2]) <= 1)
        validation['ocrConfidence'] = sum(scores) / len(scores) if scores else 0
        text = '\n'.join(lines)
        fields = extract(text, 'driving_licence')
        # Labels bound extraction to an OCR line; preserve Unicode holder names.
        names = [re.sub(r'^\s*(?:NAME|NAMA)\s*[:\-]?\s*', '', line, flags=re.I).strip()
                 for line in lines if re.match(r'^\s*(?:NAME|NAMA)\b', line, re.I)]
        fields.pop('fullName', None)
        if len(set(names)) == 1 and sum(char.isalpha() for char in names[0]) >= 3:
            fields['fullName'] = names[0][:80]
        other, _ = other_card_evidence(text)
        heading = bool(re.search(r'\b(?:DR[I1L]V[I1L]NG\s+L[I1L]CEN[CS][E3]|LES[E3]N\s+MEM[A4]NDU)\b', text, re.I))
        if other or fields.get('documentType') not in (None, 'driving_licence'):
            validation['status'] = 'wrong_document'
            return {**({'documentType': fields['documentType']} if fields.get('documentType') else {}),
                    'licenceValidation': validation}, 'wrong_document', 'This is not a driving licence. Use your physical licence or MyJPJ licence image.'
        if not heading or fields.get('documentTypeResolution') == 'ambiguous':
            validation['status'] = 'rescan_required'
            return {'licenceValidation': validation}, 'rescan_required', 'The licence heading could not be read. Show the full Driving Licence / Lesen Memandu section clearly.'
        numbers = identity_candidates(lines)
        number = next(iter(numbers)) if len(numbers) == 1 else None
        private = extract(number, 'driving_licence') if number else {}
        # Never retain an arbitrary first candidate from generic OCR extraction.
        fields.pop('identityNumber', None)
        fields.pop('identityNumberFormatValid', None)
        fields['identityNumberFormatValid'] = False
        if number and private.get('identityNumberFormatValid') is True:
            fields.update(identityNumber=number, identityNumberFormatValid=True)
        class_values = [re.sub(r'^\s*(?:CLASS|KELAS)\s*[:\-]?\s*', '', line, flags=re.I).strip().upper()
                        for line in lines if re.match(r'^\s*(?:CLASS|KELAS)\b', line, re.I)]
        tokens = [token for value in class_values for token in re.split(r'[\s,/]+', value) if token]
        classes = sorted(set(tokens)) if tokens and all(token in CLASSES for token in tokens) else []
        fields.pop('licenceClass', None)
        if classes: fields['licenceClass'] = ', '.join(classes)
        valid_from, valid_until, date_state = validity(text)
        current = today or datetime.now(timezone(timedelta(hours=8))).date()
        expired = valid_until is not None and valid_until < current
        not_yet_valid = valid_from is not None and valid_from > current
        states = {'name': 'readable' if fields.get('fullName') else 'unavailable',
            'ic_number': 'readable' if fields.get('identityNumber') else 'ambiguous' if len(numbers) > 1 else 'unavailable',
            'licence_class': 'readable' if classes else 'unavailable', 'valid_until': date_state}
        validation.update(status='expired' if expired else 'not_yet_valid' if not_yet_valid else
            'needs_review' if any(state != 'readable' for state in states.values()) else 'ready_for_review',
            acceptedForReview=not (expired or not_yet_valid), fieldStates=states)
        fields.update(documentType='driving_licence', licenceClasses=classes,
            licenceValidation=validation, reviewScope='driving_eligibility',
            documentExpired=expired, documentRiskModel='not_applicable', requiresAdminReview=True)
        if valid_until: fields['validUntil'] = valid_until.isoformat()
        if valid_from: fields['validFrom'] = valid_from.isoformat()
        message = 'This licence has expired. Upload renewed evidence.' if expired else \
            'This licence is not valid yet. Check its validity dates.' if not_yet_valid else \
            'Licence detected. Some details need administrator review.' if validation['status'] == 'needs_review' else \
            'Licence details checked. Administrator review is still required.'
        return fields, 'rescan_required' if expired or not_yet_valid else 'manual_review', message
    except Exception:
        return {'licenceValidation': validation}, 'unavailable', 'Licence text checks could not complete. Retry or upload a clearer image.'

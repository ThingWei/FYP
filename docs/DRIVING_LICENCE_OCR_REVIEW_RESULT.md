# Malaysian driving-licence OCR-assisted review

Updated: 14 October 2026

## Implemented workflow

The live driving-eligibility form now separates **Physical licence** from
**MyJPJ digital licence**. Physical evidence supports camera capture and upload;
digital evidence uses a protected image upload. Both run the same licence OCR
checks before submission. A selected format is an evidence hint, not proof of
origin or authenticity. MyJPJ screenshots are not rejected under the physical
MyKad screen-copy policy.

Final camera capture no longer allows any arbitrary licence photograph through
`Use Image`. It calls Express, which privately performs the licence OCR check and
holder comparison. Uploaded files receive the same read-only check after upload.
The final submission independently rereads the stored bytes and reruns analysis;
Flutter results and supplied IC values are never authoritative.

| Check | Behavior |
| --- | --- |
| Resolution, blur, lighting and glare | Existing image-quality policy; poor captures need a new image |
| Readable licence heading | Confident Driving Licence / Lesen Memandu heading required; wrong or unclassified cards cannot enter review |
| OCR confidence | Existing 0.60 threshold, not globally reduced |
| Holder IC | Exactly one confidently readable, valid 12-digit candidate; normalize spaces/hyphens and preserve leading zeros; never substitute OCR letters with digits |
| Holder comparison | Prefer the administrator-approved MyKad binding; legacy current-key fingerprint remains a fallback; confident mismatch needs new evidence |
| Name | Extract explicit NAME/NAMA lines without losing Unicode; unlabeled or uncertain names require manual review, not a guessed name |
| Licence class | Explicit CLASS/KELAS line and existing whitelist; ambiguous/unsupported extraction requires manual review |
| Validity | Explicit labelled expiry or a complete date range; never choose an arbitrary latest date or birth/issue date |
| Expired/not-yet-valid | Confident validity dates are checked against the Malaysian calendar; request updated evidence |
| Uncertain holder, class or validity | Plausible licence may enter manual review; it cannot grant driving eligibility automatically |
| OCR unavailable or incompatible contract | Retry before submission; a bypassed direct submission becomes resubmission-required, not approvable pending |

Recognizing a heading or IC format does not establish the issuing authority.
An administrator must still inspect the protected evidence and confirm the holder
against approved MyKad, reviewed classes and future expiry. The review dialog
prefills readable classes/expiry from the saved attempt, but retains editable
fields and both explicit confirmation checkboxes. Existing vehicle booking,
handover and extension eligibility checks remain unchanged.

## Interfaces, privacy and compatibility

- New authenticated read-only endpoint:
  `POST /api/v1/users/me/driving-eligibility/check` with owned `documentRef` and
  optional `licenceSource: physical | myjpj`.
- Existing final-frame and submission endpoints accept the optional source hint;
  existing clients default to physical. Existing endpoint paths are preserved.
- New licence contract: `malaysian-driving-ocr-v1`, advertised in AI health.
  API readiness includes `driving-licence-ocr-review-v1`; the launcher checks both.
  MyKad remains on its existing v6 frame/v2 required-field contracts.
- Express verifies upload ownership and verification-document purpose before
  reading files. Preview checks do not create attempts, modify approvals or write
  fingerprints. Safe responses include class/date/state information, never full
  IC numbers, OCR text or fingerprints. Saved evidence uses existing masking.
- Draft validation is bound to the current image and source mode. Replacement,
  removal or mode changes invalidate old checks; late replies are ignored.
  Network failure preserves the uploaded photo and offers explicit retry.
- Existing approved identities/driving eligibility are not revoked or migrated.
  Historical attempts and MyKad/pair matching remain intact.

## Setup and limitations

Restart the API, AI service and Flutter app using the updated `run-renthub.ps1`.
No new dependency, licence training dataset, model download or retraining is
needed. Existing OpenCV and installed EasyOCR language models must be available.
Keep the existing stable `KYC_IDENTITY_MATCH_SECRET`; do not rotate or regenerate
it. A missing/current-key-incompatible approved fingerprint makes the automatic
holder comparison unavailable and requires protected manual comparison.

OCR can misread clear text and miss unlabelled fields. Date/class/name extraction
is deliberately conservative; uncertain details are not invented. These checks
are not anti-counterfeit certification, liveness, facial recognition, rightful
ownership verification or an official JPJ lookup. No QR decoder/integration was
added. JPJ's [MyJPJ FAQ](https://myjpj.jpj.gov.my/faq) describes digital-licence
evidence and enforcement QR scanning; RentHub does not claim those official
verification capabilities.

## Verification results

- AI suite: **381 passed**, two existing dependency deprecation warnings.
- API suite: **322 passed / 3 skipped**, using isolated temporary MongoDB rather
  than the live database. Covers private preview, foreign/wrong-purpose uploads,
  unauthorized requests, final capture, mismatches, uncertain OCR, expiry,
  incompatible analysis, resubmission and blocked approval.
- Focused Flutter KYC/account suite: **51 passed**. Includes source selection,
  upload preservation/retry, stale mode responses, scanner gates, MyKad
  replacement/pair regression, 360/390 widths and increased-text feedback layouts.
- `flutter analyze lib`: clean. Full analysis retains only the two pre-existing
  undefined Auth0 test constructor parameters (`latestLinkProvider` and
  `mobileLinkPollInterval` in `test/auth0_persistence_test.dart:41/43`).
- Launcher regression: passed, including missing/old licence contract checks.
- Web and Android debug builds: passed. Existing web Wasm/socket interop/font
  warnings and Android plugin Kotlin migration warnings remain unrelated.
- No personal licence photographs were added as test fixtures or used for training.

## Real-device handoff (still required)

1. Physical licence: capture the whole licence under good lighting; confirm
   image feedback, holder matching and manual administrator approval.
2. MyJPJ: upload a full licence view, including class and validity rather than
   only a QR image. Confirm digital evidence is not rejected as a MyKad screen copy.
3. Try an unrelated card, a clearly expired licence and a confidently read
   different holder. Expect rescan/new evidence and disabled submission.
4. Use uncertain but plausibly typed licence evidence. Confirm manual-review
   wording and that approval still needs both administrator confirmations.
5. Stop the AI service temporarily. Confirm retry keeps the image and does not
   submit an approvable attempt. Replace/remove evidence and change its mode while
   checks run; old replies must not restore eligibility.

These device checks are not claimed complete by synthetic unit/widget tests.

## Commit message

```text
feat(kyc): add OCR-assisted Malaysian driving licence review

- separate physical licence and MyJPJ evidence selection
- gate final captures and uploads with shared licence OCR checks
- compare holder IC privately with approved MyKad bindings
- block confident mismatch, expiry and unavailable analysis
- preserve uncertain evidence for explicit administrator review
- retain uploaded drafts and ignore stale image or mode responses
- prefill reviewed classes and expiry without automatic approval
- align AI/API readiness and launcher contract checks
- add licence, privacy and MyKad regression tests and handoff docs
```

# RentHub Scope Alignment Audit Result

> Historical audit notice (5 October 2026): the KYC, recommendation, pricing,
> and blockchain placeholder findings below describe the 27 September baseline.
> The current KYC implementation and remaining artifact gaps are recorded in
> `KYC_AI_RESULT.md`; do not use the old KYC status table as the current result.

Date: 27 September 2026

## Executive result

RentHub's Flutter, Express, Socket.IO, MongoDB, Auth0-ready authentication, and storage-backed business flows are substantially implemented and connected in live mode. The ten required business modules exist and the final live renter, Owner, and administrator shells use the Express API when `USE_MOCKS=false`.

The three FYP core-technology areas are not complete:

- image/document intelligence is a deterministic FastAPI placeholder and is not called by Express;
- recommendation and rental-price endpoints use placeholder output and have no trained/evaluated models;
- the Solidity contract is unit-tested in isolation, while the Express blockchain adapter returns `not-configured` and lifecycle records contain mock references.

These are P0 completion gaps. The next implementation must preserve the existing business flows and replace the adapters behind their current boundaries.

## A. Functional scope readiness

| Priority | Area | Status | Evidence and remaining gap |
|---|---|---|---|
| P0 | User Management | PARTIAL | Auth, roles, profiles, role switching, verification states, blocking, and administrator status actions are live. Google OAuth remains an unresolved scope conflict; account deactivation/session-device management are not complete. |
| P0 | KYC/document verification | PLACEHOLDER | Private uploads, MongoDB state, admin decisions, and UI exist. OCR fields and confidence are hard-coded; no YOLOv8, OpenCV, EasyOCR, spaCy/Regex extraction, or EfficientNet inference is connected. |
| P0 | Listing Management | PARTIAL | Physical/service CRUD, moderation, images, availability, promotions, and same-Owner bundle metadata are live. Item legitimacy and ML price recommendation are missing; physical-photo minimum is not the specified three. |
| P0 | Booking Management | ALIGNED | Server-authoritative physical/service booking contracts, date validation, Owner decisions, cancellation, and idempotency are live. Current final order is booking creation followed by simulated authorization under one renter-scoped idempotency key. |
| P0 | Payment Management | ALIGNED | Simulated authorization, capture, deposit records, settlements, refunds, monitoring, and duplicate protection are live and clearly labelled simulated. |
| P0 | Rental Management | PARTIAL | Handover, extension, return, inspection, deposit outcome, and separate service lifecycle are live. Blockchain agreement/state synchronization and a confirmed overdue policy are missing. |
| P0 | Communication Management | PARTIAL | Booking-linked REST/Socket.IO messaging, notifications, reports, read state, and participant access are live. FCM push delivery, image messages, and location pins are not implemented. |
| P1 | Review Management | ALIGNED | Completion-gated multi-aspect reviews, editing window, listing display, flagging, moderation, and Owner summaries are live. No removed sentiment-analysis claim is made. |
| P0 | Dispute/claim Management | PARTIAL | Evidence, participant responses, admin outcomes, claims, audits, and simulated allocations are live. The blockchain result is a generated `MOCK-CHAIN-*` string, not a transaction. |
| P1 | Loyalty and Referral Management | ALIGNED | Persistent points, idempotent earning, redemption, referral lifecycle, settings, notifications, and admin views are connected. |
| P1 | Admin Management | PARTIAL | Core users, verification, listings, transactions, disputes/claims, reports, reviews, settings, and audit logs are live. Advanced platform health, ML metrics, scheduled reports, and exports are not complete. |
| P2 | Bundle booking | DEFERRED | Same-Owner bundle metadata is supported. Multi-item checkout and all cross-Owner lifecycle/payment allocation are intentionally absent. |
| P2 | Guide/FAQ | PARTIAL | Basic help/support UI exists; the expanded searchable, category-specific guide is not a separate completed capability. |

## B. Technology readiness

| Technology | Configured | Integrated | Real implementation | Tested/evaluated | Status |
|---|---:|---:|---:|---:|---|
| Flutter / Flutter Web | Yes | Yes | Yes | Yes | ALIGNED |
| Express / Mongoose / MongoDB | Yes | Yes | Yes | Yes | ALIGNED |
| Socket.IO | Yes | Yes | Yes | Yes | ALIGNED |
| Auth0 JWT | Yes | Yes | Yes | Build/contract tested; tenant E2E pending | PARTIAL |
| Supabase Storage | Yes | Yes | Yes | Configuration tests pass; cloud E2E pending | PARTIAL |
| FastAPI | Yes | No | Service shell only | Contract tests only | PLACEHOLDER |
| YOLOv8 | No | No | No | No | MISSING |
| OpenCV | No | No | No | No | MISSING |
| EasyOCR | No | No | No | No | MISSING |
| spaCy + Regex extraction | No | No | No | No | MISSING |
| EfficientNet-B0 | No | No | No | No | MISSING |
| Surprise SVD | No | No | No | No | MISSING |
| Scikit-learn cosine similarity | No | No | No | No | MISSING |
| Hybrid recommendation | No | No | No | No | PLACEHOLDER |
| XGBoost rental pricing | No | No | No | No | PLACEHOLDER |
| Solidity contract | Yes | Isolated only | Yes | Hardhat unit tests exist | PARTIAL |
| Ganache / Hardhat | Yes | Deploy script only | Yes | Contract tests exist | PARTIAL |
| Ethers.js API adapter | No | No | No | No | MISSING |
| OpenStreetMap/geospatial | Yes | Adapter only | Nominatim geocoding | Unit tested; UI map deferred | PARTIAL |
| Firebase Cloud Messaging | Preference fields only | No | No | No | DEFERRED |

## C. Core-technology findings

### C1. KYC and document intelligence — PLACEHOLDER

Current flow:

```text
Flutter file picker -> authenticated upload -> Express -> Supabase/local storage
-> MongoDB pending verification -> manual administrator decision
```

The FastAPI `/verify/document` endpoint returns a constant confidence based only on whether an image URL is present. Express never calls the FastAPI client. MongoDB stores placeholder masked data and a later hard-coded confidence.

Required replacement:

```text
stored image bytes -> OpenCV quality/alignment preprocessing
-> YOLOv8 document detection -> EasyOCR -> spaCy/Regex field parsing
-> EfficientNet-B0 risk indicator -> confidence/flags/manual-review outcome
-> Express validation -> MongoDB -> final verification/admin UI
```

The result must remain a document risk/consistency assessment, not a claim of legal identity proof.

### C2. Item legitimacy — MISSING

Uploads are real, but listing submission does not require three images or run item/category detection, perceptual duplicate checks, category consistency, or an EfficientNet risk model. Listing moderation therefore has no AI evidence to review.

### C3. Recommendation — PLACEHOLDER

Public discovery's `recommended` sort is promotion, rating, then recency. FastAPI returns synthetic `demo-item-*` records. There is no interaction dataset, Surprise SVD model, TF-IDF/cosine content model, 0.6/0.4 hybrid score, evaluation metric, availability filtering, or Express/UI integration.

### C4. Rental-price prediction — PLACEHOLDER

The request schema names several relevant values, but the current adapter applies a deterministic arithmetic formula. There is no simulated training dataset, feature pipeline, XGBoost artifact, MAE/RMSE evaluation, explanation, MongoDB feature aggregation, or Owner live-form integration.

### C5. Blockchain — PARTIAL

`RentalAgreement.sol` implements signing, activation, completion, cancellation, dispute, and resolution with local test ETH and has Hardhat tests. However:

- the Express API has no `ethers` dependency;
- `blockchainAdapter.createAgreement()` always returns `not-configured`;
- no booking/rental service calls the adapter;
- no participant agreement acknowledgement is persisted on-chain;
- dispute resolution writes a mock string without a Ganache transaction;
- MongoDB contract/hash fields are unused.

The approved target is local Ganache only. It must never be presented as a real payment, public-chain deployment, or financial escrow.

## D. End-to-end lifecycle readiness

| Lifecycle | Status | Core gap |
|---|---|---|
| Registration/login/profile | PARTIAL | Real Auth0 tenant verification pending; Google OAuth unresolved |
| KYC submission/admin review | PLACEHOLDER | No real CV/OCR/risk inference |
| Discovery/physical checkout/payment | ALIGNED | ML recommendation not used |
| Owner approval/rejection | ALIGNED | No local contract deployment/agreement record |
| Agreement/signing | MISSING | UI acknowledgement is not synchronized with Ganache |
| Handover/active rental | PARTIAL | Business state live; chain state absent |
| Extension | ALIGNED | Chain does not record extension, which is not required by current contract |
| Return/inspection/deposit outcome | PARTIAL | Business/payment simulation live; chain completion absent |
| Dispute/claim | PARTIAL | Admin workflow live; chain dispute/resolution absent |
| Review | ALIGNED | None |
| Service lifecycle | ALIGNED | Correctly excludes physical/blockchain return behavior |
| Messaging | ALIGNED | FCM/image messages deferred |
| Admin moderation | PARTIAL | AI evidence and model metrics absent |
| Loyalty/referral | ALIGNED | None |

## E. Scope decisions requiring confirmation

The following conflicts are recorded and are not silently resolved by the core-technology implementation:

1. **Google OAuth:** newer scope mentions it; the older final handover removed social login. Current Auth0 Universal Login remains unchanged.
2. **Owner navigation label:** active mock and live shells use `Requests`; the latest handover says `Bookings`. No rename is made in this phase.
3. **Booking/payment ordering:** the safe live implementation creates a pending booking first, then authorizes its server-calculated amount, protected by a shared idempotency key. This remains the final behavior unless explicitly changed.
4. **Overdue alerts:** not implemented as a dedicated lifecycle automation and remains unresolved.
5. **Cross-Owner bundles:** not implemented because they require separate approvals, allocations, deposits, rentals, contracts, returns, and disputes.
6. **Advanced admin/scheduled reports:** deferred beyond the simplified final use cases.
7. **Guide/FAQ placement:** existing help remains under account/profile; no new top-level module is introduced.
8. **OCR wording:** EasyOCR is selected as the single OCR engine, matching the earlier technical decision; pytesseract will not be added in parallel.
9. **NLP sentiment:** remains removed. spaCy is used only for KYC field extraction/normalization.

## F. Approved implementation direction

The user's latest instruction explicitly authorizes implementation of the missing core technologies. Work will proceed without changing the unresolved product decisions above:

1. replace FastAPI placeholders with real, failure-aware CV/OCR inference contracts;
2. add reproducible simulated datasets, training/evaluation scripts, artifacts, and inference for hybrid recommendation and XGBoost pricing;
3. connect Express services and MongoDB evidence/results to the active live Flutter screens;
4. integrate the existing Solidity contract through Ethers.js with local Ganache and persist address/hash/state references;
5. add representative FastAPI, API, contract, and Flutter contract tests;
6. label model outputs as recommendations/risk indicators and blockchain values as local prototype records.

Real model completion will only be claimed when the repository contains dataset provenance, preprocessing, training, an artifact, inference, metrics, tests, and an end-to-end UI path. If optional model weights or external services are absent, the system must return an explicit `unavailable`/manual-review state rather than fabricated confidence.

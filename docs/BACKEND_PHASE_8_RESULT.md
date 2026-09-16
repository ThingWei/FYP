# Backend Phase 8 Result: Loyalty and Referrals

## Result

Loyalty and Referral Management is now a dedicated Express and MongoDB domain connected to the final renter, Owner, and administrator interfaces. It replaces the previous generic rewards placeholder.

## Loyalty accounts and points

- Every authenticated user receives one persistent loyalty account and referral code.
- Completing a physical rental awards the configured physical-rental points to its renter.
- Completing a service order awards the configured service-completion points to its renter.
- Completion awards use a unique lifecycle source key, so retrying a completion action does not award points twice.
- The live loyalty page shows the current balance, total earned, total redeemed, activity ledger, and configured earning rules.
- Point changes create persistent loyalty notifications.

## Redemption

- Administrators define the supported point-to-Ringgit redemption options.
- A user can redeem only an exact configured option and only when the programme is enabled.
- The API checks the current balance and performs the deduction server-side.
- A successful redemption creates a traceable booking reward code in the immutable ledger.
- The final mobile UI disables unaffordable options and shows the generated code and value after redemption.

The reward is a RentHub booking discount record only. This phase does not transfer money or integrate a payment provider.

## Referrals

- Users can copy/share their persistent referral code from the final mobile UI.
- A new renter can apply one other user's code before completing a first booking.
- Self-referrals and duplicate referrals are rejected.
- Applying a code creates a pending referral without immediately granting a reward.
- After the referred renter's first completed booking, the referrer receives the configured points and the referee receives a configured booking discount code.
- Completion processing is idempotent and cannot reward the same referral twice.

## Administrator workflow

The live Platform Settings destination now lets an administrator configure:

- programme enabled/paused status;
- physical-rental completion points;
- service-completion points;
- referrer reward points;
- referred-renter discount value; and
- redemption point/value pairs.

Updates are validated by the API and recorded in the append-only administrator audit log. The page also shows recent reward-ledger entries and referral activity from MongoDB.

## Main endpoints

- `GET /api/v1/rewards/summary`
- `POST /api/v1/rewards/redeem`
- `POST /api/v1/rewards/referrals/apply`
- `GET /api/v1/rewards/admin/config`
- `PUT /api/v1/rewards/admin/config`
- `GET /api/v1/rewards/admin/ledger`
- `GET /api/v1/rewards/admin/referrals`

## Seed data

The idempotent seed includes five loyalty accounts, a renter activity ledger, a pending referral, and the default earning, referral, and redemption rules. Seeded relationships use the same user identifiers as the booking and rental records.

## Validation

- `npm.cmd test`: 37 of 37 API tests passed.
- `flutter analyze`: no issues found.
- `flutter test`: 59 of 59 Flutter tests passed.
- Live renter/Owner JavaScript web build: passed with `USE_MOCKS=false`.
- Live administrator JavaScript web build: passed with `USE_MOCKS=false`.

Flutter reports the existing upstream Socket.IO WebAssembly dry-run warning and Cupertino icon font notice. Standard JavaScript web builds complete successfully.

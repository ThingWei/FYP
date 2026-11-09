# One-day physical rental date fix

Implemented 9 November 2026. Previous notification/checkout changes are preserved.

## Cause and change

The booking form's initial start and end values used `DateTime.now()` plus days,
retaining hours/minutes. Selecting an end date returns midnight. Leaving the
displayed start unchanged and choosing the same end day therefore made the end
instant earlier than the hidden start time. Calendar availability then wrongly
reported an unavailable range; submission could also stop on the raw comparison.

A unit test and widget test reproduced this failure before the fix.

- Default dates now start from Malaysia's calendar day without a time component.
  The initial end date is derived from that same start day.
- Selected dates are explicitly stored as calendar days.
- The shared calendar-day availability check compares normalized dates, rather
  than hidden time components. End-before-start calendar days are still rejected.
- Confirmed bookings and Owner-blocked days still prevent a one-day rental and
  ranges crossing them. Pending requests remain soft holds.
- Service appointment times and server booking/payment/approval rules are not
  changed. The API already supports equal physical start/end dates and charges
  them inclusively as one day; no production API change was needed.

## Verification

Added tests cover:

1. Equal calendar dates with a hidden afternoon start time and midnight end.
2. Keeping the form's displayed default start and choosing the same end day.
3. Explicitly selecting 16 November 2027 for both dates in the picker.
4. Reversed calendar days, a blocked one-day rental and a range crossing a block.
5. API creation/reopening for `2027-11-16` to `2027-11-16`: unchanged dates,
   one rental day, one day's base amount, pending and unpaid without payment.

Focused date-picker tests: **10 passed**. Full isolated API suite: **680 passed,
3 existing opt-in skips**. Full Flutter suite: **659 passed, 3 existing skips**.
Flutter analysis: **No issues found**. Main web, admin web and Android debug APK
builds: **passed**. Model/metrics hashes: **unchanged**. Logs are in the private
execution pack `.data/testing/20261109-122812-133853b0`.

The existing Owner-preview and no-crossing-blocked-dates tests remain passing.
No live booking, availability entry, account or payment was changed. Automated
results do not mark the user's manual result sheets passed.

## Device retest

Relaunch/rebuild the Android app using the usual launcher; building an APK alone
does not install it. On an available physical listing, keep the displayed start
and choose that same day as the end. Both fields should show the same date with
no unavailable-range warning, and checkout should charge one rental day. Also
check the explicitly reported 16 November 2027 example when it is genuinely free.

## Commit message

```text
fix(booking): allow available one-day physical rentals

- remove hidden times from initial and selected rental dates
- compare availability using inclusive calendar days
- retain blocked-range and reversed-date restrictions
- cover same-day picker selection and one-day API pricing/reopening
```

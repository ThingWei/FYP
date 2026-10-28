# Active listing actions

27 October 2026, Malaysia time.

The Owner listing editor no longer offers **Save Draft** for an active listing.
It shows **Save changes & submit for review** and explains that edited published
listings need review before appearing again. The draft-only save path also refuses
an active listing locally. New listings and existing drafts retain unfinished saves.

Existing API policy is preserved: editing an active listing returns it to draft,
then successful submission sends it to pending review. There is no approval bypass
or promise that edited content stays publicly active. Form validation happens
before writes; submission failures retain the existing saved-draft recovery path.
No database records or active listing statuses were changed by this UI fix.

Verification:

- Active form checked at 360/390 pixels with 1.4 text scaling: no draft action,
  review guidance/action visible, no overflow or API calls on opening.
- Draft pricing/save regression fixtures explicitly represent draft listings.
- Focused Flutter tests: 42 passed, 1 existing skip.
- Full Flutter suite: 481 passed, 3 existing skips.
- Flutter analysis: no issues.
- Web build: passed. Existing nonblocking Wasm/dependency and optional Cupertino
  font warnings remain; no new analyzer errors.

Commit message:

```text
fix(owner): remove draft action when editing active listings

- show one review submission action for published listings
- explain the existing moderation requirement before saving
- preserve incomplete draft saves and existing API approval rules
- cover active and draft actions at mobile widths with larger text
```

# Friendly copy and listing photo review

Date: 5 November 2026

## Implemented

- **Pricing:** the expanded explanation contains at most four short, plain-language lines: what was compared, available price counts, missing comparison details when applicable, and the distinction between advertised and final prices. Full response diagnostics remain available in the presentation adapter's original response. Existing rough-estimate, limited-real-data, demonstration and longer-rental warnings remain visible.
- **Apply price:** “Use this price” fills the price field, records its AI origin and hides the suggestion card. The suggestion button remains available. Owners can edit the applied amount; AI lineage is retained. Applying a suggestion does not save or submit the listing.
- **Messages/Profile:** empty conversations say “Say hello or ask about the booking.” The API/database connection tile was removed from Profile. Review success and rewards-loading messages also use ordinary language.
- **Photo review:** Owner and administrator item-photo dialogs now show a horizontal carousel with a photo counter, Previous/Next buttons and swipe navigation. Photos retain their aspect ratio; tapping still opens the existing zoom viewer with the correct photo's evidence overlay. Empty, loading, unavailable and retry handling reuse the existing image loader.
- **Photo guidance:** status and main notes have their own padded section. Expanded photo details use labelled cards and separate lines. Within the carousel dialog, individual details follow the selected photo instead of displaying every photo's notes together. Overall listing concerns and the authenticity limitation remain available. Administrator diagnostics remain explicitly collapsed/optional.
- **Availability:** only active listings offer the Availability menu item. Pending/draft listings cannot open the unavailable public-availability request through that action. Opening the availability page directly for a non-active record shows an approval/publishing explanation without making an API call or offering Save. Existing active-listing availability behaviour remains unchanged.

No backend endpoints, permissions, pricing calculations, deployed models, booking rules or stored records were changed in this update. Existing uncommitted work was preserved.

## Verification

- Full Flutter suite: **603 passed, 3 existing optional skips**.
- Final focused photo/Owner tests: **47 passed**, including 360/390/1024-pixel carousel controls, large text, zoom/close, friendly photo guidance, pending/draft menu exclusions and the direct-page guard.
- Pricing tests cover short explanations, unavailable/malformed metadata, hidden cards after applying a price, requesting another suggestion and preserved AI price provenance on draft submission.
- Empty chat/Profile tests cover 360/390-pixel screens with larger text and check that API/database wording is absent.
- Flutter analysis: **no issues found**.
- Web and Android debug builds: **passed**. Existing nonfatal WebAssembly/font and Kotlin-plugin migration warnings remain. No new production dependency was added.

## Preview

1. Open an Owner listing and choose “Suggest a daily price.” Expand the explanation, then choose “Use this price”: the field is filled and the card closes.
2. Tap a physical listing in My Listings. Swipe photos or use the arrows; expand Photo details and check that its individual photo note follows the selection. Tap the image to zoom.
3. Open a pending listing's menu: Availability is absent. Active listings retain it.
4. Open an empty conversation and Profile to check the simplified wording.

## Commit message

```text
feat: simplify marketplace copy and improve listing photo review

- shorten pricing explanations and dismiss applied suggestions
- preserve AI price provenance and manual price editing
- replace database/API wording in messages, profile, reviews and rewards
- show listing photos in a responsive swipeable carousel
- separate photo guidance and selected-photo details
- gate availability controls until listings are approved and active
- add mobile, large-text and interaction regressions
```

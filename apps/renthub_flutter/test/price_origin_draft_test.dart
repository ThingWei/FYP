import 'package:flutter_test/flutter_test.dart';
import 'package:renthub_flutter/core/pricing/price_origin_draft.dart';
import 'package:renthub_flutter/shared/models/domain_models.dart';

void main() {
  test(
      'draft declarations retain AI lineage without claiming reviewed evidence',
      () {
    final draft = PriceOriginDraft();
    expect(draft.origin, 'unknown');
    draft.edited();
    expect(draft.origin, 'owner_entered');
    draft.useSuggestion(45.50, 'test-model');
    expect(draft.toJson(), {
      'origin': 'ai_suggested',
      'suggestedAmount': 45.5,
      'modelVersion': 'test-model'
    });
    draft.edited();
    expect(draft.origin, 'ai_edited');
    expect(draft.toJson().containsKey('independence'), false);
    final reopened = PriceOriginDraft(origin: draft.origin)..edited();
    expect(reopened.origin, 'ai_edited');
  });
  test(
      'listing origin defaults safely for legacy responses and survives reopening',
      () {
    final input = {'id': 'item', 'category': 'Devices', 'dailyPrice': 25};
    expect(Listing.fromJson(input).priceOrigin, 'unknown');
    expect(
        Listing.fromJson({
          ...input,
          'priceProvenance': {'origin': 'ai_suggested'}
        }).priceOrigin,
        'ai_suggested');
  });
  test('server-owned external origin is not sent as a client declaration', () {
    final draft = PriceOriginDraft(origin: 'external_reference');
    expect(draft.toJson()['origin'], 'unknown');
    expect(
        Listing.fromJson(
            {'id': 'demo', 'category': 'Devices', 'status': 'draft'}).condition,
        '');
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:renthub_flutter/core/theme/app_theme.dart';
import 'package:renthub_flutter/core/network/api_client.dart';
import 'package:renthub_flutter/features/live/live_saved_place_selector.dart';
import 'package:renthub_flutter/features/live/live_owner_attention.dart';
import 'package:renthub_flutter/features/live/live_listing_gallery.dart';
import 'package:renthub_flutter/features/live/live_dispute_page.dart';
import 'package:renthub_flutter/features/live/live_rental_progress.dart';
import 'package:renthub_flutter/features/live/live_renthub_controller.dart';
import 'package:renthub_flutter/shared/models/domain_models.dart';
import 'booking_case_usability_test.dart' as fixture;

UserAddress place({String id = 'A', bool automatic = false}) => UserAddress(
    id: id,
    automatic: automatic,
    label: 'Pickup',
    line1: 'Jalan Example 12',
    city: 'Setapak',
    state: 'Kuala Lumpur',
    postcode: '01234',
    latitude: 3.2,
    longitude: 101.7);

class ReturnPageApi extends ApiClient {
  ReturnPageApi() : super('https://unused.invalid');
  @override
  Future<dynamic> request(String method, String path, {Object? body}) async {
    if (method == 'POST') {
      return {
        ...fixture.rentalRow('disputed'),
        'returnAllowed': false,
        'returnSubmission': {
          'condition': 'Good',
          'recordedAt': '2026-11-15T10:00:00Z',
          'evidence': ['upload://RETURN']
        }
      };
    }
    return ApiItems([], {'page': 1, 'limit': 20, 'total': 0});
  }
}

void main() {
  testWidgets(
      'delivery selection survives refreshed profile objects behind checkout',
      (t) async {
    final selected = <UserAddress>[];
    final addresses = ValueNotifier<List<UserAddress>>([place()]);
    addTearDown(addresses.dispose);
    await t.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
            body: ValueListenableBuilder<List<UserAddress>>(
                valueListenable: addresses,
                builder: (context, value, _) => Column(children: [
                      SavedPlaceSelector(
                          addresses: value, onSelected: selected.add),
                      TextButton(
                          onPressed: () => Navigator.push<void>(
                              context,
                              MaterialPageRoute(
                                  builder: (_) =>
                                      const Scaffold(body: Text('Checkout')))),
                          child: const Text('Continue')),
                    ])))));
    await t.tap(find.byType(DropdownButtonFormField<String>));
    await t.pumpAndSettle();
    await t
        .tap(find.text('Jalan Example 12, Setapak, Kuala Lumpur, 01234').last);
    await t.pumpAndSettle();
    expect(selected.single.id, 'A');
    await t.tap(find.text('Continue'));
    await t.pumpAndSettle();
    addresses.value = [
      place()
    ]; // User.fromJson creates new objects after booking.
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    Navigator.of(t.element(find.text('Checkout'))).pop();
    await t.pumpAndSettle();
    expect(
        t
            .widget<DropdownButtonFormField<String>>(
                find.byType(DropdownButtonFormField<String>))
            .initialValue,
        'saved:A');
    addresses.value = [place(id: 'B')];
    await t.pumpAndSettle();
    expect(
        t
            .widget<DropdownButtonFormField<String>>(
                find.byType(DropdownButtonFormField<String>))
            .initialValue,
        isNull);
    expect(selected.length,
        1); // Refresh/removal never changes the confirmed destination.
    expect(t.takeException(), isNull);
  });

  testWidgets(
      'saved places deduplicate keys and display addresses, not a Pickup destination',
      (t) async {
    await t.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
            body: SavedPlaceSelector(
                addresses: [place(automatic: true), place(automatic: true)],
                onSelected: (_) {}))));
    await t.tap(find.byType(DropdownButtonFormField<String>));
    await t.pumpAndSettle();
    expect(find.text('Recent place'), findsOneWidget);
    expect(find.text('Pickup'), findsNothing);
    expect(t.takeException(), isNull);
  });

  test(
      'return eligibility stays conservative for old disputed records and services',
      () {
    expect(const Rental('R', 'active').canSubmitReturn, isTrue);
    expect(const Rental('R', 'disputed').canSubmitReturn, isFalse);
    expect(const Rental('R', 'completed', returnAllowed: true).canSubmitReturn,
        isFalse);
    expect(const Rental('R', 'disputed', returnAllowed: true).canSubmitReturn,
        isTrue);
    expect(
        const Rental('R', 'disputed',
                listingType: 'service', returnAllowed: true)
            .canSubmitReturn,
        isFalse);
    final record = Rental.fromJson({
      ...fixture.rentalRow('disputed'),
      'returnAllowed': true,
      'returnSubmission': {
        'condition': 'Good',
        'recordedAt': '2026-11-15T10:00:00Z'
      }
    });
    expect(record.canSubmitReturn, isFalse);
    expect(record.hasOverdueReturn, isFalse);
    expect(RentalJourney.forRecord(rental: record).title,
        'Return submitted. Case under review');
  });

  test(
      'return response preserves evidence even when refreshed pages omit the rental',
      () async {
    final c = LiveRentHubController(ReturnPageApi())..profile = fixture.renter;
    addTearDown(c.dispose);
    final old = Rental.fromJson(
        {...fixture.rentalRow('disputed'), 'returnAllowed': true});
    c.renterWorkspace.rentals = [old];
    await c.runRentalAction(old, 'return', body: {
      'condition': 'Good',
      'evidence': ['upload://RETURN']
    });
    final saved = c.currentDisputeRental(old);
    expect(saved.returnSubmission!.photos, ['upload://RETURN']);
    expect(saved.status, 'disputed');
    expect(saved.canSubmitReturn, isFalse);
    c.profile = fixture.owner;
    expect(c.rentals, isEmpty);
  });

  for (final width in [360.0, 390.0, 1024.0, 1440.0]) {
    testWidgets(
        'dashboard cards share alignment and compact typography at $width',
        (t) async {
      await t.binding.setSurfaceSize(Size(width, 1000));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(MaterialApp(
          theme: AppTheme.light,
          home: MediaQuery(
              data: MediaQueryData(
                  size: Size(width, 1000),
                  textScaler: const TextScaler.linear(1.6)),
              child: Scaffold(
                  body: SingleChildScrollView(
                      child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(children: [
                            const OwnerMetricGrid(children: [
                              OwnerMetricCard(
                                  label: 'Listings',
                                  value: '50',
                                  icon: Icons.inventory_2_outlined),
                              OwnerMetricCard(
                                  label: 'Rentals',
                                  value: '20',
                                  icon: Icons.event),
                            ]),
                            const SizedBox(height: 12),
                            OwnerAttentionCards(
                                pending: 3,
                                overdue: 2,
                                onRequests: () {},
                                onOverdue: () {}),
                          ])))))));
      expect(t.getTopLeft(find.text('Listings')).dx,
          t.getTopLeft(find.text('Awaiting approval')).dx);
      expect(t.takeException(), isNull);
    });
    testWidgets(
        'case shows separate carousel records and latest return at $width',
        (t) async {
      await t.binding.setSurfaceSize(Size(width, 1200));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final c = LiveRentHubController(fixture.CaseApi())
        ..profile = fixture.renter
        ..disputes = [fixture.caseRecord];
      addTearDown(c.dispose);
      final old = Rental.fromJson(
          {...fixture.rentalRow('disputed'), 'returnAllowed': true});
      c.renterWorkspace.rentals = [
        Rental.fromJson({
          ...fixture.rentalRow('disputed'),
          'returnAllowed': false,
          'returnSubmission': {
            'condition': 'Fair',
            'notes': 'Returned with all accessories.',
            'recordedAt': '2026-11-15T10:00:00Z',
            'evidence': ['upload://RETURN-1', 'upload://RETURN-2']
          }
        })
      ];
      await t.pumpWidget(fixture.host(
          LiveDisputePage(rental: old, owner: false),
          controller: c,
          scale: 1.6));
      await t.pumpAndSettle();
      expect(find.text('Case details'), findsNothing);
      await t.scrollUntilVisible(find.text('Condition photos'), 150,
          scrollable: find.byType(Scrollable).first);
      await t.scrollUntilVisible(find.text('Return'), 100,
          scrollable: find.byType(Scrollable).first);
      await t.pumpAndSettle();
      expect(find.text('Fair'), findsOneWidget);
      expect(find.text('Submit return'), findsNothing);
      expect(find.byType(ListingPhotoCarousel), findsWidgets);
      expect(t.takeException(), isNull);
    });
  }
}

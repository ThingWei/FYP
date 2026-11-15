import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:renthub_flutter/core/network/api_client.dart';
import 'package:renthub_flutter/core/theme/app_theme.dart';
import 'package:renthub_flutter/core/validation/input_validation.dart';
import 'package:renthub_flutter/features/live/live_contact_profile.dart';
import 'package:renthub_flutter/features/live/live_listing_gallery.dart';
import 'package:renthub_flutter/features/live/live_listing_photo_viewer.dart';
import 'package:renthub_flutter/features/live/live_product_details.dart';
import 'package:renthub_flutter/features/live/live_renter_shell.dart';
import 'package:renthub_flutter/features/live/live_renthub_controller.dart';
import 'package:renthub_flutter/features/live/live_subject_reviews.dart';
import 'package:renthub_flutter/features/live/live_value_pickers.dart';
import 'package:renthub_flutter/features/live/live_trust_page.dart';
import 'package:renthub_flutter/features/live/live_booking_locations.dart';
import 'package:renthub_flutter/features/live/user_record_pagination.dart';
import 'package:renthub_flutter/shared/models/domain_models.dart';
import 'live_photo_preview_test.dart' as photos;
import 'precise_location_test.dart' as location;
import 'booking_case_usability_test.dart' as booking;
import 'package:renthub_flutter/features/live/live_owner_shell.dart';
import 'package:renthub_flutter/features/live/live_location_field.dart';
import 'package:renthub_flutter/features/live/live_location_picker.dart';
import 'package:renthub_flutter/features/live/live_dispute_page.dart';

const user = User(
    id: 'viewer',
    email: 'viewer@example.test',
    name: 'Viewer',
    roles: {UserRole.renter},
    verificationStatus: 'approved');
const item = Listing(
    id: 'item',
    title: 'Camera',
    category: 'Devices',
    subcategory: 'Cameras',
    dailyPrice: 40,
    brand: 'Canon',
    productModel: 'EOS R50',
    variant: 'Black',
    packageType: 'body_only',
    itemAgeYears: 1,
    ownerId: 'owner',
    ownerName: 'Alice',
    location: 'George Town, Penang',
    latitude: 5.4,
    longitude: 100.3,
    locationPrecision: 'approximate');
Map<String, dynamic> roleScore(int score) => {
      'recorded': {
        'status': 'established',
        'score': score,
        'completedRentals': 5,
        'distinctPartners': 3
      }
    };
Map<String, dynamic> trust() => {
      'version': 'renthub-trust-v1',
      'policyVersion': 'recorded-rentals-v3',
      'overall': roleScore(73),
      'owner': roleScore(69),
      'renter': roleScore(81)
    };

class PolishApi extends photos.PhotoApi {
  Completer<Uint8List>? pendingPhoto;
  @override
  Future<Uint8List> downloadBytes(String path) =>
      pendingPhoto?.future ?? super.downloadBytes(path);
  @override
  Future<dynamic> request(String method, String path, {Object? body}) async {
    if (path.endsWith('/availability')) return {'unavailableRanges': []};
    if (path == '/users/owner/profile') {
      return {
        'id': 'owner',
        'displayName': 'Alice',
        'roles': ['owner', 'renter'],
        'trustProfile': trust()
      };
    }
    if (path == '/users/owner/trust') return trust();
    if (path == '/maps/config') return {'enabled': false};
    if (path.startsWith('/reviews/subjects/')) {
      return ApiItems([], {'page': 1, 'limit': 20, 'total': 0});
    }
    return <dynamic>[];
  }
}

Widget host(LiveRentHubController c, Widget child, {double scale = 1}) =>
    ChangeNotifierProvider.value(
        value: c,
        child: MaterialApp(
            theme: AppTheme.light,
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!),
            home: child));

void main() {
  testWidgets(
      'profile labels separate Owner/Renter scores rather than comparing an overall score',
      (t) async {
    final c = LiveRentHubController(PolishApi())..profile = user;
    addTearDown(c.dispose);
    await t.pumpWidget(host(c, const LiveContactProfilePage(userId: 'owner')));
    await t.pumpAndSettle();
    expect(find.text('Owner trust score: 69%'), findsOneWidget);
    expect(find.text('Renter trust score: 81%'), findsOneWidget);
    expect(find.textContaining('73%'), findsNothing);
    final owner =
        find.widgetWithText(TrustSummaryButton, 'Owner trust score: 69%');
    await t.tap(owner);
    await t.pumpAndSettle();
    expect(t.widget<LiveTrustPage>(find.byType(LiveTrustPage)).role, 'owner');
    expect(find.text('69%'), findsWidgets);
    expect(t.takeException(), isNull);
  });

  test(
      'received reviews describe the author role without relabelling the subject',
      () {
    expect(
        reviewAuthorLabel(const Review('R', 5, 'Careful renter',
            authorName: 'Alice', authorRole: 'owner', subjectRole: 'renter')),
        'Alice \u00b7 Owner');
    expect(
        reviewAuthorLabel(const Review('R', 5, 'Good Owner',
            authorName: 'Bob', authorRole: 'renter', subjectRole: 'owner')),
        'Bob \u00b7 Renter');
    expect(
        reviewAuthorLabel(const Review('R', 5, 'Historical',
            authorName: 'Charlie', subjectRole: 'renter')),
        'Charlie');
  });

  testWidgets(
      'location name opens approximate map, trust and long pickup sentence are absent',
      (t) async {
    final c = LiveRentHubController(PolishApi())..profile = user;
    addTearDown(c.dispose);
    await t.pumpWidget(
        host(c, LiveBookingPage(listing: item, onSubmitted: () {})));
    await t.pumpAndSettle();
    expect(find.byType(TrustSummaryButton), findsNothing);
    expect(find.text('View approximate area'), findsNothing);
    expect(find.textContaining('exact pickup point shared'), findsNothing);
    await t.tap(find.widgetWithText(TextButton, 'George Town, Penang'));
    await t.pumpAndSettle();
    final map = t.widget<LiveLocationView>(find.byType(LiveLocationView));
    expect(map.approximate, isTrue);
    expect(map.location.point.latitude, 5.4);
    expect(t.takeException(), isNull);
  });

  testWidgets(
      'full photo gallery starts on selected image, swipes, zooms and closes without losing the draft',
      (t) async {
    final c = LiveRentHubController(PolishApi())..profile = user;
    addTearDown(c.dispose);
    final draft = TextEditingController(text: 'Keep this draft');
    addTearDown(draft.dispose);
    await t.pumpWidget(host(
        c,
        Scaffold(
            body: ListView(children: [
          const ListingPhotoCarousel(photos: [
            'https://example.test/a',
            'https://example.test/b',
            'https://example.test/c'
          ], title: 'Camera'),
          TextField(controller: draft),
        ]))));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('Next photo'));
    await t.pumpAndSettle();
    await t.tap(find.bySemanticsLabel('Preview Camera, photo 2'));
    await t.pumpAndSettle();
    expect(find.byType(ListingPhotoViewer), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
    expect(find.text('2 / 3'), findsOneWidget);
    final scaffold = t.widget<Scaffold>(find.descendant(
        of: find.byType(ListingPhotoViewer), matching: find.byType(Scaffold)));
    expect(scaffold.backgroundColor, Colors.black);
    final pager = find.descendant(
        of: find.byType(ListingPhotoViewer), matching: find.byType(PageView));
    await t.drag(pager, const Offset(-450, 0));
    await t.pumpAndSettle();
    expect(find.text('3 / 3'), findsOneWidget);
    final image = find.byType(InteractiveViewer).hitTestable().first;
    final centre = t.getCenter(image);
    final first = await t.createGesture(pointer: 1),
        second = await t.createGesture(pointer: 2);
    await first.down(centre - const Offset(25, 0));
    await second.down(centre + const Offset(25, 0));
    await t.pump();
    await first.moveTo(centre - const Offset(100, 0));
    await second.moveTo(centre + const Offset(100, 0));
    await t.pump();
    await first.up();
    await second.up();
    await t.pumpAndSettle();
    expect(
        t
            .widget<InteractiveViewer>(image)
            .transformationController!
            .value
            .getMaxScaleOnAxis(),
        greaterThan(1));
    expect(
        t.widget<PageView>(pager).physics, isA<NeverScrollableScrollPhysics>());
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    expect(find.byType(ListingPhotoViewer), findsNothing);
    expect(draft.text, 'Keep this draft');
    expect(find.text('2 / 3'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets(
      'gallery retries failures and removes private photos on account change',
      (t) async {
    final api = PolishApi()..failures = 1;
    final c = LiveRentHubController(api)..profile = user;
    addTearDown(c.dispose);
    await t.pumpWidget(host(
        c,
        const ListingPhotoViewer(
            photos: ['https://example.test/a'], title: 'Camera')));
    await t.pumpAndSettle();
    expect(find.text('Photo unavailable'), findsOneWidget);
    await t.tap(find.text('Retry'));
    await t.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);
    c.profile = const User(
        id: 'other',
        name: 'Other',
        email: 'other@example.test',
        roles: {UserRole.renter});
    c.notifyListeners();
    await t.pumpAndSettle();
    expect(find.byType(Image), findsNothing);
    expect(find.textContaining('Your session changed'), findsOneWidget);
  });

  testWidgets('late photo data cannot reappear after account switching',
      (t) async {
    final api = PolishApi()..pendingPhoto = Completer<Uint8List>();
    final c = LiveRentHubController(api)..profile = user;
    addTearDown(c.dispose);
    await t.pumpWidget(host(
        c,
        const ListingPhotoViewer(
            photos: ['https://example.test/private'], title: 'Camera')));
    await t.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    c.profile = null;
    c.notifyListeners();
    api.pendingPhoto!.complete(photos.photo);
    await t.pumpAndSettle();
    expect(find.byType(Image), findsNothing);
    expect(find.textContaining('Your session changed'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets(
      'case heading names the initiating participant and avoids duplicate category text',
      (t) async {
    final c = LiveRentHubController(booking.CaseApi())
      ..profile = booking.owner
      ..disputes = [
        const Dispute('CASE', 'awaiting_response', 'Late return',
            rentalId: 'RNT',
            raisedByName: 'Alice',
            category: 'late_return',
            description: 'Please arrange the return.')
      ];
    addTearDown(c.dispose);
    await t.pumpWidget(host(c,
        const LiveDisputePage(rental: Rental('RNT', 'disputed'), owner: true)));
    await t.pumpAndSettle();
    expect(find.text('Alice: Late return'), findsOneWidget);
    expect(find.text('Late return'), findsNothing);
  });

  for (final width in [360.0, 390.0, 1024.0, 1440.0]) {
    testWidgets('service location controls have separate spacing at $width',
        (t) async {
      await t.binding.setSurfaceSize(Size(width, 1100));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final c = LiveRentHubController(PolishApi())..profile = user;
      addTearDown(c.dispose);
      await t.pumpWidget(
          host(c, const LiveListingForm(isService: true), scale: 1.6));
      await t.pumpAndSettle();
      final venue = find.widgetWithText(
          DropdownButtonFormField<String>, 'Service location type');
      await t.scrollUntilVisible(venue, 350,
          maxScrolls: 60, scrollable: find.byType(Scrollable).first);
      final field = find.descendant(
          of: find.byType(LiveLocationField),
          matching: find.byType(TextFormField));
      await t.ensureVisible(field);
      await t.pumpAndSettle();
      expect(t.getRect(field).top - t.getRect(venue).bottom,
          greaterThanOrEqualTo(20));
      final choose = find.widgetWithText(OutlinedButton, 'Choose location');
      await t.ensureVisible(choose);
      await t.pumpAndSettle();
      expect(t.getRect(choose).top - t.getRect(field).bottom,
          greaterThanOrEqualTo(16));
      final duration = find.widgetWithText(TextFormField, 'Service duration');
      await t.ensureVisible(duration);
      await t.pumpAndSettle();
      expect(t.getRect(duration).top - t.getRect(choose).bottom,
          greaterThanOrEqualTo(20));
      expect(t.takeException(), isNull);
    });

    testWidgets(
        'map controls have gaps without routine pin/GPS commentary at $width',
        (t) async {
      await t.binding.setSurfaceSize(Size(width, 1100));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(MaterialApp(
          theme: AppTheme.light,
          home: LiveLocationPicker(
              api: ListingLocationApi(location.LocationApi()),
              positionClient: location.Gps(),
              mapBuilder: location.canvas)));
      await t.pumpAndSettle();
      final search = find.widgetWithText(FilledButton, 'Search');
      final gps =
          find.widgetWithText(OutlinedButton, 'Use my current location');
      expect(t.getRect(gps).top - t.getRect(search).bottom,
          greaterThanOrEqualTo(20));
      expect(find.textContaining('Search or use GPS'), findsNothing);
      expect(find.textContaining('Selected pin:'), findsNothing);
      expect(find.textContaining('Keep unit/house details'), findsNothing);
      final city = find.widgetWithText(TextField, 'City / town');
      final state = find.widgetWithText(TextField, 'State');
      final postcode = find.widgetWithText(TextField, 'Postcode (if known)');
      await t.scrollUntilVisible(postcode, 250,
          maxScrolls: 30, scrollable: find.byType(Scrollable).first);
      expect(t.getRect(state).top - t.getRect(city).bottom,
          greaterThanOrEqualTo(16));
      expect(t.getRect(postcode).top - t.getRect(state).bottom,
          greaterThanOrEqualTo(16));
      expect(t.takeException(), isNull);
    });

    testWidgets('saved facts and missing age display honestly at $width',
        (t) async {
      await t.binding.setSurfaceSize(Size(width, 1000));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(MaterialApp(
          theme: AppTheme.light,
          home: MediaQuery(
              data: MediaQueryData(
                  size: Size(width, 1000),
                  textScaler: const TextScaler.linear(1.6)),
              child: const Scaffold(
                  body: SingleChildScrollView(
                      child: ListingProductDetails(listing: item))))));
      expect(find.text('1 year'), findsOneWidget);
      expect(find.text('Body only'), findsOneWidget);
      expect(find.text('Black'), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.pumpWidget(MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
              body: ListingProductDetails(
                  listing: Listing.fromJson({
            'publicId': 'legacy',
            'title': 'Unknown age',
            'category': 'Devices',
            'dailyPrice': 20
          })))));
      expect(find.text('Item age'), findsNothing);
    });
    for (final duration in [true, false]) {
      testWidgets(
          'preset chips remain one swipe row without movement at $width duration=$duration',
          (t) async {
        await t.binding.setSurfaceSize(Size(width, 1000));
        addTearDown(() => t.binding.setSurfaceSize(null));
        final value = TextEditingController(text: duration ? '60' : '5.00');
        addTearDown(value.dispose);
        await t.pumpWidget(MaterialApp(
            theme: AppTheme.light,
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: const TextScaler.linear(1.6)),
                child: child!),
            home: Scaffold(
                body: ListingValuePicker(
                    controller: value,
                    label: duration ? 'Service duration' : 'Deposit',
                    rule:
                        InputRule('Value', kind: InputKind.money, max: 100000),
                    duration: duration))));
        await t.tap(find.byType(TextFormField));
        await t.pumpAndSettle();
        final chips = find.byType(ChoiceChip);
        final original = t.getTopLeft(chips.first),
            next = t.getTopLeft(chips.at(1));
        await t.tap(chips.first);
        await t.pumpAndSettle();
        expect(t.getTopLeft(chips.first), original);
        expect(t.getTopLeft(chips.at(1)), next);
        final strip = find.byKey(const ValueKey('value-preset-strip'));
        expect(t.widget<SingleChildScrollView>(strip).scrollDirection,
            Axis.horizontal);
        final last =
            find.widgetWithText(ChoiceChip, duration ? '1d' : 'RM 500');
        await t.drag(strip, const Offset(-1800, 0),
            kind: PointerDeviceKind.mouse);
        await t.pumpAndSettle();
        await t.ensureVisible(last);
        await t.tap(last);
        await t.pumpAndSettle();
        expect(t.widget<ChoiceChip>(last).selected, isTrue);
        expect(t.takeException(), isNull);
      });
    }
  }
  testWidgets('pagination is transparent and reserves its own space',
      (t) async {
    final c = LiveRentHubController(PolishApi())..profile = user;
    addTearDown(c.dispose);
    c.userRecordPages['reviews'] = UserRecordPage()
      ..loaded = true
      ..total = 40;
    await t.pumpWidget(host(
        c,
        const Scaffold(
            body: SizedBox.expand(key: ValueKey('records-body')),
            bottomNavigationBar: UserRecordPagination(collection: 'reviews'))));
    await t.pumpAndSettle();
    final footer = find.byType(UserRecordPagination);
    final material = t.widget<Material>(
        find.descendant(of: footer, matching: find.byType(Material)).first);
    expect(material.type, MaterialType.transparency);
    expect(t.getRect(find.byKey(const ValueKey('records-body'))).bottom,
        lessThanOrEqualTo(t.getRect(footer).top));
  });
}

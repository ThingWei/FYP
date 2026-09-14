import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:renthub_flutter/core/constants/renthub_categories.dart';
import 'package:renthub_flutter/core/theme/app_theme.dart';
import 'package:renthub_flutter/features/admin/admin_app.dart';
import 'package:renthub_flutter/features/owner/owner_app.dart';
import 'package:renthub_flutter/features/renter/comparison/controllers/compare_selection_controller.dart';
import 'package:renthub_flutter/features/renter/comparison/pages/compare_items_page.dart';
import 'package:renthub_flutter/features/renter/discovery/controllers/renter_prototype_state.dart';
import 'package:renthub_flutter/features/renter/discovery/pages/wishlist_page.dart';
import 'package:renthub_flutter/features/renter/renter_app.dart';
import 'package:renthub_flutter/features/renter/services/models/service_draft.dart';
import 'package:renthub_flutter/features/renter/services/pages/service_booking_details_page.dart';
import 'package:renthub_flutter/features/renter/services/pages/service_search_results_page.dart';
import 'package:renthub_flutter/modules/booking/controllers/booking_controller.dart';
import 'package:renthub_flutter/modules/booking/repositories/booking_repository.dart';
import 'package:renthub_flutter/modules/user/controllers/auth_controller.dart';
import 'package:renthub_flutter/modules/user/repositories/auth_repository.dart';
import 'package:renthub_flutter/shared/mock_data/mock_data.dart';
import 'package:renthub_flutter/shared/models/domain_models.dart';
import 'package:renthub_flutter/shared/widgets/account_components.dart';

class _CountingBookingRepository implements BookingRepository {
  int calls = 0;

  @override
  Future<Booking> create(
    String listingId,
    DateTime start,
    DateTime end,
  ) async {
    calls++;
    await Future<void>.delayed(const Duration(milliseconds: 20));
    return Booking(
      id: 'service-$calls',
      listingId: listingId,
      start: start,
      end: end,
      status: 'pending',
    );
  }
}

Widget _withMobileProviders(Widget child) {
  final auth = AuthController(MockAuthRepository())
    ..user = MockData.dual
    ..selectedRole = UserRole.renter;
  return MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: auth),
      ChangeNotifierProvider(
        create: (_) => BookingController(MockBookingRepository()),
      ),
    ],
    child: MaterialApp(theme: AppTheme.light, home: child),
  );
}

void main() {
  test('canonical categories and mock listings use the protected taxonomy', () {
    expect(RentHubCategories.values, const [
      'Clothing',
      'Vehicles',
      'Services',
      'Devices',
      'Books',
      'Equipment',
    ]);
    expect(
      MockData.listings.every(
        (listing) => RentHubCategories.values.contains(listing.category),
      ),
      isTrue,
    );
    expect(MockData.listings.any((listing) => listing.category == 'Fashion'),
        isFalse);
  });

  test('service submission is idempotent and remains Pending', () async {
    final repository = _CountingBookingRepository();
    final controller = BookingController(repository);
    final service =
        MockData.listings.firstWhere((listing) => listing.isService);
    final draft = ServiceDraft(service);

    final results = await Future.wait([
      draft.submit(controller),
      draft.submit(controller),
      draft.submit(controller),
    ]);

    expect(repository.calls, 1);
    expect(results.map((booking) => booking?.id).toSet(), {'service-1'});
    expect(draft.createdBooking?.status, 'pending');
  });

  test('comparison selection enforces category and three-item maximum', () {
    const first = Listing(
      id: 'one',
      title: 'One',
      category: RentHubCategories.devices,
      dailyPrice: 10,
    );
    const second = Listing(
      id: 'two',
      title: 'Two',
      category: RentHubCategories.devices,
      dailyPrice: 20,
    );
    const third = Listing(
      id: 'three',
      title: 'Three',
      category: RentHubCategories.devices,
      dailyPrice: 30,
    );
    const fourth = Listing(
      id: 'four',
      title: 'Four',
      category: RentHubCategories.devices,
      dailyPrice: 40,
    );
    const vehicle = Listing(
      id: 'vehicle',
      title: 'Vehicle',
      category: RentHubCategories.vehicles,
      dailyPrice: 50,
    );
    final selection = ComparisonSelectionController();

    expect(selection.toggle(first), isNull);
    expect(selection.toggle(vehicle), contains('same category'));
    expect(selection.toggle(second), isNull);
    expect(selection.toggle(third), isNull);
    expect(selection.toggle(fourth), contains('up to 3'));
    expect(selection.selectedIds, {'one', 'two', 'three'});
    selection.dispose();
  });

  testWidgets('Explore comparison route preserves selected IDs on back',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _withMobileProviders(
        ExplorePage(
          onOpenBookings: _noop,
          onReturnHome: _noop,
          onDraftCreated: (_) {},
        ),
      ),
    );
    final state = tester.state<ExplorePageState>(find.byType(ExplorePage));
    state.availableOnly = false;
    state.category = RentHubCategories.equipment;
    state.applyQuery('');
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('explore-compare-mode')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('explore-compare-l-tent')), findsOneWidget);
    expect(find.byKey(const Key('explore-compare-l-drill')), findsOneWidget);
    expect(
      tester
          .widget<RentHubActionButton>(
            find.byKey(const Key('explore-compare-selected')),
          )
          .onPressed,
      isNull,
    );

    await tester.tap(find.byKey(const Key('explore-compare-l-tent')));
    await tester.tap(find.byKey(const Key('explore-compare-l-drill')));
    await tester.pumpAndSettle();
    expect(find.text('2 of 3 selected'), findsOneWidget);
    await tester.tap(find.byKey(const Key('explore-compare-selected')));
    await tester.pumpAndSettle();

    expect(find.byType(CompareItemsPage), findsOneWidget);
    expect(find.text('Four-person Camping Tent'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Makita Cordless Drill Set'),
      300,
    );
    expect(find.text('Makita Cordless Drill Set'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('2 of 3 selected'), findsOneWidget);
    expect(
      tester
          .widget<Checkbox>(
            find.byKey(const Key('explore-compare-l-tent')),
          )
          .value,
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Wishlist uses the same comparison selection flow',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final previousWishlist = {...RenterPrototypeState.wishlist.value};
    RenterPrototypeState.wishlist.value = {'l-tent', 'l-drill', 'l-camera'};
    addTearDown(() => RenterPrototypeState.wishlist.value = previousWishlist);

    await tester.pumpWidget(
      _withMobileProviders(WishlistPage(onOpenListing: (_) {})),
    );
    await tester.tap(find.byKey(const Key('wishlist-compare-mode')));
    await tester.pumpAndSettle();
    expect(find.byType(Checkbox), findsNWidgets(3));
    await tester.tap(find.byKey(const Key('wishlist-compare-l-tent')));
    await tester.tap(find.byKey(const Key('wishlist-compare-l-camera')));
    await tester.pumpAndSettle();
    expect(
        find.text('Choose listings from the same category.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('wishlist-compare-l-drill')));
    await tester.pumpAndSettle();
    expect(find.text('2 of 3 selected'), findsOneWidget);
    await tester.tap(find.byKey(const Key('wishlist-compare-selected')));
    await tester.pumpAndSettle();
    expect(find.byType(CompareItemsPage), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('2 of 3 selected'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('comparison controls fit both mobile target widths',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final previousWishlist = {...RenterPrototypeState.wishlist.value};
    RenterPrototypeState.wishlist.value = {'l-tent', 'l-drill', 'l-camera'};
    addTearDown(() => RenterPrototypeState.wishlist.value = previousWishlist);

    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpWidget(
      _withMobileProviders(
        ExplorePage(
          onOpenBookings: _noop,
          onReturnHome: _noop,
          onDraftCreated: (_) {},
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('explore-compare-mode')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    tester.view.physicalSize = const Size(360, 800);
    await tester.pumpWidget(
      _withMobileProviders(WishlistPage(onOpenListing: (_) {})),
    );
    await tester.tap(find.byKey(const Key('wishlist-compare-mode')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('Services category opens the separate service journey',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _withMobileProviders(
        const RenterShell(onSwitchRole: _noop, canSwitch: true),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Services').first);
    await tester.pumpAndSettle();

    expect(find.byType(ServiceResultsPage), findsOneWidget);
    await tester.tap(find.text('Tutoring'));
    await tester.pumpAndSettle();
    expect(find.text('SPM Mathematics Tutoring'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renter and owner shells render as mobile interfaces at 390x844',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _withMobileProviders(
        const RenterShell(onSwitchRole: _noop, canSwitch: true),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(
      _withMobileProviders(
        const OwnerShell(onSwitchRole: _noop, canSwitch: true),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('high-risk Batch 3 mobile pages fit at 360x800', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final service =
        MockData.listings.firstWhere((listing) => listing.isService);

    for (final page in <Widget>[
      ServiceBookingPage(
        draft: ServiceDraft(service),
        onOpenBookings: _noop,
        onReturnHome: _noop,
      ),
      const OwnerActiveRentalsPage(),
      const ListingForm(isService: false),
    ]) {
      await tester.pumpWidget(_withMobileProviders(page));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('admin shell fits one desktop and one tablet viewport',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    for (final size in const [Size(1440, 900), Size(800, 1024)]) {
      tester.view.physicalSize = size;
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.light, home: const AdminShell()),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
  });
}

void _noop() {}

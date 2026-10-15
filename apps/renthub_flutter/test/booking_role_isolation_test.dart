import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:renthub_flutter/core/network/api_client.dart';
import 'package:renthub_flutter/core/theme/app_theme.dart';
import 'package:renthub_flutter/features/live/live_owner_shell.dart';
import 'package:renthub_flutter/features/live/live_renter_shell.dart';
import 'package:renthub_flutter/features/live/live_renthub_controller.dart';
import 'package:renthub_flutter/shared/models/domain_models.dart';

User account({String id = 'dual', UserRole role = UserRole.renter}) => User(
    id: id,
    email: '$id@example.invalid',
    name: 'Dual role user',
    roles: const {UserRole.renter, UserRole.owner},
    activeRole: role);

Map<String, dynamic> row(String id,
        {String renter = 'dual', String owner = 'supplier'}) =>
    {
      'publicId': id,
      'listingId': 'listing-$id',
      'listingTitle': '$id camera',
      'listingType': 'physical',
      'renterId': renter,
      'ownerId': owner,
      'renterName': 'Test Renter',
      'ownerName': 'Test Owner',
      'startDate': '2027-01-20',
      'endDate': '2027-01-21',
      'status': 'pending',
      'paymentStatus': 'authorized',
      'total': 100,
    };

Map<String, dynamic> rentalRow(String id, String booking,
        {String renter = 'dual', String owner = 'supplier'}) =>
    {
      'publicId': id,
      'bookingId': booking,
      'renterId': renter,
      'ownerId': owner,
      'status': 'active',
      'listingType': 'physical',
    };

class RoleApi extends ApiClient {
  RoleApi() : super('https://example.invalid');
  User user = account();
  List<dynamic> outgoing = [row('OUT')];
  List<dynamic> incoming = [row('IN', renter: 'customer', owner: 'dual')];
  final details = <String, dynamic>{
    'OUT': row('OUT'),
    'IN': row('IN', renter: 'customer', owner: 'dual'),
  };
  final waits = <String, List<Completer<dynamic>>>{};
  final errors = <String, Object>{};
  final calls = <(String, String)>[];

  Completer<dynamic> delay(String path) {
    final result = Completer<dynamic>();
    (waits[path] ??= []).add(result);
    return result;
  }

  @override
  Future<dynamic> request(String method, String path, {Object? body}) async {
    calls.add((method, path));
    if (waits[path]?.isNotEmpty ?? false) {
      return waits[path]!.removeAt(0).future;
    }
    if (errors.containsKey(path)) throw errors[path]!;
    if (path == '/users/me') {
      return {
        'authId': user.id,
        'displayName': user.name,
        'roles': ['renter', 'owner'],
        'activeRole': user.activeRole?.name
      };
    }
    if (path == '/bookings/mine') return outgoing;
    if (path == '/bookings/owner') return incoming;
    if (path == '/rentals/mine') return [rentalRow('R-OUT', 'OUT')];
    if (path == '/rentals/owner') {
      return [rentalRow('R-IN', 'IN', renter: 'customer', owner: 'dual')];
    }
    if (path == '/rewards/summary') return <String, dynamic>{};
    if (path == '/bookings' && method == 'POST') return details['OUT'];
    if (path == '/bookings/OUT/cancel') {
      return <String, dynamic>{
        ...details['OUT'] as Map<String, dynamic>,
        'status': 'cancelled'
      };
    }
    if (path == '/bookings/IN/decision') {
      incoming = [
        <String, dynamic>{
          ...details['IN'] as Map<String, dynamic>,
          'status': (body as Map)['status']
        }
      ];
      return incoming.first;
    }
    if (path.startsWith('/bookings/')) return details[path.split('/').last];
    if (path == '/rentals/R-OUT') return rentalRow('R-OUT', 'OUT');
    if (path == '/rentals/R-IN') {
      return rentalRow('R-IN', 'IN', renter: 'customer', owner: 'dual');
    }
    return <dynamic>[];
  }
}

void main() {
  late RoleApi api;
  late LiveRentHubController controller;
  setUp(() {
    api = RoleApi();
    controller = LiveRentHubController(api, socketUrl: 'http://127.0.0.1:1')
      ..syncSession(api.user);
  });
  tearDown(() => controller.dispose());

  test('role loads keep separate outgoing/incoming bookings and rentals',
      () async {
    await controller.loadRenter();
    api.user = account(role: UserRole.owner);
    controller.syncSession(api.user);
    await controller.loadOwner();
    expect(controller.renterBookings.map((b) => b.id), ['OUT']);
    expect(controller.ownerBookings.map((b) => b.id), ['IN']);
    expect(controller.renterRentals.map((b) => b.id), ['R-OUT']);
    expect(controller.ownerRentals.map((b) => b.id), ['R-IN']);
    controller.syncSession(account());
    expect(controller.renterBookings.single.id, 'OUT');
    expect(controller.ownerBookings.single.id, 'IN');
  });

  test('late renter load cannot overwrite Owner workspace or current profile',
      () async {
    final delayed = api.delay('/bookings/mine');
    final renterLoad = controller.loadRenter();
    api.user = account(role: UserRole.owner);
    controller.syncSession(api.user);
    await controller.loadOwner();
    delayed.complete(api.outgoing);
    await renterLoad;
    expect(controller.profile!.activeRole, UserRole.owner);
    expect(controller.ownerBookings.single.id, 'IN');
    expect(controller.renterBookings, isEmpty);
    expect(controller.renterWorkspace.loading, isFalse);
    expect(controller.ownerWorkspace.loaded, isTrue);
  });

  test('newest same-role request wins, including loading state', () async {
    final old = api.delay('/bookings/owner');
    final recent = api.delay('/bookings/owner');
    final first = controller.loadOwner();
    final second = controller.loadOwner();
    recent.complete(api.incoming);
    await second;
    old.complete([row('OLD', renter: 'customer', owner: 'dual')]);
    await first;
    expect(controller.ownerBookings.single.id, 'IN');
    expect(controller.ownerWorkspace.loading, isFalse);
  });

  test(
      'failed Owner load never displays renter data, keeps separate errors and cache',
      () async {
    await controller.loadRenter();
    api.errors['/bookings/owner'] = ApiException(503, 'private failure');
    await expectLater(controller.loadOwner(), throwsA(isA<ApiException>()));
    expect(controller.ownerBookings, isEmpty);
    expect(controller.ownerWorkspace.error, isA<ApiException>());
    expect(controller.renterWorkspace.error, isNull);
    expect(controller.renterBookings.single.id, 'OUT');
    api.errors.clear();
    await controller.loadOwner();
    api.errors['/bookings/owner'] = ApiException(503, 'private failure');
    await expectLater(controller.loadOwner(), throwsA(isA<ApiException>()));
    expect(controller.ownerBookings.single.id, 'IN');
    expect(controller.ownerWorkspace.loading, isFalse);
  });

  test(
      'logout/account replacement discards delayed loads and focused responses, even after returning',
      () async {
    await controller.getBooking('OUT');
    final focused = api.delay('/bookings/OUT');
    final read = controller.refreshFocusedBooking('OUT', 'R-OUT');
    controller.syncSession(null);
    controller.syncSession(account(id: 'other'));
    expect(controller.bookings, isEmpty);
    expect(controller.rentals, isEmpty);
    controller.syncSession(account());
    focused.complete(row('OUT'));
    await read;
    expect(controller.bookings, isEmpty);
    expect(controller.rentals, isEmpty);

    final delayed = api.delay('/bookings/owner');
    final load = controller.loadOwner();
    controller.syncSession(null);
    delayed.complete(api.incoming);
    await load;
    expect(controller.ownerBookings, isEmpty);
    expect(controller.ownerWorkspace.loaded, isFalse);
  });

  test(
      'notification hydration partitions by actual ownership without switching roles',
      () async {
    await controller.refreshFocusedBooking('OUT', 'R-OUT');
    expect(controller.ownerBookings, isEmpty);
    expect(controller.ownerRentals, isEmpty);
    await controller.refreshFocusedBooking('IN', 'R-IN');
    expect(controller.renterBookings.single.id, 'OUT');
    expect(controller.ownerBookings.single.id, 'IN');
    expect(controller.profile!.activeRole, UserRole.renter);
  });

  test(
      'local approval/rejection and Owner rental guards perform no foreign writes',
      () async {
    await controller.getBooking('OUT');
    for (final status in ['approved', 'rejected']) {
      await expectLater(
          controller.decideBooking('OUT', status, reason: 'Not my listing'),
          throwsA(isA<ApiException>()));
    }
    await expectLater(
        controller.runRentalAction(
            Rental.fromJson(rentalRow('R-OUT', 'OUT')), 'handover',
            owner: true),
        throwsA(isA<ApiException>()));
    expect(api.calls.where((call) => call.$1 != 'GET'), isEmpty);
    await controller.getBooking('IN');
    await controller.decideBooking('IN', 'approved');
    expect(controller.ownerBookings.single.status, 'approved');
    expect(controller.renterBookings.single.status, 'pending');
  });

  test(
      'cancel/payment reads update renter only; administrator records stay separate',
      () async {
    await controller.getBooking('IN');
    await controller.getBooking('OUT');
    await controller.cancelBooking('OUT', 'Changed plans');
    expect(controller.renterBookings.single.status, 'cancelled');
    expect(controller.ownerBookings.single.status, 'pending');
    api.details['OUT'] = {...row('OUT'), 'paymentStatus': 'authorized'};
    await controller.getBooking('OUT');
    expect(controller.renterBookings.single.paymentStatus, 'authorized');
    controller.adminWorkspace.bookings = [
      Booking.fromJson(row('ADMIN', renter: 'someone', owner: 'another'))
    ];
    expect(controller.bookings.any((b) => b.id == 'ADMIN'), isFalse);
  });

  test('malformed self-booking and foreign records never gain Owner controls',
      () {
    controller.ownerWorkspace.bookings = [
      Booking.fromJson(row('SELF', owner: 'dual')),
      Booking.fromJson(row('OUT'))
    ];
    controller.ownerWorkspace.rentals = [
      Rental.fromJson(rentalRow('SELF', 'SELF', owner: 'dual'))
    ];
    expect(controller.ownerBookings, isEmpty);
    expect(controller.ownerRentals, isEmpty);
  });

  for (final width in [360.0, 390.0]) {
    testWidgets(
        'Owner/renter lists and controls stay isolated at $width with larger text',
        (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await controller.getBooking('OUT');
      await controller.getBooking('IN');
      Widget app(Widget page) => ChangeNotifierProvider.value(
          value: controller,
          child: MaterialApp(
              theme: AppTheme.light,
              builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: const TextScaler.linear(1.4)),
                  child: child!),
              home: page));
      await tester.pumpWidget(app(const LiveOwnerRequestsPage()));
      await tester.pumpAndSettle();
      expect(find.text('OUT camera'), findsNothing);
      expect(find.text('IN camera'), findsOneWidget);
      expect(find.text('Approve'), findsOneWidget);
      expect(find.text('Reject'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(app(const LiveRenterBookingsPage()));
      await tester.pumpAndSettle();
      expect(find.text('OUT camera'), findsOneWidget);
      expect(find.text('IN camera'), findsNothing);
      expect(find.text('Approve'), findsNothing);
      expect(find.text('Reject'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'failed Owner requests show retry rather than outgoing records or false empty state',
      (tester) async {
    await controller.getBooking('OUT');
    controller.ownerWorkspace.error = ApiException(503, 'private server path');
    await tester.pumpWidget(ChangeNotifierProvider.value(
        value: controller,
        child: MaterialApp(
            theme: AppTheme.light, home: const LiveOwnerRequestsPage())));
    await tester.pumpAndSettle();
    expect(find.text('Try again'), findsOneWidget);
    expect(find.text('No booking requests'), findsNothing);
    expect(find.text('OUT camera'), findsNothing);
    expect(find.textContaining('private server path'), findsNothing);
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('IN camera'), findsOneWidget);
    expect(controller.ownerWorkspace.error, isNull);
    controller.syncSession(null);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}

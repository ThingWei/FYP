import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:renthub_flutter/core/network/api_client.dart';
import 'package:renthub_flutter/core/network/user_facing_error.dart';
import 'package:renthub_flutter/core/theme/app_theme.dart';
import 'package:renthub_flutter/features/live/live_existing_booking_request.dart';
import 'package:renthub_flutter/features/live/live_renter_shell.dart';
import 'package:renthub_flutter/features/live/live_renthub_controller.dart';
import 'package:renthub_flutter/modules/user/controllers/auth_controller.dart';
import 'package:renthub_flutter/modules/user/repositories/auth_repository.dart';
import 'package:renthub_flutter/shared/models/domain_models.dart';

const existingId = 'RH-BKG-2026-EXISTING';
ApiException duplicate([Object? details = const {'bookingId': existingId}]) =>
    ApiException(409, 'private diagnostics',
        code: 'DUPLICATE_PENDING_BOOKING', details: details);

class DuplicateApi extends ApiClient {
  DuplicateApi(this.paid) : super('https://example.invalid');
  final bool paid;
  int creations = 0, payments = 0;
  final profile = <String, dynamic>{
    'authId': 'renter',
    'displayName': 'Test renter',
    'roles': ['renter'],
    'activeRole': 'renter',
    'verification': {'documentType': 'mykad', 'status': 'approved'}
  };
  @override
  Future<dynamic> request(String method, String path, {Object? body}) async {
    if (path == '/users/me') return profile;
    if (path.endsWith('/availability')) {
      return {'listingId': 'l-camera', 'unavailableRanges': []};
    }
    if (path.contains('/agreement-terms')) {
      return {
        'version': 'renthub-physical-v2',
        'title': 'Rental agreement',
        'sections': [
          {
            'title': 'Owner approval',
            'detail': 'Requests require Owner approval.'
          }
        ]
      };
    }
    if (path == '/bookings' && method == 'POST') {
      creations++;
      throw duplicate();
    }
    if (path.startsWith('/payments')) {
      payments++;
      throw StateError('Must not pay automatically');
    }
    if (path == '/bookings/$existingId') {
      return {
        'publicId': existingId,
        'listingId': 'l-camera',
        'listingTitle': 'Existing camera request',
        'listingType': 'physical',
        'renterId': 'renter',
        'ownerId': 'owner',
        'startDate': '2027-01-01',
        'endDate': '2027-01-03',
        'status': 'pending',
        'paymentStatus': paid ? 'authorized' : 'unpaid',
        'expiresAt': '2099-01-01T00:00:00Z',
        'total': 100,
      };
    }
    if (path.endsWith('/views')) return <String, dynamic>{};
    return <dynamic>[];
  }
}

Future<void> tapText(WidgetTester tester, String text) async {
  final target = find.text(text);
  for (int i = 0; target.evaluate().isEmpty && i < 35; i++) {
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -220));
    await tester.pumpAndSettle();
  }
  await tester.ensureVisible(target.last);
  await tester.pumpAndSettle();
  await tester.tap(target.last);
  await tester.pumpAndSettle();
}

void main() {
  test('only typed, validated duplicate targets can open a booking', () {
    expect(
        ExistingBookingRequest.fromError(duplicate())!.bookingId, existingId);
    for (final details in [
      null,
      <dynamic>[],
      {'bookingId': 'https://private.invalid'},
      {'bookingId': 123},
      {'bookingId': 'OTHER'}
    ]) {
      expect(ExistingBookingRequest.fromError(duplicate(details)), isNull);
    }
    expect(
        ExistingBookingRequest.fromError(ApiException(403, 'private',
            code: 'DUPLICATE_PENDING_BOOKING',
            details: {'bookingId': existingId})),
        isNull);
    expect(
        UserFacingError.from(duplicate()).message, isNot(contains('private')));
    expect(
        UserFacingError.from(ApiException(409, 'private',
                code: 'BOOKING_REQUEST_IN_PROGRESS'))
            .message,
        contains('Check Bookings'));
  });

  for (final width in [360.0, 390.0]) {
    testWidgets(
        'duplicate recovery retains draft and requires explicit navigation at $width',
        (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final draft =
          TextEditingController(text: 'Please collect at the entrance.');
      addTearDown(draft.dispose);
      String? opened;
      await tester.pumpWidget(MaterialApp(
          theme: AppTheme.light,
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(1.5)),
              child: child!),
          home: Scaffold(
              body: Builder(
                  builder: (context) => Column(children: [
                        TextField(controller: draft),
                        FilledButton(
                            onPressed: () => offerExistingBookingRequest(
                                    context, duplicate(), onOpen: (id) async {
                                  opened = id;
                                }),
                            child: const Text('Submit')),
                      ])))));
      await tester.tap(find.text('Submit'));
      await tester.pumpAndSettle();
      expect(opened, isNull);
      expect(find.text('You already have a request'), findsOneWidget);
      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      expect(draft.text, 'Please collect at the entrance.');
      await tester.tap(find.text('Submit'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('View existing request'));
      await tester.pumpAndSettle();
      expect(opened, existingId);
      expect(tester.takeException(), isNull);
    });
  }

  for (final paid in [false, true]) {
    testWidgets(
        'listing submission opens existing ${paid ? 'paid' : 'unpaid'} request without a second payment',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final api = DuplicateApi(paid);
      final user = User.fromJson(api.profile);
      final auth = AuthController(MockAuthRepository())..user = user;
      final controller = LiveRentHubController(api)..syncSession(user);
      addTearDown(auth.dispose);
      addTearDown(controller.dispose);
      await tester.pumpWidget(MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: auth),
            ChangeNotifierProvider.value(value: controller),
          ],
          child: MaterialApp(
              theme: AppTheme.light,
              home: LiveBookingPage(
                listing: const Listing(
                    id: 'l-camera',
                    title: 'Test camera',
                    category: 'Devices',
                    dailyPrice: 100,
                    fulfilmentMethods: ['pickup']),
                onSubmitted: () =>
                    fail('Duplicate must not report a newly submitted booking'),
              ))));
      await tester.pumpAndSettle();
      await tapText(tester, 'Review');
      await tapText(tester, 'I have reviewed these terms');
      await tapText(
          tester, 'I have reviewed and accept the RentHub booking agreement.');
      await tapText(tester, 'Continue to checkout');
      await tapText(tester, 'Continue');
      expect(find.text('You already have a request'), findsOneWidget);
      expect(api.creations, 1);
      expect(api.payments, 0);
      await tapText(tester, 'Keep editing');
      expect(find.text('Continue to checkout'), findsOneWidget);
      final button = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Continue to checkout'));
      expect(button.onPressed, isNotNull);
      await tapText(tester, 'Continue to checkout');
      await tapText(tester, 'Continue');
      await tapText(tester, 'View existing request');
      expect(find.text('Existing camera request'), findsOneWidget);
      expect(
          find.text('Continue payment'), paid ? findsNothing : findsOneWidget);
      expect(find.text('Awaiting Owner approval'),
          paid ? findsOneWidget : findsNothing);
      expect(controller.ownerBookings, isEmpty);
      expect(controller.renterBookings.single.id, existingId);
      expect(api.payments, 0);
      expect(tester.takeException(), isNull);
    });
  }
}

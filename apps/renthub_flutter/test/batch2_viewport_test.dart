import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:renthub_flutter/features/renter/booking/booking_flow.dart';
import 'package:renthub_flutter/features/renter/renter_app.dart';
import 'package:renthub_flutter/modules/booking/controllers/booking_controller.dart';
import 'package:renthub_flutter/modules/booking/repositories/booking_repository.dart';
import 'package:renthub_flutter/shared/mock_data/mock_data.dart';
import 'package:renthub_flutter/shared/models/domain_models.dart';

Widget _app(Widget child, BookingController booking) =>
    ChangeNotifierProvider.value(
      value: booking,
      child: MaterialApp(home: child),
    );

void main() {
  for (final size in [const Size(360, 800), const Size(390, 844)]) {
    testWidgets('all Batch 2 screens render at ${size.width}x${size.height}',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final camera =
          MockData.listings.firstWhere((item) => item.id == 'l-camera');
      final draft = BookingDraft(
        listing: camera,
        today: DateTime(2026, 8, 14),
      );
      draft.markAuthorized('sim-visual');
      draft.createdBooking = Booking(
        id: 'visual-pending',
        listingId: camera.id,
        start: draft.startDate!,
        end: draft.endDate!,
        status: 'pending',
      );
      final booking = BookingController(MockBookingRepository());
      await booking.create(camera.id, draft.startDate!, draft.endDate!);

      final screens = <Widget>[
        RenterHome(
          onExplore: (_) {},
          onOpenBookings: () {},
          onReturnHome: () {},
          onDraftCreated: (_) {},
        ),
        ExplorePage(
          onOpenBookings: () {},
          onReturnHome: () {},
          onDraftCreated: (_) {},
        ),
        ListingDetailsPage(
          listing: camera,
          onOpenBookings: () {},
          onReturnHome: () {},
          onDraftCreated: (_) {},
        ),
        BookingDetailsPage(
          draft: draft,
          onOpenBookings: () {},
          onReturnHome: () {},
        ),
        AgreementReviewPage(
          draft: draft,
          onOpenBookings: () {},
          onReturnHome: () {},
        ),
        SimulatedPaymentPage(
          draft: draft,
          onOpenBookings: () {},
          onReturnHome: () {},
        ),
        BookingRequestSubmittedPage(
          draft: draft,
          onOpenBookings: () {},
          onReturnHome: () {},
        ),
        BookingsPage(latestDraft: () => draft),
      ];

      for (final screen in screens) {
        await tester.pumpWidget(_app(screen, booking));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$screen at $size');
      }
    });
  }
}

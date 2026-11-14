import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:renthub_flutter/core/network/api_client.dart';
import 'package:renthub_flutter/core/theme/app_theme.dart';
import 'package:renthub_flutter/features/live/live_appointments.dart';
import 'package:renthub_flutter/features/live/live_handover_receipt.dart';
import 'package:renthub_flutter/features/live/live_owner_shell.dart';
import 'package:renthub_flutter/features/live/live_rental_progress.dart';
import 'package:renthub_flutter/features/live/live_renter_shell.dart';
import 'package:renthub_flutter/features/live/live_renthub_controller.dart';
import 'package:renthub_flutter/shared/models/domain_models.dart';

void main() {
  for (final owner in [false, true]) {
    for (final width in [360.0, 390.0]) {
      testWidgets(
          'appointments, progress and handover order; owner=$owner width=$width',
          (t) async {
        await t.binding.setSurfaceSize(Size(width, 1100));
        addTearDown(() => t.binding.setSurfaceSize(null));
        final c = LiveRentHubController(ApiClient('https://unused.invalid'))
          ..profile = User(
              id: owner ? 'owner' : 'renter',
              name: 'Participant',
              email: 'person@example.test',
              roles: {owner ? UserRole.owner : UserRole.renter});
        addTearDown(c.dispose);
        final workspace = owner ? c.ownerWorkspace : c.renterWorkspace;
        workspace.bookings = [
          Booking.fromJson({
            'publicId': 'RH-BKG-2026-ORDER',
            'listingId': 'camera',
            'listingTitle': 'Camera',
            'listingType': 'physical',
            'renterId': 'renter',
            'ownerId': 'owner',
            'startDate': '2026-10-01',
            'endDate': '2026-10-01',
            'pickupTime': '09:00',
            'returnTime': '18:00',
            'status': 'completed',
            'paymentStatus': 'settled'
          })
        ];
        workspace.rentals = [
          Rental.fromJson({
            'publicId': 'RH-RNT-2026-ORDER',
            'bookingId': 'RH-BKG-2026-ORDER',
            'listingType': 'physical',
            'renterId': 'renter',
            'ownerId': 'owner',
            'status': 'completed',
            'startDate': '2026-10-01',
            'endDate': '2026-10-01',
            'handover': {
              'condition': 'Good',
              'notes': 'Saved condition',
              'evidence': []
            }
          })
        ];
        await t.pumpWidget(ChangeNotifierProvider.value(
            value: c,
            child: MaterialApp(
                theme: AppTheme.light,
                builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(textScaler: TextScaler.linear(1.4)),
                    child: child!),
                home: owner
                    ? const LiveOwnerRequestsPage(
                        focusBookingId: 'RH-BKG-2026-ORDER')
                    : const LiveRenterBookingsPage(
                        focusBookingId: 'RH-BKG-2026-ORDER'))));
        await t.pumpAndSettle();
        expect(find.byType(RentalProgressPanel), findsOneWidget);
        expect(t.getTopLeft(find.byType(RentalAppointments)).dy,
            lessThan(t.getTopLeft(find.byType(RentalProgressPanel)).dy));
        expect(t.getTopLeft(find.byType(RentalProgressPanel)).dy,
            lessThan(t.getTopLeft(find.byType(HandoverPhotosSection)).dy));
        expect(t.takeException(), isNull);
      });
    }
  }
}

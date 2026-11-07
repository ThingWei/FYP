import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/network/user_facing_error.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/models/domain_models.dart';
import '../../shared/widgets/renthub_components.dart';
import '../renter/booking/booking_flow.dart' show formatDateRange, formatMoney;
import 'live_authenticated_page.dart';
import 'live_payment_countdown.dart';
import 'live_rental_progress.dart';
import 'live_renthub_controller.dart';

String bookingStatusText(Booking booking, Rental? rental,
    {bool expired = false}) {
  if (expired || booking.displayStatus == 'expired') return 'Expired';
  if (booking.status == 'cancelled') return 'Cancelled';
  if (booking.status == 'rejected') return 'Declined';
  if (booking.awaitingPayment) return 'Awaiting payment';
  if (booking.status == 'pending') return 'Awaiting Owner approval';
  return rental == null
      ? const {
            'approved': 'Scheduled',
            'active': 'In progress',
            'completed': 'Completed',
            'disputed': 'Issue under review'
          }[booking.status] ??
          'See booking details'
      : rentalStatusLabel(rental.status);
}

Future<void> openBookingDetails(BuildContext context,
    {required Booking booking,
    Rental? rental,
    required bool owner,
    required Widget page}) async {
  await Navigator.push<void>(
      context,
      MaterialPageRoute(
          builder: (_) => LiveAuthenticatedPage(
              renterOnly: !owner,
              sessionMessage:
                  'Sign in with the account that can access this booking.',
              child: _RefreshBookingDetails(
                  bookingId: booking.id, rentalId: rental?.id, child: page))));
  if (context.mounted) {
    await context
        .read<LiveRentHubController>()
        .loadUserRecords(owner ? 'owner-bookings' : 'renter-bookings');
  }
}

class _RefreshBookingDetails extends StatefulWidget {
  const _RefreshBookingDetails(
      {required this.bookingId, this.rentalId, required this.child});
  final String bookingId;
  final String? rentalId;
  final Widget child;
  @override
  State<_RefreshBookingDetails> createState() => _RefreshBookingDetailsState();
}

class _RefreshBookingDetailsState extends State<_RefreshBookingDetails> {
  bool loading = true;
  String? error;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => refresh());
  }

  Future<void> refresh() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      await context
          .read<LiveRentHubController>()
          .refreshFocusedBooking(widget.bookingId, widget.rentalId);
    } catch (e) {
      if (mounted) setState(() => error = friendlyError(e));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final exists = context
        .watch<LiveRentHubController>()
        .bookings
        .any((b) => b.id == widget.bookingId);
    if (!exists) {
      return Scaffold(
          appBar: AppBar(title: const Text('Booking details')),
          body: Center(
              child: loading
                  ? const CircularProgressIndicator()
                  : Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(error ?? 'This booking is not available.'),
                      TextButton(
                          onPressed: refresh, child: const Text('Try again'))
                    ])));
    }
    return Column(children: [
      if (loading) const LinearProgressIndicator(),
      if (error != null)
        Material(
            child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(children: [
                  Expanded(child: Text(error!)),
                  TextButton(onPressed: refresh, child: const Text('Retry'))
                ]))),
      Expanded(child: widget.child)
    ]);
  }
}

class LiveBookingSummaryCard extends StatelessWidget {
  const LiveBookingSummaryCard(
      {super.key,
      required this.booking,
      this.rental,
      this.owner = false,
      required this.onDetails,
      this.onPay,
      this.onExpired});
  final Booking booking;
  final Rental? rental;
  final bool owner;
  final VoidCallback onDetails;
  final VoidCallback? onPay;
  final Future<void> Function()? onExpired;
  @override
  Widget build(BuildContext context) => BookingPaymentClock(
      booking: booking,
      onExpired: onExpired,
      builder: (context, remaining, expired) => Card(
          child: InkWell(
              onTap: onDetails,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        StatusBadge(bookingStatusText(booking, rental,
                            expired: expired)),
                        const SizedBox(height: 12),
                        Text(booking.listingTitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        Text(formatDateRange(booking.start, booking.end),
                            style: const TextStyle(
                                color: AppColors.secondaryText)),
                        if (owner && booking.renterName.isNotEmpty)
                          Text(booking.renterName,
                              style: const TextStyle(
                                  color: AppColors.secondaryText)),
                        const SizedBox(height: 8),
                        Text(formatMoney(booking.total),
                            style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: AppColors.primaryDark)),
                        if (booking.awaitingPayment)
                          Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: PaymentCountdownLabel(
                                  remaining: remaining,
                                  expired: expired,
                                  compact: true)),
                        const SizedBox(height: 12),
                        Row(children: [
                          Expanded(
                              child: OutlinedButton(
                                  onPressed: onDetails,
                                  child: const Text('View details'))),
                          if (!owner &&
                              !expired &&
                              booking.canContinuePayment &&
                              onPay != null) ...[
                            const SizedBox(width: 12),
                            Expanded(
                                child: FilledButton(
                                    onPressed: onPay,
                                    child: const Text('Continue payment',
                                        textAlign: TextAlign.center)))
                          ],
                        ]),
                      ])))));
}

class BookingStatusHeader extends StatelessWidget {
  const BookingStatusHeader(
      {super.key,
      required this.booking,
      this.rental,
      this.owner = false,
      this.onExpired});
  final Booking booking;
  final Rental? rental;
  final bool owner;
  final Future<void> Function()? onExpired;
  @override
  Widget build(BuildContext context) => BookingPaymentClock(
      booking: booking,
      onExpired: onExpired,
      builder: (context, remaining, expired) {
        final unpaidExpiry = booking.paymentStatus == 'unpaid' &&
            (expired || booking.displayStatus == 'expired');
        return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              StatusBadge(bookingStatusText(booking, rental, expired: expired)),
              const SizedBox(height: 8),
              Text(
                  unpaidExpiry
                      ? 'This checkout has expired'
                      : booking.awaitingPayment
                          ? owner
                              ? 'Waiting for renter payment'
                              : 'Finish payment to send your request'
                          : RentalJourney.forRecord(
                                  booking: booking,
                                  rental: rental,
                                  owner: owner)
                              .title,
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text(unpaidExpiry
                  ? 'Payment was not completed in time. No payment was taken. Choose dates again to start a new checkout.'
                  : booking.awaitingPayment
                      ? 'Complete payment within 10 minutes of starting checkout. The Owner reviews your request after payment.'
                      : RentalJourney.forRecord(
                              booking: booking, rental: rental, owner: owner)
                          .next),
              if (booking.awaitingPayment)
                Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: PaymentCountdownLabel(
                        remaining: remaining, expired: expired)),
            ]));
      });
}

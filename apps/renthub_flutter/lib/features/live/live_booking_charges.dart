import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/network/user_facing_error.dart';
import '../../core/theme/app_theme.dart';
import '../../modules/payment/repositories/payment_repository.dart';
import '../../shared/models/domain_models.dart';
import '../renter/booking/booking_flow.dart' show formatMoney;
import 'live_rental_progress.dart';
import 'live_renthub_controller.dart';
import 'live_appointments.dart';

class LiveBookingPaymentDetails extends StatelessWidget {
  const LiveBookingPaymentDetails({super.key, required this.booking});
  final Booking booking;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<LiveRentHubController>();
    return _BookingPaymentDetails(
      key:
          ValueKey((controller.profile?.id, booking.id, booking.paymentStatus)),
      booking: booking,
      repository: LiveBookingPaymentRepository(controller.api),
    );
  }
}

class _BookingPaymentDetails extends StatefulWidget {
  const _BookingPaymentDetails(
      {super.key, required this.booking, required this.repository});
  final Booking booking;
  final LiveBookingPaymentRepository repository;

  @override
  State<_BookingPaymentDetails> createState() => _BookingPaymentDetailsState();
}

class _BookingPaymentDetailsState extends State<_BookingPaymentDetails> {
  List<Transaction> history = [];
  bool loading = false;
  Object? error;

  Future<void> _load() async {
    if (loading) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final payments =
          await widget.repository.listForBooking(widget.booking.id);
      if (mounted) setState(() => history = payments);
    } catch (exception) {
      if (mounted) setState(() => error = exception);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${formatMoney(widget.booking.total)} · ${rentalPaymentLabel(widget.booking.paymentStatus)}',
            style: const TextStyle(
                color: AppColors.primaryDark, fontWeight: FontWeight.w700),
          ),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            leading: const Icon(Icons.receipt_long_outlined),
            title: const Text('See payment details'),
            onExpansionChanged: (expanded) {
              if (expanded) _load();
            },
            expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LiveBookingCharges(booking: widget.booking),
              const SizedBox(height: 16),
              Text('Payment history',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              if (loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Column(children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 8),
                    Text('Loading payment history…'),
                  ]),
                )
              else if (error != null)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(friendlyError(error!)),
                    TextButton.icon(
                      onPressed: _load,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry payment history'),
                    ),
                  ],
                )
              else if (history.isEmpty)
                const Text(
                    'No payment transactions have been recorded for this booking.')
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final payment in history)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: LivePaymentSummary(payment: payment),
                      ),
                  ],
                ),
              const SizedBox(height: 16),
            ],
          ),
        ],
      );
}

class LivePaymentSummary extends StatelessWidget {
  const LivePaymentSummary({super.key, required this.payment});
  final Transaction payment;
  @override
  Widget build(BuildContext context) => Card(
      child: Padding(
          padding: const EdgeInsets.all(12),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
                switch (payment.type) {
                  'authorization' => 'Payment authorization',
                  'refund' => 'Refund',
                  'dispute_release' => 'Dispute refund',
                  'deposit_release' => 'Deposit returned',
                  'deposit_deduction' => 'Deposit deduction',
                  'owner_settlement' => 'Owner earnings',
                  'platform_retention' => payment.rewardReversal
                      ? 'Unused reward returned to RentHub'
                      : 'Platform fee retained',
                  'reward_credit' => 'Reward covered by RentHub',
                  'capture' => 'Payment collected',
                  _ => 'Payment update'
                },
                style: Theme.of(context).textTheme.titleMedium),
            Text(formatMoney(payment.amount)),
            Text('Reference: ${payment.id}'),
            Text(switch (payment.status) {
              'succeeded' => 'Complete',
              'authorized' => 'Authorized',
              'failed' => 'Declined',
              'voided' => 'Cancelled',
              _ => 'Pending'
            }),
            const Text('Simulated payment'),
          ])));
}

class LiveBookingCharges extends StatelessWidget {
  const LiveBookingCharges({super.key, required this.booking});
  final Booking booking;
  @override
  Widget build(BuildContext context) {
    final charges = booking.charges;
    Widget row(String label, double amount) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Expanded(child: Text(label)),
          const SizedBox(width: 12),
          Text(formatMoney(amount)),
        ]));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (booking.listingType == 'physical')
        RentalAppointments(
            pickup: booking.pickupTime, returnTime: booking.returnTime),
      Text('Charges', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      if (charges != null) ...[
        row(booking.listingType == 'service' ? 'Service' : 'Rental',
            charges.base),
        if (booking.listingType != 'service')
          row('Security deposit', charges.deposit),
        if (charges.waiver > 0 && booking.listingType != 'service')
          row('Optional damage waiver', charges.waiver),
        if (charges.platform > 0) row('Platform fee', charges.platform),
        if (booking.listingType != 'service')
          row('Delivery fee', charges.delivery),
        if (charges.rewardDiscount > 0)
          Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(children: [
                const Expanded(child: Text('Reward discount')),
                Text('−${formatMoney(charges.rewardDiscount)}',
                    style: const TextStyle(color: AppColors.success))
              ])),
      ] else
        const Text(
            'The detailed charge breakdown is unavailable for this record.'),
      const Divider(),
      row(
          booking.extensionCharges.isEmpty
              ? 'Total (MYR)'
              : 'Original booking total',
          booking.total),
      for (final extension in booking.extensionCharges)
        row('Approved extra days (${extension.extraDays})', extension.amount),
      if (booking.extensionCharges.isNotEmpty) ...[
        const Divider(),
        row(
            'Charges including extra days',
            booking.total +
                booking.extensionCharges.fold<double>(
                    0, (sum, extension) => sum + extension.amount)),
        const Text(
            'Refunds and payouts are shown separately in payment history.'),
      ],
    ]);
  }
}

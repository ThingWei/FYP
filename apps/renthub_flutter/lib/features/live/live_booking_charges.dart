import 'package:flutter/material.dart';
import '../../shared/models/domain_models.dart';
import '../renter/booking/booking_flow.dart' show formatMoney;

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
                  'refund' => 'Refund',
                  'deposit_release' => 'Deposit returned',
                  'deposit_deduction' => 'Deposit deduction',
                  'owner_settlement' => 'Owner earnings',
                  'capture' => 'Payment collected',
                  _ => 'Payment update'
                },
                style: Theme.of(context).textTheme.titleMedium),
            Text(formatMoney(payment.amount)),
            Text(switch (payment.status) {
              'succeeded' => 'Complete',
              'authorized' => 'Authorized',
              'failed' => 'Declined',
              'voided' => 'Cancelled',
              _ => 'Pending'
            }),
            const Text('Demo payment — no real money was transferred.'),
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
      ] else
        const Text(
            'The detailed charge breakdown is unavailable for this record.'),
      const Divider(),
      row('Total (MYR)', booking.total),
    ]);
  }
}

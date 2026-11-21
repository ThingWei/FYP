import '../../shared/models/domain_models.dart';

const disputeWindowClosedMessage =
    'This rental is complete, so a new dispute can no longer be opened.';

List<String> allowedDisputeCategories(Rental rental, {required bool owner}) {
  if (rental.listingType != 'physical') {
    return const [
      'service_quality',
      'non_delivery',
      'scope_mismatch',
      'cancellation',
      'communication',
      'other'
    ];
  }
  final started = [
        'active',
        'overdue',
        'return_submitted',
        'completion_pending'
      ].contains(rental.status) ||
      rental.handover?.receiptStatus == 'acknowledged';
  return [
    if (started || !owner && rental.awaitingReceipt) ...[
      'damaged_item',
      'missing_item'
    ],
    if (rental.returnSubmission?.recordedAt != null) ...[
      'return_condition',
      'deposit_deduction'
    ],
    if (started && rental.overdueReturn == true) 'late_return',
    'communication',
    'other'
  ];
}

/// Calendar end dates and demo payment do not establish final completion.
String? disputeCreationBlockReason(Rental rental, {Booking? booking}) {
  if (rental.status == 'completed' || booking?.status == 'completed') {
    return disputeWindowClosedMessage;
  }
  if (rental.status == 'cancelled' ||
      rental.status == 'scheduled' && !rental.awaitingReceipt ||
      rental.status == 'expired' ||
      booking?.status == 'expired') {
    return 'A new dispute is not available at this stage of the booking.';
  }
  return null;
}

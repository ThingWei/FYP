import '../../shared/models/domain_models.dart';

const disputeWindowClosedMessage =
    'This rental is complete, so a new dispute can no longer be opened.';

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

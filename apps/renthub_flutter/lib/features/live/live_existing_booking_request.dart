import 'package:flutter/material.dart';

import '../../core/network/api_client.dart';

class ExistingBookingRequest {
  const ExistingBookingRequest(this.bookingId);
  final String bookingId;

  static ExistingBookingRequest? fromError(Object error) {
    if (error is! ApiException ||
        error.status != 409 ||
        error.code != 'DUPLICATE_PENDING_BOOKING' ||
        error.details is! Map) {
      return null;
    }
    final id = (error.details as Map)['bookingId'];
    if (id is! String || !RegExp(r'^RH-BKG-\d{4}-[A-Z0-9]+$').hasMatch(id)) {
      return null;
    }
    return ExistingBookingRequest(id);
  }
}

Future<bool> offerExistingBookingRequest(BuildContext context, Object error,
    {required Future<void> Function(String bookingId) onOpen}) async {
  final existing = ExistingBookingRequest.fromError(error);
  if (existing == null) return false;
  final open = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
            title: const Text('You already have a request'),
            content: const Text(
                'You have a pending request for this item on overlapping dates. '
                'Open it to continue payment or check its progress. To change dates, cancel that request first.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Keep editing')),
              FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('View existing request')),
            ],
          ));
  if (open == true && context.mounted) await onOpen(existing.bookingId);
  return true;
}

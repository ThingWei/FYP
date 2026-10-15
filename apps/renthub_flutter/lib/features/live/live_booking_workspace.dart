import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/network/user_facing_error.dart';
import '../../shared/widgets/account_components.dart';
import 'live_renthub_controller.dart';

/// Retains role-specific records on refresh failures, without showing another
/// role's data or calling an unsuccessful load an empty collection.
class LiveBookingWorkspace extends StatelessWidget {
  const LiveBookingWorkspace({
    super.key,
    required this.state,
    required this.hasRecords,
    required this.onRetry,
    required this.child,
  });

  final BookingWorkspaceState state;
  final bool hasRecords;
  final Future<void> Function() onRetry;
  final Widget child;

  void _retry() => unawaited(onRetry().catchError((Object _) {}));

  @override
  Widget build(BuildContext context) {
    final failure =
        state.error == null ? null : UserFacingError.from(state.error);
    if (!hasRecords && state.loading) {
      return const RentHubFeedbackState(
        kind: FeedbackKind.loading,
        title: 'Loading your bookings',
        message: 'Getting the latest requests and rentals.',
      );
    }
    if (!hasRecords && failure != null) {
      return RentHubFeedbackState(
        kind: FeedbackKind.error,
        title: failure.title,
        message: failure.message,
        actionLabel: 'Try again',
        onAction: _retry,
      );
    }
    return Column(children: [
      if (state.loading) const LinearProgressIndicator(),
      if (failure != null)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text(failure.message),
            TextButton(onPressed: _retry, child: const Text('Retry')),
          ]),
        ),
      Expanded(child: child),
    ]);
  }
}

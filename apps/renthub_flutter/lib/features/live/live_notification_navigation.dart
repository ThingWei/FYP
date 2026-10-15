import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/network/api_client.dart';
import '../../core/network/user_facing_error.dart';
import '../../modules/user/controllers/auth_controller.dart';
import '../../shared/models/domain_models.dart';
import 'live_authenticated_page.dart';
import 'live_dispute_page.dart';
import 'live_loyalty_page.dart';
import 'live_owner_shell.dart';
import 'live_renter_shell.dart';
import 'live_renthub_controller.dart';
import 'live_shared_pages.dart';

class NotificationTarget {
  NotificationTarget.fromJson(Map row)
      : kind = row['kind'] as String? ?? 'unavailable',
        bookingId = row['bookingId'] as String?,
        rentalId = row['rentalId'] as String?,
        threadId = row['threadId'] as String?,
        paymentId = row['paymentId'] as String?,
        disputeId = row['disputeId'] as String? {
    if (!const [
          'booking',
          'chat',
          'dispute',
          'rewards',
          'verification',
          'unavailable'
        ].contains(kind) ||
        (const ['booking', 'chat', 'dispute'].contains(kind) &&
            !_id(bookingId)) ||
        (kind == 'chat' && !_id(threadId)) ||
        (kind == 'dispute' && (!_id(disputeId) || !_id(rentalId))) ||
        (rentalId != null && !_id(rentalId)) ||
        (paymentId != null && !_id(paymentId))) {
      throw const FormatException('Invalid notification target');
    }
  }
  static bool _id(String? value) =>
      value != null && RegExp(r'^[A-Za-z0-9_-]{1,100}$').hasMatch(value);
  final String kind;
  final String? bookingId, rentalId, threadId, disputeId, paymentId;
}

final _openingNotifications = Expando<Set<String>>();

Future<void> openRentHubNotification(
    BuildContext context, RentHubNotification note,
    {NavigatorState? navigator}) async {
  final auth = context.read<AuthController>();
  if (!auth.authenticated) return;
  final nav = navigator ?? Navigator.of(context);
  final opening = _openingNotifications[nav] ??= <String>{};
  final key = '${auth.user!.id}/${note.id}';
  if (!opening.add(key)) return;
  final controller = context.read<LiveRentHubController>();
  // Marking read must not gate navigation or reset the notification filter.
  if (!note.read && note.id.isNotEmpty) {
    unawaited(controller.markNotificationRead(note.id).catchError((_) {}));
  }
  try {
    await nav.push<void>(MaterialPageRoute(
        builder: (_) => LiveAuthenticatedPage(
            sessionMessage:
                'Your session changed. Return to the app and sign in again to view this update.',
            child: LiveNotificationDestination(notification: note))));
  } finally {
    opening.remove(key);
  }
}

class LiveNotificationDestination extends StatefulWidget {
  const LiveNotificationDestination({super.key, required this.notification});
  final RentHubNotification notification;
  @override
  State<LiveNotificationDestination> createState() =>
      _LiveNotificationDestinationState();
}

class _LiveNotificationDestinationState
    extends State<LiveNotificationDestination> {
  Widget? destination;
  bool loading = true, sessionExpired = false;
  String? message;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final auth = context.read<AuthController>();
    final userId = auth.user?.id;
    if (!auth.authenticated) {
      setState(() {
        loading = false;
        sessionExpired = true;
      });
      return;
    }
    final c = context.read<LiveRentHubController>();
    bool current() => mounted && auth.user?.id == userId && auth.authenticated;
    setState(() {
      loading = true;
      message = null;
      destination = null;
    });
    try {
      if (c.profile?.id != userId) {
        final profile = await c.api
            .request('GET', '/users/me')
            .timeout(const Duration(seconds: 15));
        if (!current()) return;
        c.profile = User.fromJson(Map<String, dynamic>.from(profile as Map));
      }
      if (widget.notification.id.isEmpty) throw const FormatException();
      final target = NotificationTarget.fromJson(await c.api
          .request('GET',
              '/messages/notifications/${Uri.encodeComponent(widget.notification.id)}/target')
          .timeout(const Duration(seconds: 15)) as Map);
      if (!current()) return;
      if (target.kind == 'rewards') {
        destination = const LiveLoyaltyPage();
      } else if (target.kind == 'verification') {
        destination = const LiveVerificationPage();
      } else if (target.kind != 'unavailable') {
        await c.refreshFocusedBooking(target.bookingId!, target.rentalId);
        if (!current()) return;
        final booking =
            c.bookings.firstWhere((item) => item.id == target.bookingId);
        final owner = booking.ownerId == userId;
        if (target.kind == 'chat') {
          destination = LiveChatPage(
              conversation: Conversation(
                  id: target.threadId!,
                  bookingId: booking.id,
                  listingTitle: booking.listingTitle,
                  otherParticipantName:
                      owner ? booking.renterName : booking.ownerName,
                  unreadCount: 0,
                  lastMessageText: ''));
        } else if (target.kind == 'dispute') {
          final row = await c.loadDisputeCase(target.disputeId!);
          if (!current()) return;
          final dispute = Dispute.fromJson(row);
          c.disputes = [
            ...c.disputes.where((item) => item.id != dispute.id),
            dispute
          ];
          if (row['claim'] is Map) {
            final claim = InsuranceClaim.fromJson(
                Map<String, dynamic>.from(row['claim'] as Map));
            c.claims = [
              ...c.claims.where((item) => item.id != claim.id),
              claim
            ];
          }
          destination = LiveDisputePage(
              rental:
                  c.rentals.firstWhere((item) => item.id == target.rentalId),
              owner: owner);
        } else {
          Transaction? payment;
          if (target.paymentId != null) {
            final rows = await c.api
                .request('GET', '/payments/booking/${booking.id}')
                .timeout(const Duration(seconds: 15));
            if (!current()) return;
            final matches = (rows as List).where((row) =>
                row is Map &&
                (row['publicId'] ?? row['id']) == target.paymentId);
            if (matches.isEmpty) throw ApiException(404, 'Payment unavailable');
            payment = Transaction.fromJson(
                Map<String, dynamic>.from(matches.first as Map));
          }
          destination = owner
              ? LiveOwnerRequestsPage(
                  focusBookingId: booking.id,
                  focusRentalId: target.rentalId,
                  payment: payment)
              : LiveRenterBookingsPage(
                  focusBookingId: booking.id,
                  focusRentalId: target.rentalId,
                  payment: payment);
        }
      }
      if (current()) setState(() => loading = false);
    } catch (error) {
      if (current()) {
        setState(() {
          loading = false;
          sessionExpired = error is ApiException && error.status == 401;
          message = error is ApiException && error.status == 404
              ? 'The related record is no longer available to this account.'
              : friendlyError(error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (destination != null) return destination!;
    return Scaffold(
        appBar: AppBar(
            title: Text(
                sessionExpired ? 'Sign in required' : 'Notification details')),
        body: loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(padding: const EdgeInsets.all(20), children: [
                if (sessionExpired)
                  const Text(
                      'Your session has expired. Return to the app and sign in again.')
                else ...[
                  Text(widget.notification.title,
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 12),
                  Text(widget.notification.body),
                  if (widget.notification.createdAt != null)
                    Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(MaterialLocalizations.of(context)
                            .formatMediumDate(
                                widget.notification.createdAt!.toLocal()))),
                  const SizedBox(height: 16),
                  Text(message ??
                      'No related page is available for this notification.'),
                  TextButton.icon(
                      onPressed: _load,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Try again')),
                ],
              ]));
  }
}

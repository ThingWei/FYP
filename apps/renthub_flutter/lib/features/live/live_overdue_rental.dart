import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/network/user_facing_error.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/models/domain_models.dart';
import 'live_renthub_controller.dart';
import 'live_chat_page.dart';
import 'live_dispute_page.dart';
import 'live_condition_record_page.dart';

class OverdueRentalPanel extends StatefulWidget {
  const OverdueRentalPanel(
      {super.key, required this.rental, this.owner = false});
  final Rental rental;
  final bool owner;
  @override
  State<OverdueRentalPanel> createState() => _OverdueRentalPanelState();
}

class _OverdueRentalPanelState extends State<OverdueRentalPanel> {
  bool busy = false;
  String? error;
  Future<void> message() async {
    if (busy) return;
    final c = context.read<LiveRentHubController>();
    final generation = c.accountGeneration;
    final account = c.profile?.id;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final response = await c.api.request(
          'POST', '/messages/threads/from-booking/${widget.rental.bookingId}');
      if (!mounted ||
          c.accountGeneration != generation ||
          c.profile?.id != account) {
        return;
      }
      final conversation =
          Conversation.fromJson(Map<String, dynamic>.from(response as Map));
      await Navigator.push<void>(
          context,
          MaterialPageRoute(
              builder: (_) => LiveChatPage(conversation: conversation)));
    } catch (e) {
      if (mounted &&
          c.accountGeneration == generation &&
          c.profile?.id == account) {
        setState(() => error = friendlyError(e));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<LiveRentHubController>();
    final r = widget.rental;
    final actualParticipant = widget.owner ? r.ownerId : r.renterId;
    if (!r.hasOverdueReturn || c.profile?.id != actualParticipant) {
      return const SizedBox.shrink();
    }
    final existing = c.disputeForRental(r.id);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.warning)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.schedule, color: AppColors.warning),
          const SizedBox(width: 8),
          Expanded(
              child: Text(
                  r.overdueNeedsAttention
                      ? 'Overdue — needs attention'
                      : 'Return overdue',
                  style: Theme.of(context).textTheme.titleMedium)),
        ]),
        const SizedBox(height: 8),
        Text(widget.owner
            ? 'Your item has not been recorded as returned. Message the renter to arrange its return, or report the issue for review.'
            : 'Please arrange the return with the Owner. New bookings are unavailable until your return is submitted or an administrator resolves the case.'),
        if (r.overdueNeedsAttention)
          const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                  'This rental needs administrator attention. No penalty or payment decision has been made automatically.')),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          OutlinedButton.icon(
              onPressed: busy ? null : message,
              icon: const Icon(Icons.chat_bubble_outline),
              label: Text(busy
                  ? 'Opening conversation…'
                  : widget.owner
                      ? 'Message renter'
                      : 'Message Owner')),
          if (!widget.owner && ['active', 'overdue'].contains(r.status))
            FilledButton(
                onPressed: () =>
                    openConditionRecord(context, r, handover: false),
                child: const Text('Submit return')),
          if (existing != null || c.canStartDispute(r))
            OutlinedButton.icon(
                onPressed: () => Navigator.push<void>(
                    context,
                    MaterialPageRoute(
                        builder: (_) => LiveDisputePage(
                            rental: r,
                            owner: widget.owner,
                            initialCategory:
                                widget.owner ? 'late_return' : null))),
                icon: const Icon(Icons.support_agent_outlined),
                label: Text(existing != null
                    ? 'View case'
                    : widget.owner
                        ? 'Report item not returned'
                        : 'Report an issue')),
        ]),
        if (error != null)
          Padding(
              padding: const EdgeInsets.only(top: 8),
              child:
                  Text(error!, style: const TextStyle(color: AppColors.error))),
        if (widget.owner)
          const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text(
                  'Keep the handover photos and agreement. Administrators can review the issue and any remaining held deposit; compensation is not guaranteed.')),
      ]),
    );
  }
}

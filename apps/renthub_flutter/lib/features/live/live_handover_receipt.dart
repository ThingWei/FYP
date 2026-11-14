import 'package:flutter/material.dart';
import 'live_listing_gallery.dart';
import 'package:provider/provider.dart';
import '../../core/network/user_facing_error.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/calendar_date.dart';
import '../../shared/models/domain_models.dart';
import '../../shared/widgets/renthub_components.dart';
import 'live_dispute_page.dart';
import 'live_photo_widgets.dart';
import 'live_rental_progress.dart';
import 'live_renthub_controller.dart';

class ReturnPhotosSection extends StatelessWidget {
  const ReturnPhotosSection({super.key, required this.rental});
  final Rental rental;
  @override
  Widget build(BuildContext context) {
    final record = rental.returnSubmission;
    if (rental.listingType != 'physical' || record == null) {
      return const SizedBox.shrink();
    }
    return Card(
        child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(children: [
                    const Icon(Icons.assignment_return_outlined,
                        color: AppColors.primary),
                    const SizedBox(width: 12),
                    Expanded(
                        child: Text('Return',
                            style: Theme.of(context).textTheme.titleMedium))
                  ]),
                  const SizedBox(height: 12),
                  Text(
                      'Condition: ${record.condition.isEmpty ? 'Not recorded' : record.condition}',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  if (record.notes.isNotEmpty)
                    Text(record.notes,
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                  if (record.photos.isNotEmpty)
                    Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: ListingPhotoCarousel(
                            photos: record.photos,
                            title: 'Return',
                            compact: true))
                  else
                    const Padding(
                        padding: EdgeInsets.only(top: 12),
                        child: Text('No return photos were saved.')),
                  ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: const Text('Details'),
                      children: [
                        ListTile(
                            dense: true,
                            title: const Text('Returned by renter'),
                            subtitle: Text(rentalEventTime(record.recordedAt))),
                        if (record.notes.isNotEmpty)
                          ListTile(
                              dense: true,
                              title: const Text('Notes'),
                              subtitle: Text(record.notes)),
                      ]),
                ])));
  }
}

/// Participant-only saved condition evidence, separate from the progress rail.
class HandoverPhotosSection extends StatefulWidget {
  const HandoverPhotosSection(
      {super.key,
      required this.rental,
      this.owner = false,
      this.ownerName = ''});
  final Rental rental;
  final bool owner;
  final String ownerName;
  @override
  State<HandoverPhotosSection> createState() => _HandoverPhotosSectionState();
}

class _HandoverPhotosSectionState extends State<HandoverPhotosSection> {
  final pages = PageController();
  int selected = 0;
  bool reviewing = false,
      checked = false,
      busy = false,
      needsStatusCheck = false;
  String? error;
  @override
  void dispose() {
    pages.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant HandoverPhotosSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.rental.id != widget.rental.id ||
        oldWidget.rental.handover?.handoverId !=
            widget.rental.handover?.handoverId) {
      reviewing = false;
      checked = false;
      error = null;
      selected = 0;
    }
  }

  Rental latest(LiveRentHubController c) =>
      [...c.renterRentals, ...c.ownerRentals]
          .where((r) => r.id == widget.rental.id)
          .firstOrNull ??
      widget.rental;
  bool windowClosed(Rental rental) =>
      rental.handover?.reviewNeededAt != null ||
      rental.end != null &&
          calendarDate(rental.end!).isBefore(malaysiaCalendarToday());

  Future<void> refreshOrConfirm({bool confirm = false}) async {
    if (busy) return;
    final c = context.read<LiveRentHubController>();
    final accountId = c.profile?.id;
    final generation = c.accountGeneration;
    final viewedHandoverId = latest(c).handover?.handoverId;
    if (accountId != widget.rental.renterId || widget.owner) return;
    setState(() {
      busy = true;
      error = null;
    });
    bool current() =>
        mounted &&
        c.profile?.id == accountId &&
        c.accountGeneration == generation;
    try {
      await c.refreshFocusedBooking(widget.rental.bookingId, widget.rental.id);
      if (!current()) return;
      final rental = latest(c);
      if (rental.handover?.handoverId != viewedHandoverId) {
        setState(() {
          checked = false;
          error =
              'The handover record changed. Review the latest photos before confirming.';
        });
        return;
      }
      setState(() => needsStatusCheck = false);
      if (!confirm || !rental.awaitingReceipt) return;
      if (rental.status != 'scheduled' ||
          windowClosed(rental) ||
          rental.handover?.receiptStatus == 'processing') {
        setState(() => error =
            'Receipt confirmation is unavailable. Check the handover status or report an issue.');
        return;
      }
      if (!mounted) return;
      final accepted = await confirmAction(context,
          title: 'Confirm item received?',
          message:
              'Confirm that you have received the item and reviewed the Owner’s condition and photos. This starts the rental and completes the payment. You can still report a problem during the rental.',
          action: 'Confirm receipt');
      if (!current() || !accepted) return;
      await c.runRentalAction(rental, 'handover-acknowledge',
          body: {'handoverId': rental.handover!.handoverId});
    } catch (e) {
      if (current()) {
        final saved = latest(c);
        if (saved.handover?.receiptStatus == 'acknowledged') return;
        setState(() {
          needsStatusCheck = true;
          error =
              '${friendlyError(e)} Check the latest status before trying again.';
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<LiveRentHubController>();
    final rental = latest(c), record = rental.handover;
    if (rental.listingType == 'service' ||
        c.profile == null ||
        ![rental.ownerId, rental.renterId].contains(c.profile!.id)) {
      return const SizedBox.shrink();
    }
    final canAcknowledge = !widget.owner &&
        c.profile!.id == rental.renterId &&
        rental.awaitingReceipt &&
        rental.status == 'scheduled' &&
        !windowClosed(rental) &&
        handoverDayReached(rental) &&
        record?.receiptStatus != 'processing';
    final issue = c.disputeForRental(rental.id);
    final status = record == null
        ? 'Not submitted yet'
        : rental.awaitingReceipt
            ? windowClosed(rental)
                ? 'Handover needs review'
                : record.receiptStatus == 'processing'
                    ? 'Receipt confirmation processing'
                    : 'Awaiting renter confirmation'
            : record.receiptStatus == 'acknowledged'
                ? 'Renter confirmed receipt'
                : 'Renter confirmation was not recorded';
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: AppColors.blueSurface,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(12)),
      child: Material(
          type: MaterialType.transparency,
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.photo_library_outlined,
                  color: AppColors.primary),
              const SizedBox(width: 12),
              Expanded(
                  child: Text('Handover',
                      style: Theme.of(context).textTheme.titleMedium))
            ]),
            const SizedBox(height: 12),
            if (rental.awaitingReceipt ||
                record?.receiptStatus == 'acknowledged')
              Text(status, style: const TextStyle(fontWeight: FontWeight.w600)),
            if (record == null)
              const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text('No handover record is available.'))
            else ...[
              const SizedBox(height: 12),
              Text(
                  'Condition: ${record.condition.isEmpty ? 'Not recorded' : record.condition}',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              if (record.notes.isNotEmpty)
                Text(record.notes,
                    maxLines: 2, overflow: TextOverflow.ellipsis),
              if (record.photos.isEmpty)
                const Text('No photos were saved for this older record.')
              else ...[
                const SizedBox(height: 12),
                LayoutBuilder(
                    builder: (context, box) => SizedBox(
                        height: 160,
                        child: PageView.builder(
                            controller: pages,
                            itemCount: record.photos.length,
                            onPageChanged: (i) => setState(() => selected = i),
                            itemBuilder: (context, i) => LivePhotoThumbnail(
                                reference: record.photos[i],
                                label: 'Handover photo ${i + 1}',
                                controller: c,
                                width: box.maxWidth,
                                height: double.infinity)))),
                if (record.photos.length > 1)
                  Row(children: [
                    IconButton(
                        tooltip: 'Previous handover photo',
                        onPressed: selected > 0
                            ? () => pages.previousPage(
                                duration: const Duration(milliseconds: 200),
                                curve: Curves.easeOut)
                            : null,
                        icon: const Icon(Icons.chevron_left)),
                    Expanded(
                        child: Text('${selected + 1} / ${record.photos.length}',
                            textAlign: TextAlign.center)),
                    IconButton(
                        tooltip: 'Next handover photo',
                        onPressed: selected + 1 < record.photos.length
                            ? () => pages.nextPage(
                                duration: const Duration(milliseconds: 200),
                                curve: Curves.easeOut)
                            : null,
                        icon: const Icon(Icons.chevron_right))
                  ]),
              ],
              ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: const Text('Details'),
                  children: [
                    ListTile(
                        dense: true,
                        title: const Text('Submitted by Owner'),
                        subtitle: Text(rentalEventTime(record.recordedAt))),
                    ListTile(
                        dense: true,
                        title: Text(status),
                        subtitle: record.acknowledgedAt == null
                            ? null
                            : Text(rentalEventTime(record.acknowledgedAt))),
                    if (record.notes.isNotEmpty)
                      ListTile(
                          dense: true,
                          title: const Text('Notes'),
                          subtitle: Text(record.notes)),
                  ]),
            ],
            if (error != null)
              Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(error!,
                      style: const TextStyle(color: AppColors.error))),
            if (canAcknowledge && reviewing) ...[
              CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: checked,
                  onChanged: busy
                      ? null
                      : (value) => setState(() => checked = value ?? false),
                  title: const Text(
                      'I have received the item and reviewed the condition and photos.')),
              const Text(
                  'Acknowledging receipt does not remove your right to report a problem.'),
            ],
            if (!widget.owner && rental.awaitingReceipt)
              Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Wrap(spacing: 12, runSpacing: 12, children: [
                    if (needsStatusCheck ||
                        record?.receiptStatus == 'processing')
                      OutlinedButton.icon(
                          onPressed: busy ? null : () => refreshOrConfirm(),
                          icon: const Icon(Icons.refresh),
                          label: const Text('Check latest status'))
                    else if (canAcknowledge)
                      FilledButton.icon(
                          onPressed: busy || reviewing && !checked
                              ? null
                              : reviewing
                                  ? () => refreshOrConfirm(confirm: true)
                                  : () => setState(() => reviewing = true),
                          icon: const Icon(Icons.task_alt),
                          label: Text(busy
                              ? 'Please wait…'
                              : reviewing
                                  ? 'Confirm item received'
                                  : 'Review handover')),
                    if (issue != null || c.canStartDispute(rental))
                      OutlinedButton.icon(
                          onPressed: busy
                              ? null
                              : () => Navigator.push<void>(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) => LiveDisputePage(
                                          rental: rental, owner: false))),
                          icon: const Icon(Icons.report_problem_outlined),
                          label: Text(
                              issue == null ? 'Report an issue' : 'View case')),
                  ])),
          ])),
    );
  }
}

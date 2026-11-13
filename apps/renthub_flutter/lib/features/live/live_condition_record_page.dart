import '../../shared/widgets/section_help.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/network/api_client.dart';
import '../../core/network/user_facing_error.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/calendar_date.dart';
import '../../shared/models/domain_models.dart';
import '../../shared/widgets/renthub_components.dart';
import 'live_authenticated_page.dart';
import 'live_listing_photo_picker.dart';
import 'live_photo_widgets.dart';
import 'live_rental_progress.dart';
import 'live_renthub_controller.dart';

Future<void> openConditionRecord(BuildContext context, Rental rental,
        {required bool handover}) =>
    Navigator.push<void>(
        context,
        MaterialPageRoute(
            builder: (_) => LiveAuthenticatedPage(
                sessionMessage:
                    'Sign in with the same account to view this rental.',
                child: LiveConditionRecordPage(
                    rental: rental, handover: handover))));

class LiveConditionRecordPage extends StatefulWidget {
  const LiveConditionRecordPage(
      {super.key, required this.rental, required this.handover});
  final Rental rental;
  final bool handover;
  @override
  State<LiveConditionRecordPage> createState() =>
      _LiveConditionRecordPageState();
}

class _LiveConditionRecordPageState extends State<LiveConditionRecordPage> {
  final form = GlobalKey<FormState>();
  final notes = TextEditingController();
  final photos = <String>[];
  String? condition, error;
  bool acknowledged = false,
      busy = false,
      needsStatusCheck = false,
      attempted = false;
  @override
  void dispose() {
    notes.dispose();
    super.dispose();
  }

  Rental currentRental(LiveRentHubController c) =>
      [...c.ownerRentals, ...c.renterRentals, ...c.ownerOrderRecords]
          .where((r) => r.id == widget.rental.id)
          .firstOrNull ??
      widget.rental;

  Future<void> addPhotos() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final added = await pickListingPhotos(context, 10 - photos.length,
          purpose: widget.handover ? 'handover_evidence' : 'return_evidence');
      if (mounted) {
        setState(() => photos.addAll(added.where((p) => !photos.contains(p))));
      }
    } catch (e) {
      if (mounted) setState(() => error = friendlyError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> checkStatus() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final c = context.read<LiveRentHubController>();
      await c.refreshFocusedBooking(widget.rental.bookingId, widget.rental.id);
      if (!mounted) return;
      final rental = currentRental(c);
      final recorded =
          widget.handover ? rental.handover : rental.returnSubmission;
      if (recorded != null && photos.every(recorded.photos.contains)) {
        Navigator.pop(context);
        return;
      }
      setState(() {
        needsStatusCheck = false;
        error =
            'Latest status checked. Review your details before trying again.';
      });
    } catch (e) {
      if (mounted) setState(() => error = friendlyError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> submit() async {
    if (busy || needsStatusCheck) return;
    setState(() => attempted = true);
    if (!form.currentState!.validate() || photos.isEmpty || !acknowledged) {
      return;
    }
    final c = context.read<LiveRentHubController>();
    final latest = currentRental(c);
    if (widget.handover &&
        (latest.status != 'scheduled' ||
            latest.hasSubmittedHandover ||
            !handoverDayReached(latest) ||
            latest.end != null &&
                calendarDate(latest.end!).isBefore(malaysiaCalendarToday()))) {
      return;
    }
    final accepted = await confirmAction(context,
        title: widget.handover
            ? 'Send handover for confirmation?'
            : 'Submit your return record?',
        message: widget.handover
            ? 'Your condition, notes and photos will be sent to the renter and cannot be edited afterward. The rental starts only after the renter confirms receipt.'
            : 'The Owner will compare these photos with the handover record and inspect the returned item before completing the rental.',
        action: widget.handover ? 'Send handover' : 'Submit return');
    if (!accepted || !mounted) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await c.runRentalAction(
          widget.rental, widget.handover ? 'handover' : 'return',
          owner: widget.handover,
          body: {
            'condition': condition,
            'notes': notes.text.trim(),
            'evidence': List<String>.from(photos)
          });
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          needsStatusCheck =
              e is! ApiException || e.status == 0 || e.status >= 500;
          error = needsStatusCheck
              ? 'We could not confirm the result. Your photos and notes are kept. Check the latest status before trying again.'
              : friendlyError(e);
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<LiveRentHubController>();
    final rental = currentRental(c);
    final allowed = c.profile != null &&
        (widget.handover ? rental.ownerId : rental.renterId) == c.profile!.id;
    final ended = widget.handover &&
        (rental.status == 'expired' ||
            rental.end != null &&
                calendarDate(rental.end!).isBefore(malaysiaCalendarToday()));
    final ready = !widget.handover ||
        !ended &&
            !rental.hasSubmittedHandover &&
            rental.status == 'scheduled' &&
            handoverDayReached(rental);
    final handoverDate = rental.start == null ? null : rentalDay(rental.start!);
    final handoverNotice = rental.hasSubmittedHandover
        ? 'The handover record is saved. Check the booking for renter confirmation.'
        : ended
            ? 'The booked dates have ended. Handover is closed. Open the booking again to check its expiry and payment status.'
            : handoverDate == null
                ? 'The booked start date is not available. Check the latest rental status before handover.'
                : 'You can send handover from $handoverDate (Malaysia time), when you give the item to the renter. The renter must confirm receipt before the rental starts.';
    return PopScope(
        canPop: !busy,
        child: Scaffold(
            appBar: AppBar(
                title: Text(widget.handover
                    ? 'Handover condition'
                    : 'Return condition')),
            body: !allowed
                ? const Center(
                    child:
                        Text('This rental is not available to this account.'))
                : Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 720),
                        child: Form(
                            key: form,
                            child: ListView(
                                padding: const EdgeInsets.all(16),
                                children: [
                                  RentHubSectionHeader(
                                      widget.handover
                                          ? 'Record the item before it changes hands'
                                          : 'Show the item as you return it',
                                      help: widget.handover
                                          ? 'Take clear photos of the whole item, accessories and any existing marks. Check them with the renter before handing it over.'
                                          : 'Take clear photos of the item and accessories. Describe any changes honestly so the Owner can inspect the return.',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleLarge),
                                  if (!ready) ...[
                                    const SizedBox(height: 16),
                                    DecoratedBox(
                                        decoration: BoxDecoration(
                                            color: AppColors.blueSurface,
                                            borderRadius:
                                                BorderRadius.circular(12)),
                                        child: Padding(
                                            padding: const EdgeInsets.all(16),
                                            child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                      ended
                                                          ? 'Handover is closed'
                                                          : handoverDate == null
                                                              ? 'Check the rental start date'
                                                              : 'Scheduled for $handoverDate',
                                                      style: Theme.of(context)
                                                          .textTheme
                                                          .titleSmall),
                                                  const SizedBox(height: 8),
                                                  Text(handoverNotice),
                                                  const SizedBox(height: 8),
                                                  const Text(
                                                      'Condition photos should show the item on the actual handover day.'),
                                                ]))),
                                  ],
                                  if (!widget.handover)
                                    Padding(
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 12),
                                        child: RentalConditionSection(
                                            title: 'Owner’s handover record',
                                            record: rental.handover)),
                                  const SizedBox(height: 20),
                                  DropdownButtonFormField<String>(
                                      initialValue: condition,
                                      decoration: const InputDecoration(
                                          labelText: 'Actual condition'),
                                      items: const [
                                        'Like new',
                                        'Excellent',
                                        'Good',
                                        'Fair',
                                        'Damaged'
                                      ]
                                          .map((c) => DropdownMenuItem(
                                              value: c, child: Text(c)))
                                          .toList(),
                                      onChanged: busy
                                          ? null
                                          : (value) =>
                                              setState(() => condition = value),
                                      validator: (value) => value == null
                                          ? 'Choose the condition you observed.'
                                          : null,
                                      autovalidateMode:
                                          AutovalidateMode.onUserInteraction),
                                  const SizedBox(height: 16),
                                  TextFormField(
                                      controller: notes,
                                      enabled: !busy,
                                      maxLength: 1000,
                                      minLines: 3,
                                      maxLines: 6,
                                      decoration: const InputDecoration(
                                          labelText:
                                              'Marks, damage or missing accessories',
                                          hintText:
                                              'Describe existing scratches or missing parts. Leave empty if there are none.'),
                                      validator: (value) => (value
                                                      ?.trim()
                                                      .length ??
                                                  0) >
                                              1000
                                          ? 'Use no more than 1,000 characters.'
                                          : null),
                                  const SizedBox(height: 12),
                                  OutlinedButton.icon(
                                      onPressed: busy || photos.length >= 10
                                          ? null
                                          : addPhotos,
                                      icon: const Icon(
                                          Icons.add_a_photo_outlined),
                                      label: Text(
                                          'Add condition photos (${photos.length}/10)')),
                                  const Text(
                                      'At least one photo is required. Add several angles and close-ups where useful.'),
                                  if (attempted && photos.isEmpty)
                                    const Text(
                                        'Add a condition photo before continuing.',
                                        style:
                                            TextStyle(color: AppColors.error)),
                                  for (var i = 0; i < photos.length; i++)
                                    PhotoAttachmentTile(
                                        reference: photos[i],
                                        label: 'Condition photo ${i + 1}',
                                        onRemove: busy
                                            ? null
                                            : () => setState(
                                                () => photos.removeAt(i))),
                                  const SizedBox(height: 12),
                                  CheckboxListTile(
                                      contentPadding: EdgeInsets.zero,
                                      value: acknowledged,
                                      onChanged: busy
                                          ? null
                                          : (value) => setState(() =>
                                              acknowledged = value ?? false),
                                      title: const Text(
                                          'These photos and notes show the condition I observed.'),
                                      controlAffinity:
                                          ListTileControlAffinity.leading),
                                  if (attempted && !acknowledged)
                                    const Text(
                                        'Confirm that the condition record is accurate.',
                                        style:
                                            TextStyle(color: AppColors.error)),
                                  if (error != null)
                                    Padding(
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 12),
                                        child: Text(error!,
                                            style: const TextStyle(
                                                color: AppColors.error))),
                                  const SizedBox(height: 16),
                                  if (!ready && !needsStatusCheck)
                                    Padding(
                                        padding:
                                            const EdgeInsets.only(bottom: 12),
                                        child: Text(handoverNotice)),
                                  FilledButton.icon(
                                      onPressed: busy
                                          ? null
                                          : needsStatusCheck
                                              ? checkStatus
                                              : !ready
                                                  ? null
                                                  : submit,
                                      icon: Icon(needsStatusCheck
                                          ? Icons.refresh
                                          : Icons.check_circle_outline),
                                      label: Text(busy
                                          ? 'Please wait…'
                                          : needsStatusCheck
                                              ? 'Check latest status'
                                              : !ready
                                                  ? ended
                                                      ? 'Handover closed'
                                                      : handoverDate == null
                                                          ? 'Start date needed'
                                                          : 'Handover opens $handoverDate'
                                                  : widget.handover
                                                      ? 'Send handover for confirmation'
                                                      : 'Review & submit return')),
                                  const SizedBox(height: 12),
                                  const Text(
                                      'The record is shared with the other party and can be reviewed by an administrator if there is a problem. It does not automatically assign responsibility.',
                                      style: TextStyle(
                                          color: AppColors.secondaryText)),
                                ]))))));
  }
}

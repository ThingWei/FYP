import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/calendar_date.dart';
import '../../shared/models/domain_models.dart';
import 'live_photo_widgets.dart';

String rentalDay(DateTime value) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec'
  ];
  return '${value.day} ${months[value.month - 1]} ${value.year}';
}

String rentalEventTime(DateTime? value) {
  if (value == null) return 'Time not recorded';
  final myt = value.toUtc().add(const Duration(hours: 8));
  final hour = myt.hour % 12 == 0 ? 12 : myt.hour % 12;
  return '${rentalDay(myt)}, $hour:${myt.minute.toString().padLeft(2, '0')} ${myt.hour < 12 ? 'am' : 'pm'} MYT';
}

String rentalStatusLabel(String status) =>
    const {
      'scheduled': 'Scheduled',
      'active': 'In progress',
      'overdue': 'Return overdue',
      'return_submitted': 'Return awaiting inspection',
      'completion_pending': 'Completion awaiting review',
      'completed': 'Completed',
      'disputed': 'Issue under review',
      'cancelled': 'Cancelled',
      'expired': 'Expired',
    }[status] ??
    'Check progress';

String rentalPaymentLabel(String status) =>
    const {
      'unpaid': 'Demo payment needed',
      'pending': 'Demo payment pending',
      'authorized': 'Demo payment ready',
      'captured': 'Demo payment completed',
      'settled': 'Demo payment settled',
      'failed': 'Demo payment declined',
      'refunded': 'Demo payment refunded',
      'partially_refunded': 'Demo payment partly refunded',
      'voided': 'Demo payment released',
    }[status] ??
    'Payment status unavailable';

bool handoverDayReached(Rental rental, {DateTime? now}) =>
    rental.start != null &&
    !calendarDate(rental.start!).isAfter(malaysiaCalendarToday(now: now));

bool handoverReviewRequired(Rental rental, {DateTime? now}) =>
    rental.handover?.reviewNeededAt != null ||
    rental.end != null &&
        calendarDate(rental.end!).isBefore(malaysiaCalendarToday(now: now));

/// Progress is derived from saved lifecycle states, never from elapsed time alone.
class RentalJourney {
  const RentalJourney(this.title, this.next, this.stage, this.steps,
      {this.paused = false});
  final String title, next;
  final int stage;
  final List<String> steps;
  final bool paused;

  factory RentalJourney.forRecord(
      {Booking? booking, Rental? rental, bool owner = false, DateTime? now}) {
    final status = rental?.status ?? booking?.displayStatus ?? 'pending';
    final service = (rental?.listingType ?? booking?.listingType) == 'service';
    final paid = booking?.paymentStatus == 'authorized' ||
        booking?.paymentStatus == 'captured';
    final start = rental?.start ?? booking?.start;
    final date = start == null ? 'the booked day' : rentalDay(start);
    final steps = service
        ? const [
            'Request & demo payment',
            'Owner approval',
            'Service in progress',
            'Review completed service',
            'Completed'
          ]
        : const [
            'Request & demo payment',
            'Owner approval',
            'Collection or delivery',
            'Rental in progress',
            'Return & inspection',
            'Completed'
          ];
    if (['cancelled', 'rejected', 'expired'].contains(status)) {
      if (status == 'expired' && rental?.expiryReason == 'not_collected') {
        return RentalJourney(
            'Expired — item not collected',
            'The booked dates ended without a recorded handover. No rental started. Check payment details for the released demo hold.',
            -1,
            steps,
            paused: true);
      }
      return RentalJourney(
          status == 'rejected'
              ? 'Request declined'
              : status == 'expired'
                  ? 'Request expired'
                  : 'Booking cancelled',
          'This booking will not continue. Check your payment details for any refund update.',
          -1,
          steps,
          paused: true);
    }
    if (status == 'disputed') {
      return RentalJourney(
          'Issue under review',
          'Open the case to see what information is needed. An administrator will review both sides before deciding.',
          rental?.returnSubmission != null
              ? 4
              : rental?.awaitingReceipt == true
                  ? 2
                  : rental?.handover != null
                      ? 3
                      : 1,
          steps,
          paused: true);
    }
    if (status == 'completed') {
      return RentalJourney(
          'Completed',
          'The ${service ? 'service' : 'rental'} is complete. You can review your agreement and leave feedback.',
          steps.length,
          steps);
    }
    if (status == 'return_submitted' || status == 'completion_pending') {
      return RentalJourney(
          service
              ? 'Waiting for completion review'
              : 'Return awaiting inspection',
          service
              ? 'The renter checks the delivered service and confirms completion, or reports a problem.'
              : owner
                  ? 'Compare the return photos with your handover record. Inspect the item before confirming its return.'
                  : 'The Owner will inspect the returned item. You can still view the handover photos or report a problem.',
          steps.length - 2,
          steps);
    }
    if (['active', 'overdue'].contains(status)) {
      return RentalJourney(
          service
              ? 'Service in progress'
              : status == 'overdue'
                  ? 'Return overdue'
                  : 'Rental in progress',
          service
              ? 'The Owner marks the service delivered, then the renter confirms completion.'
              : owner
                  ? 'Keep the handover photos. Inspect the item with the renter when it is returned.'
                  : 'Keep the item safe. Add return photos when you return it${rental?.end == null ? '.' : ' by ${rentalDay(rental!.end!)}.'}',
          service ? 2 : 3,
          steps);
    }
    if (status == 'scheduled' || status == 'approved') {
      if (!service && rental?.awaitingReceipt == true) {
        final review = rental!.handover!.reviewNeededAt != null ||
            rental.end != null &&
                calendarDate(rental.end!)
                    .isBefore(malaysiaCalendarToday(now: now));
        return RentalJourney(
            review
                ? 'Handover needs review'
                : rental.handover!.receiptStatus == 'processing'
                    ? 'Confirming item receipt'
                    : owner
                        ? 'Waiting for renter confirmation'
                        : 'Review your handover',
            review
                ? 'The booked dates ended without completed receipt confirmation. Report an issue or contact support. No rental has started.'
                : owner
                    ? 'Your condition record has been sent. The rental starts after the renter confirms receipt.'
                    : 'Review the Owner’s condition photos. Confirm only when you have received the item, or report an issue.',
            2,
            steps);
      }
      final future = start != null &&
          calendarDate(start).isAfter(malaysiaCalendarToday(now: now));
      return RentalJourney(
          future
              ? 'Approved \u2014 waiting for $date'
              : service
                  ? 'Ready for the service'
                  : 'Ready for collection or delivery',
          service
              ? 'The service is scheduled for $date. Agree the arrangements with the Owner; approval does not mean the service has started.'
              : owner
                  ? 'Prepare the item for $date. Record its actual condition and photos before handover. Confirm handover only when you give it to the renter.'
                  : 'Your dates are approved. Wait until $date and arrange collection or delivery with the Owner. Check the item and the Owner’s condition photos together before accepting it.',
          2,
          steps);
    }
    return RentalJourney(
        paid ? 'Waiting for Owner approval' : 'Awaiting payment',
        paid
            ? 'The request is paid but the Owner still needs to approve it. Pending requests do not reserve dates.'
            : owner
                ? 'The renter needs to finish demo payment before you can approve this request.'
                : 'Complete payment within 10 minutes to send your request for Owner approval.',
        paid ? 1 : 0,
        steps);
  }
}

class RentalProgressPanel extends StatelessWidget {
  const RentalProgressPanel(
      {super.key,
      this.booking,
      this.rental,
      this.owner = false,
      this.showSummary = true});
  final Booking? booking;
  final Rental? rental;
  final bool owner, showSummary;
  @override
  Widget build(BuildContext context) {
    final journey =
        RentalJourney.forRecord(booking: booking, rental: rental, owner: owner);
    // Unpaid checkouts are not yet rental requests: no step rail or photo history.
    if (booking?.paymentStatus == 'unpaid') {
      return const SizedBox.shrink();
    }
    return Container(
        margin: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
            color: AppColors.blueSurface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border)),
        child: Material(
            type: MaterialType.transparency,
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (showSummary)
                Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                    child: Text(journey.title,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700))),
              if (showSummary)
                Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(journey.next)),
              Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: RentalProgressRail(
                      journey: journey,
                      service: (rental?.listingType ?? booking?.listingType) ==
                          'service')),
              ExpansionTile(
                  title: Text(
                      (rental?.listingType ?? booking?.listingType) == 'service'
                          ? 'See booking progress'
                          : 'Return record'),
                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  expandedCrossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if ((rental?.listingType ?? booking?.listingType) !=
                        'service') ...[
                      const Divider(height: 24),
                      RentalConditionSection(
                          title: 'At return', record: rental?.returnSubmission),
                      const SizedBox(height: 12),
                      const Text(
                          'Photos support a fair review for both parties. They do not automatically prove who caused damage.',
                          style: TextStyle(color: AppColors.secondaryText)),
                    ],
                  ]),
            ])));
  }
}

class RentalConditionSection extends StatelessWidget {
  const RentalConditionSection({super.key, required this.title, this.record});
  final String title;
  final RentalConditionRecord? record;
  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 6),
        if (record == null)
          const Text('No condition record yet.')
        else ...[
          Text(record!.condition.isEmpty
              ? 'Condition not recorded'
              : record!.condition),
          Text(rentalEventTime(record!.recordedAt),
              style: const TextStyle(color: AppColors.secondaryText)),
          if (record!.notes.isNotEmpty)
            Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(record!.notes)),
          for (var i = 0; i < record!.photos.length; i++)
            PhotoAttachmentTile(
                reference: record!.photos[i], label: '$title photo ${i + 1}'),
          if (record!.photos.isEmpty)
            const Text('No photos were saved for this older record.'),
        ],
      ]);
}

class RentalProgressRail extends StatefulWidget {
  const RentalProgressRail(
      {super.key, required this.journey, this.service = false});
  final RentalJourney journey;
  final bool service;
  @override
  State<RentalProgressRail> createState() => _RentalProgressRailState();
}

class _RentalProgressRailState extends State<RentalProgressRail> {
  final scroll = ScrollController();
  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, constraints) {
        final labels = widget.service
            ? const [
                'Request',
                'Owner approval',
                'Service',
                'Review',
                'Completed'
              ]
            : const [
                'Request',
                'Owner approval',
                'Handover',
                'Renting',
                'Return',
                'Completed'
              ];
        final icons = widget.service
            ? const [
                Icons.receipt_long_outlined,
                Icons.task_alt,
                Icons.work_outline,
                Icons.rate_review_outlined,
                Icons.verified_outlined
              ]
            : const [
                Icons.receipt_long_outlined,
                Icons.task_alt,
                Icons.inventory_2_outlined,
                Icons.event_available_outlined,
                Icons.assignment_return_outlined,
                Icons.verified_outlined
              ];
        final scale = MediaQuery.textScalerOf(context).scale(1);
        final cell = (constraints.maxWidth / labels.length)
            .clamp(104.0 * scale.clamp(1, 1.6), 180.0);
        final overflow = cell * labels.length > constraints.maxWidth + 1;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !scroll.hasClients) return;
          final offset =
              (widget.journey.stage.clamp(0, labels.length - 1) * cell -
                      (constraints.maxWidth - cell) / 2)
                  .clamp(0.0, scroll.position.maxScrollExtent);
          // Retain manual scrolling on rebuild; move only when the saved stage changes.
          if (_lastStage != widget.journey.stage) {
            scroll.jumpTo(offset);
            _lastStage = widget.journey.stage;
          }
        });
        return Column(children: [
          SingleChildScrollView(
              controller: scroll,
              scrollDirection: Axis.horizontal,
              child:
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (var i = 0; i < labels.length; i++)
                  SizedBox(
                      width: cell,
                      child: Semantics(
                          label:
                              '${widget.journey.steps[i]}: ${i < widget.journey.stage ? 'finished' : i == widget.journey.stage ? widget.journey.paused ? 'paused' : 'current step' : 'not reached'}',
                          child: Column(children: [
                            Row(children: [
                              Expanded(
                                  child: Container(
                                      height: 2,
                                      color: i == 0
                                          ? Colors.transparent
                                          : i <= widget.journey.stage
                                              ? AppColors.primary
                                              : AppColors.border)),
                              Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: i <= widget.journey.stage
                                          ? widget.journey.paused &&
                                                  i == widget.journey.stage
                                              ? AppColors.warning
                                                  .withValues(alpha: .12)
                                              : AppColors.primaryLight
                                          : AppColors.background,
                                      border: Border.all(
                                          color: i <= widget.journey.stage
                                              ? AppColors.primary
                                              : AppColors.border,
                                          width: i == widget.journey.stage
                                              ? 2
                                              : 1)),
                                  child: Icon(icons[i],
                                      size: 23,
                                      color: i <= widget.journey.stage
                                          ? AppColors.primaryDark
                                          : AppColors.secondaryText)),
                              Expanded(
                                  child: Container(
                                      height: 2,
                                      color: i == labels.length - 1
                                          ? Colors.transparent
                                          : i < widget.journey.stage
                                              ? AppColors.primary
                                              : AppColors.border)),
                            ]),
                            const SizedBox(height: 8),
                            Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 8),
                                child: Text(labels[i],
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                        fontWeight: i == widget.journey.stage
                                            ? FontWeight.w700
                                            : FontWeight.w500,
                                        color: i <= widget.journey.stage
                                            ? AppColors.primaryDark
                                            : AppColors.secondaryText))),
                          ]))),
              ])),
          if (overflow)
            const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('Swipe to see all steps',
                    style: TextStyle(
                        fontSize: 12, color: AppColors.secondaryText))),
        ]);
      });
  int? _lastStage;
}

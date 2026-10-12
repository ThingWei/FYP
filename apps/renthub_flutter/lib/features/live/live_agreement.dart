import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/booking/checkout_models.dart';
import '../../core/network/user_facing_error.dart';
import '../../shared/models/domain_models.dart';
import '../renter/booking/booking_flow.dart' show formatDateRange;
import 'live_authenticated_page.dart';
import 'live_booking_charges.dart';
import 'live_renthub_controller.dart';

String agreementStatusLabel(Rental rental) =>
    rental.blockchainStatus == 'confirmed'
        ? 'Rental record saved'
        : 'Supporting record unavailable';
Future<AgreementTerms?> showAgreementTerms(
  BuildContext context, {
  required String listingTitle,
  required String dateRange,
  required String total,
  String listingType = 'physical',
}) =>
    Navigator.push<AgreementTerms>(
        context,
        MaterialPageRoute(
            builder: (_) => LiveAuthenticatedPage(
                child: LiveAgreementPage(
                    listingType: listingType,
                    previewTitle: listingTitle,
                    previewDates: dateRange,
                    previewTotal: total))));
Future<void> showBookingAgreement(
    BuildContext context, String bookingId) async {
  await Navigator.push<void>(
      context,
      MaterialPageRoute(
          builder: (_) => LiveAuthenticatedPage(
              child: LiveAgreementPage(bookingId: bookingId))));
}

Future<void> showBlockchainAgreement(BuildContext context, Rental rental,
        {Booking? booking}) =>
    showBookingAgreement(context, rental.bookingId);

class BookingAgreementDocument {
  const BookingAgreementDocument(
      this.booking,
      this.terms,
      this.renterAcceptedAt,
      this.ownerApprovedAt,
      this.recordStatus,
      this.demonstrationNetwork);
  final Booking booking;
  final AgreementTerms? terms;
  final DateTime? renterAcceptedAt, ownerApprovedAt;
  final String recordStatus;
  final bool demonstrationNetwork;
  factory BookingAgreementDocument.fromJson(Map<String, dynamic> row) {
    if (row['booking'] is! Map ||
        row['history'] is! Map ||
        row['record'] is! Map) {
      throw const FormatException('Invalid agreement');
    }
    final history = row['history'] as Map, record = row['record'] as Map;
    DateTime? date(dynamic value) =>
        value == null ? null : DateTime.parse(value as String);
    return BookingAgreementDocument(
        Booking.fromJson(Map<String, dynamic>.from(row['booking'])),
        row['terms'] == null
            ? null
            : AgreementTerms.fromJson(Map<String, dynamic>.from(row['terms'])),
        date(history['renterAcceptedAt']),
        date(history['ownerApprovedAt']),
        record['status'] as String? ?? 'unavailable',
        record['demonstrationNetwork'] == true);
  }
}

class LiveAgreementPage extends StatefulWidget {
  const LiveAgreementPage(
      {super.key,
      this.bookingId,
      this.listingType = 'physical',
      this.previewTitle = '',
      this.previewDates = '',
      this.previewTotal = ''});
  final String? bookingId;
  final String listingType, previewTitle, previewDates, previewTotal;
  @override
  State<LiveAgreementPage> createState() => _LiveAgreementPageState();
}

class _LiveAgreementPageState extends State<LiveAgreementPage> {
  AgreementTerms? terms;
  BookingAgreementDocument? document;
  bool loading = true;
  String? error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final api = context.read<LiveRentHubController>().api;
      if (widget.bookingId == null) {
        final value = AgreementTerms.fromJson(Map<String,
            dynamic>.from(await api.request('GET',
                '/bookings/agreement-terms?listingType=${widget.listingType}')
            as Map));
        if (mounted) setState(() => terms = value);
      } else {
        final value = BookingAgreementDocument.fromJson(
            Map<String, dynamic>.from(await api.request(
                'GET', '/bookings/${widget.bookingId}/agreement') as Map));
        if (mounted) {
          setState(() {
            document = value;
            terms = value.terms;
          });
        }
      }
    } catch (exception) {
      if (mounted) setState(() => error = friendlyError(exception));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  String date(DateTime? value, String missing) {
    if (value == null) return missing;
    final local = value.toLocal();
    return '${local.day}/${local.month}/${local.year} at ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  Widget section(String title, List<Widget> children) => Card(
      child: Padding(
          padding: const EdgeInsets.all(20),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            ...children
          ])));
  @override
  Widget build(BuildContext context) {
    final booking = document?.booking;
    final service = (booking?.listingType ?? widget.listingType) == 'service';
    final status = document?.recordStatus;
    final recordLabel = switch (status) {
      'saved' => 'Rental record saved',
      'awaiting_approval' => 'Record available after Owner approval',
      'booking_record' => 'Service booking record',
      'not_created' => 'No supporting rental record was created',
      _ => 'Supporting record unavailable',
    };
    return Scaffold(
        appBar: AppBar(
            title: Text(service ? 'Service agreement' : 'Rental agreement')),
        body: SafeArea(
            child: Center(
                child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: loading
                        ? const Center(child: CircularProgressIndicator())
                        : error != null
                            ? Padding(
                                padding: const EdgeInsets.all(24),
                                child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(error!),
                                      const SizedBox(height: 16),
                                      OutlinedButton(
                                          onPressed: _load,
                                          child: const Text('Retry'))
                                    ]))
                            : ListView(
                                padding: const EdgeInsets.all(16),
                                children: [
                                    section('RentHub', [
                                      Text(
                                          service
                                              ? 'Service booking agreement'
                                              : 'Rental agreement',
                                          style: Theme.of(context)
                                              .textTheme
                                              .headlineSmall),
                                      const SizedBox(height: 8),
                                      const Text(
                                          'Your booking details, responsibilities and recorded acceptance, together in one place.'),
                                      if (booking != null) ...[
                                        const SizedBox(height: 12),
                                        Text('Booking ${booking.id}'),
                                        Text('Status: ${booking.status}')
                                      ],
                                      if (booking == null)
                                        const Text(
                                            'Review before submitting. Final charges are shown at checkout; Owner approval is still required.'),
                                    ]),
                                    section('Booking details', [
                                      Text(
                                          booking?.listingTitle ??
                                              widget.previewTitle,
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleLarge),
                                      const SizedBox(height: 8),
                                      Text(booking == null
                                          ? widget.previewDates
                                          : formatDateRange(
                                              booking.start, booking.end)),
                                      if (service && booking != null)
                                        Text(
                                            'Scheduled: ${date(booking.start, '')} to ${date(booking.end, '')}'),
                                      if (booking == null)
                                        Text(widget.previewTotal),
                                      if (booking != null) ...[
                                        const SizedBox(height: 12),
                                        Text(
                                            'Renter: ${booking.renterName.isEmpty ? 'Historical name unavailable' : booking.renterName}'),
                                        Text(
                                            'Owner: ${booking.ownerName.isEmpty ? 'Historical name unavailable' : booking.ownerName}'),
                                        Text(service
                                            ? 'Venue: ${booking.serviceVenue ?? 'Available when permitted by booking status'}'
                                            : 'Arrangement: ${booking.fulfilmentMethod == 'owner_delivery' ? 'Owner delivery' : 'Pickup'}'),
                                        if (!service)
                                          Text(booking.pickupLocation == null
                                              ? 'Exact pickup details are available when permitted by booking status.'
                                              : 'Pickup: ${booking.pickupLocation!.label}'),
                                        if (booking.deliveryLocation != null)
                                          Text(
                                              'Delivery: ${booking.deliveryLocation!.label}'),
                                        const SizedBox(height: 16),
                                        LiveBookingCharges(booking: booking),
                                      ],
                                    ]),
                                    section('Terms and responsibilities', [
                                      if (terms == null)
                                        const Text(
                                            'The accepted wording is unavailable for this historical record. We will not substitute newer terms.'),
                                      for (final term in terms?.sections ??
                                          <AgreementSection>[]) ...[
                                        Text(term.title,
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w700)),
                                        const SizedBox(height: 4),
                                        Text(term.detail),
                                        const SizedBox(height: 20),
                                      ],
                                    ]),
                                    if (document != null)
                                      section('Acceptance history', [
                                        Text(
                                            'Renter accepted: ${date(document!.renterAcceptedAt, 'No acceptance time recorded')}'),
                                        const SizedBox(height: 12),
                                        Text(
                                            'Owner approved: ${date(document!.ownerApprovedAt, 'Not recorded')}'),
                                        const SizedBox(height: 12),
                                        const Text(
                                            'These are recorded RentHub actions, not handwritten signatures.'),
                                      ]),
                                    if (document != null)
                                      section('Agreement record', [
                                        Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Icon(status == 'saved' ||
                                                      status == 'booking_record'
                                                  ? Icons.receipt_long_outlined
                                                  : Icons.info_outline),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                  child: Text(recordLabel,
                                                      style: const TextStyle(
                                                          fontWeight: FontWeight
                                                              .w700))),
                                            ]),
                                        const SizedBox(height: 12),
                                        Text(service
                                            ? 'RentHub keeps this service booking and its recorded acceptance for review.'
                                            : 'RentHub records rental amounts and status changes to support later review. This does not store or verify the full agreement text.'),
                                        if (document!.demonstrationNetwork) ...[
                                          const SizedBox(height: 8),
                                          const Text(
                                              'RentHub’s local demonstration network uses test funds, not real money.')
                                        ],
                                        if (status == 'unavailable') ...[
                                          const SizedBox(height: 8),
                                          const Text(
                                              'The booking status shown above is separate from this supporting record. Contact support if you need help.')
                                        ],
                                      ]),
                                    if (widget.bookingId == null)
                                      FilledButton(
                                          onPressed: terms == null
                                              ? null
                                              : () =>
                                                  Navigator.pop(context, terms),
                                          child: const Text(
                                              'I have reviewed these terms')),
                                    if (widget.bookingId != null)
                                      OutlinedButton(
                                          onPressed: () =>
                                              Navigator.pop(context),
                                          child: const Text('Close agreement')),
                                  ])))));
  }
}

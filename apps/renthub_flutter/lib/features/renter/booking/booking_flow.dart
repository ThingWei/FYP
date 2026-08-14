import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../modules/booking/controllers/booking_controller.dart';
import '../../../modules/payment/controllers/payment_controller.dart';
import '../../../modules/payment/repositories/payment_repository.dart';
import '../../../shared/models/domain_models.dart';
import '../../../shared/widgets/account_components.dart';
import '../../../shared/widgets/renthub_components.dart';

enum FulfilmentMethod { pickup, delivery }

class UnavailableDateRange {
  const UnavailableDateRange(this.start, this.end);

  final DateTime start;
  final DateTime end;

  bool overlaps(DateTime candidateStart, DateTime candidateEnd) =>
      !candidateEnd.isBefore(start) && !candidateStart.isAfter(end);
}

class BookingPolicy {
  const BookingPolicy({
    required this.pickupLocation,
    required this.deposit,
    required this.damageWaiver,
    required this.deliveryFee,
    required this.maxQuantity,
    required this.unavailableDates,
    this.deliveryAvailable = true,
  });

  final String pickupLocation;
  final double deposit;
  final double damageWaiver;
  final double deliveryFee;
  final int maxQuantity;
  final List<UnavailableDateRange> unavailableDates;
  final bool deliveryAvailable;
}

abstract final class BookingPolicies {
  static BookingPolicy forListing(Listing listing, {DateTime? today}) {
    final base = dateOnly(today ?? DateTime.now());
    return BookingPolicy(
      pickupLocation: listing.id == 'l-camera'
          ? 'Lot 10, Bukit Bintang, Kuala Lumpur'
          : listing.location,
      deposit: listing.id == 'l-camera' ? 300 : 200,
      damageWaiver: listing.id == 'l-camera' ? 15 : 10,
      deliveryFee: 18,
      maxQuantity: listing.id == 'l-camera' ? 2 : 1,
      unavailableDates: [
        UnavailableDateRange(
          base.add(const Duration(days: 12)),
          base.add(const Duration(days: 14)),
        ),
      ],
    );
  }
}

DateTime dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

String formatMoney(double amount) => 'RM ${amount.toStringAsFixed(2)}';

String formatShortDate(DateTime date) {
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
    'Dec',
  ];
  return '${date.day} ${months[date.month - 1]} ${date.year}';
}

String formatDateRange(DateTime start, DateTime end) =>
    '${formatShortDate(start)} – ${formatShortDate(end)}';

class BookingDraft extends ChangeNotifier {
  BookingDraft({
    required this.listing,
    BookingPolicy? policy,
    DateTime? today,
  }) : policy = policy ?? BookingPolicies.forListing(listing, today: today) {
    final base = dateOnly(today ?? DateTime.now());
    startDate = base.add(const Duration(days: 7));
    endDate = base.add(const Duration(days: 9));
    _validateDates();
  }

  final Listing listing;
  final BookingPolicy policy;

  DateTime? startDate;
  DateTime? endDate;
  FulfilmentMethod fulfilment = FulfilmentMethod.pickup;
  String deliveryLocation = '12 Jalan SS 2/72, Petaling Jaya, Selangor';
  String rentalPurpose = '';
  int quantity = 1;
  bool damageWaiverSelected = true;
  bool agreementAccepted = false;
  bool availabilityValid = false;
  String? dateError;
  String? authorizationId;
  Booking? createdBooking;
  String? submissionError;
  Future<Booking?>? _submission;

  String get fulfilmentLabel =>
      fulfilment == FulfilmentMethod.pickup ? 'Self Pickup' : 'Owner Delivery';

  String get fulfilmentLocation => fulfilment == FulfilmentMethod.pickup
      ? policy.pickupLocation
      : deliveryLocation.trim();

  int get rentalDays {
    if (startDate == null || endDate == null || endDate!.isBefore(startDate!)) {
      return 0;
    }
    return endDate!.difference(startDate!).inDays + 1;
  }

  double get rentalSubtotal => listing.dailyPrice * rentalDays * quantity;
  double get waiverAmount =>
      damageWaiverSelected ? policy.damageWaiver * quantity : 0;
  double get deliveryAmount =>
      fulfilment == FulfilmentMethod.delivery ? policy.deliveryFee : 0;
  double get total =>
      rentalSubtotal + waiverAmount + deliveryAmount + policy.deposit;

  bool get canReview =>
      availabilityValid &&
      startDate != null &&
      endDate != null &&
      fulfilmentLocation.isNotEmpty &&
      quantity >= 1 &&
      quantity <= policy.maxQuantity;

  bool get submissionInProgress => _submission != null;

  void setStartDate(DateTime value) {
    startDate = dateOnly(value);
    _changedBookingTerms();
  }

  void setEndDate(DateTime value) {
    endDate = dateOnly(value);
    _changedBookingTerms();
  }

  void setFulfilment(FulfilmentMethod value) {
    if (value == FulfilmentMethod.delivery && !policy.deliveryAvailable) return;
    fulfilment = value;
    _changedBookingTerms(validateDates: false);
  }

  void setDeliveryLocation(String value) {
    deliveryLocation = value;
    _changedBookingTerms(validateDates: false);
  }

  void setRentalPurpose(String value) {
    rentalPurpose = value;
    notifyListeners();
  }

  void setQuantity(int value) {
    quantity = value.clamp(1, policy.maxQuantity);
    _changedBookingTerms(validateDates: false);
  }

  void setDamageWaiver(bool value) {
    damageWaiverSelected = value;
    _changedBookingTerms(validateDates: false);
  }

  void setAgreementAccepted(bool value) {
    agreementAccepted = value;
    notifyListeners();
  }

  void _changedBookingTerms({bool validateDates = true}) {
    agreementAccepted = false;
    authorizationId = null;
    submissionError = null;
    if (validateDates) _validateDates();
    notifyListeners();
  }

  bool validateAvailability() {
    _validateDates();
    notifyListeners();
    return availabilityValid;
  }

  void _validateDates() {
    final start = startDate;
    final end = endDate;
    availabilityValid = false;
    if (start == null || end == null) {
      dateError = 'Select both a rental start and end date.';
      return;
    }
    if (end.isBefore(start)) {
      dateError = 'End date must be on or after the start date.';
      return;
    }
    for (final blocked in policy.unavailableDates) {
      if (blocked.overlaps(start, end)) {
        dateError =
            'Unavailable: ${formatDateRange(blocked.start, blocked.end)}. Choose another range.';
        return;
      }
    }
    dateError = null;
    availabilityValid = true;
  }

  void markAuthorized(String id) {
    authorizationId = id;
    submissionError = null;
    notifyListeners();
  }

  Future<Booking?> createPending(BookingController controller) {
    if (createdBooking != null) return Future.value(createdBooking);
    if (_submission != null) return _submission!;
    if (authorizationId == null) {
      submissionError =
          'Complete the local simulated authorization before submitting.';
      notifyListeners();
      return Future.value(null);
    }

    _submission = () async {
      submissionError = null;
      await controller.create(listing.id, startDate!, endDate!);
      if (controller.error != null) {
        submissionError = controller.error;
        notifyListeners();
        return null;
      }
      final booking = controller.latest;
      if (booking == null || booking.status.toLowerCase() != 'pending') {
        submissionError = 'The demo request could not be created as Pending.';
        notifyListeners();
        return null;
      }
      createdBooking = booking;
      notifyListeners();
      return booking;
    }()
        .whenComplete(() {
      _submission = null;
      notifyListeners();
    });
    return _submission!;
  }
}

class BookingDetailsPage extends StatefulWidget {
  const BookingDetailsPage({
    super.key,
    required this.draft,
    required this.onOpenBookings,
    required this.onReturnHome,
  });

  final BookingDraft draft;
  final VoidCallback onOpenBookings;
  final VoidCallback onReturnHome;

  @override
  State<BookingDetailsPage> createState() => _BookingDetailsPageState();
}

class _BookingDetailsPageState extends State<BookingDetailsPage> {
  late final TextEditingController purpose;
  late final TextEditingController deliveryAddress;

  @override
  void initState() {
    super.initState();
    purpose = TextEditingController(text: widget.draft.rentalPurpose);
    deliveryAddress =
        TextEditingController(text: widget.draft.deliveryLocation);
  }

  @override
  void dispose() {
    purpose.dispose();
    deliveryAddress.dispose();
    super.dispose();
  }

  Future<void> _pickStartDate() async {
    final now = dateOnly(DateTime.now());
    final value = await showDatePicker(
      context: context,
      initialDate: widget.draft.startDate ?? now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      helpText: 'Select rental start date',
    );
    if (value != null) widget.draft.setStartDate(value);
  }

  Future<void> _pickEndDate() async {
    final now = dateOnly(DateTime.now());
    final value = await showDatePicker(
      context: context,
      initialDate: widget.draft.endDate ?? widget.draft.startDate ?? now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      helpText: 'Select rental end date',
    );
    if (value != null) widget.draft.setEndDate(value);
  }

  void _review() {
    if (!widget.draft.validateAvailability()) return;
    Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => AgreementReviewPage(
          draft: widget.draft,
          onOpenBookings: widget.onOpenBookings,
          onReturnHome: widget.onReturnHome,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: widget.draft,
        builder: (context, _) {
          final draft = widget.draft;
          return Scaffold(
            appBar: const _StepAppBar(step: 1, title: 'Booking Details'),
            bottomNavigationBar: SafeArea(
              child: Container(
                color: AppColors.background,
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => showMockSuccess(
                          context,
                          'Draft saved for this session',
                        ),
                        child: const Text('Save Draft'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: FilledButton(
                        key: const Key('review-agreement-button'),
                        onPressed: draft.canReview ? _review : null,
                        child: const Text('Review Agreement'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            body: SafeArea(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                children: [
                  _ListingSummary(draft: draft),
                  const SizedBox(height: 20),
                  _SectionTitle(
                    title: 'Rental Period',
                    trailing: draft.rentalDays > 0
                        ? '${draft.rentalDays} rental days'
                        : null,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _SelectionTile(
                          key: const Key('start-date-field'),
                          label: 'PICKUP DATE',
                          value: draft.startDate == null
                              ? 'Select date'
                              : formatShortDate(draft.startDate!),
                          icon: Icons.calendar_month_outlined,
                          onTap: _pickStartDate,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _SelectionTile(
                          key: const Key('end-date-field'),
                          label: 'RETURN DATE',
                          value: draft.endDate == null
                              ? 'Select date'
                              : formatShortDate(draft.endDate!),
                          icon: Icons.calendar_month_outlined,
                          onTap: _pickEndDate,
                        ),
                      ),
                    ],
                  ),
                  if (draft.dateError != null) ...[
                    const SizedBox(height: 8),
                    _InlineMessage(
                      icon: Icons.error_outline,
                      message: draft.dateError!,
                      color: AppColors.error,
                    ),
                  ] else ...[
                    const SizedBox(height: 8),
                    const _InlineMessage(
                      icon: Icons.check_circle_outline,
                      message: 'Selected dates are available',
                      color: AppColors.success,
                    ),
                  ],
                  const SizedBox(height: 20),
                  const _SectionTitle(
                    title: 'Rental Purpose',
                    trailing: 'Optional',
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: purpose,
                    minLines: 2,
                    maxLines: 3,
                    onChanged: draft.setRentalPurpose,
                    decoration: const InputDecoration(
                      hintText:
                          'Briefly explain what you will use the item for.',
                    ),
                  ),
                  const SizedBox(height: 20),
                  const _SectionTitle(title: 'Fulfilment Method'),
                  const SizedBox(height: 8),
                  SegmentedButton<FulfilmentMethod>(
                    segments: const [
                      ButtonSegment(
                        value: FulfilmentMethod.pickup,
                        label: Text('Self Pickup'),
                        icon: Icon(Icons.storefront_outlined),
                      ),
                      ButtonSegment(
                        value: FulfilmentMethod.delivery,
                        label: Text('Delivery'),
                        icon: Icon(Icons.local_shipping_outlined),
                      ),
                    ],
                    selected: {draft.fulfilment},
                    onSelectionChanged: (value) =>
                        draft.setFulfilment(value.first),
                    showSelectedIcon: false,
                  ),
                  const SizedBox(height: 12),
                  if (draft.fulfilment == FulfilmentMethod.pickup)
                    _LocationCard(
                      icon: Icons.storefront_outlined,
                      title: 'Self Pickup Location',
                      value: draft.policy.pickupLocation,
                      helper: 'VIEW MAP',
                    )
                  else
                    AccountCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'DELIVERY LOCATION',
                            style: TextStyle(
                              color: AppColors.primaryDark,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            key: const Key('delivery-location-field'),
                            controller: deliveryAddress,
                            onChanged: draft.setDeliveryLocation,
                            decoration: const InputDecoration(
                              prefixIcon: Icon(Icons.location_on_outlined),
                              labelText: 'Pickup/delivery location',
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 12),
                  if (draft.policy.maxQuantity > 1)
                    AccountCard(
                      child: Row(
                        children: [
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Quantity',
                                  style: TextStyle(fontWeight: FontWeight.w700),
                                ),
                                Text(
                                  'Subject to available inventory',
                                  style: TextStyle(
                                    color: AppColors.secondaryText,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Decrease quantity',
                            onPressed: draft.quantity > 1
                                ? () => draft.setQuantity(draft.quantity - 1)
                                : null,
                            icon: const Icon(Icons.remove_circle_outline),
                          ),
                          Text(
                            '${draft.quantity}',
                            key: const Key('quantity-value'),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          IconButton(
                            tooltip: 'Increase quantity',
                            onPressed: draft.quantity < draft.policy.maxQuantity
                                ? () => draft.setQuantity(draft.quantity + 1)
                                : null,
                            icon: const Icon(Icons.add_circle_outline),
                          ),
                        ],
                      ),
                    )
                  else
                    const _LocationCard(
                      icon: Icons.inventory_2_outlined,
                      title: 'Quantity',
                      value: '1 item',
                      helper: 'SINGLE UNIT',
                    ),
                  const SizedBox(height: 12),
                  AccountCard(
                    child: SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Damage Waiver'),
                      subtitle: Text(
                        '${formatMoney(draft.policy.damageWaiver)} · Optional protection during your rental period',
                      ),
                      value: draft.damageWaiverSelected,
                      onChanged: draft.setDamageWaiver,
                    ),
                  ),
                  const SizedBox(height: 12),
                  BookingPriceBreakdown(draft: draft),
                  const SizedBox(height: 12),
                  const Text(
                    'Protected by the RentHub digital rental agreement',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.secondaryText,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
}

class AgreementReviewPage extends StatelessWidget {
  const AgreementReviewPage({
    super.key,
    required this.draft,
    required this.onOpenBookings,
    required this.onReturnHome,
  });

  final BookingDraft draft;
  final VoidCallback onOpenBookings;
  final VoidCallback onReturnHome;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: draft,
        builder: (context, _) => Scaffold(
          appBar: const _StepAppBar(step: 2, title: 'Agreement'),
          bottomNavigationBar: SafeArea(
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              color: AppColors.background,
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Back'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      key: const Key('proceed-payment-button'),
                      onPressed: draft.agreementAccepted && draft.canReview
                          ? () => Navigator.push<void>(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => SimulatedPaymentPage(
                                    draft: draft,
                                    onOpenBookings: onOpenBookings,
                                    onReturnHome: onReturnHome,
                                  ),
                                ),
                              )
                          : null,
                      child: const Text('Proceed to Demo Payment'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                _ListingSummary(draft: draft),
                const SizedBox(height: 16),
                AccountCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Rental Agreement',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ),
                          const Spacer(),
                          const Icon(
                            Icons.gavel_outlined,
                            color: AppColors.primaryDark,
                          ),
                        ],
                      ),
                      const Divider(height: 24),
                      const Text(
                        'AGREEMENT REFERENCE',
                        style: _labelStyle,
                      ),
                      const SizedBox(height: 4),
                      const _MutedBox(child: Text('RH-AGR-2026-09142')),
                      const SizedBox(height: 16),
                      const Text('PARTIES', style: _labelStyle),
                      const SizedBox(height: 4),
                      _MutedBox(
                        child: Row(
                          children: [
                            Expanded(
                              child: Text('${draft.listing.ownerName}\nOwner'),
                            ),
                            const Icon(Icons.swap_horiz),
                            const Expanded(
                              child: Text(
                                'Nur Izzati\nRenter',
                                textAlign: TextAlign.end,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text('FULFILMENT', style: _labelStyle),
                      const SizedBox(height: 4),
                      _MutedBox(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.location_on_outlined,
                              color: AppColors.primaryDark,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${draft.fulfilmentLabel}\n${draft.fulfilmentLocation}',
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text('TERMS & CONDITIONS', style: _labelStyle),
                      const SizedBox(height: 4),
                      Text(
                        'Duration: ${draft.rentalDays} days · Quantity: ${draft.quantity}\nRefundable deposit: ${formatMoney(draft.policy.deposit)}',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                BookingPriceBreakdown(draft: draft),
                const SizedBox(height: 12),
                Material(
                  color: const Color(0xFFECFDF5),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: const BorderSide(color: Color(0xFFBBF7D0)),
                  ),
                  child: CheckboxListTile(
                    key: const Key('agreement-checkbox'),
                    value: draft.agreementAccepted,
                    onChanged: (value) =>
                        draft.setAgreementAccepted(value ?? false),
                    controlAffinity: ListTileControlAffinity.leading,
                    title: const Text(
                      'I accept this rental agreement and confirm the booking details above.',
                    ),
                    subtitle: const Text(
                      'Prototype only: no blockchain record or external contract is created.',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

class SimulatedPaymentPage extends StatefulWidget {
  const SimulatedPaymentPage({
    super.key,
    required this.draft,
    required this.onOpenBookings,
    required this.onReturnHome,
    this.paymentController,
  });

  final BookingDraft draft;
  final VoidCallback onOpenBookings;
  final VoidCallback onReturnHome;
  final PaymentController? paymentController;

  @override
  State<SimulatedPaymentPage> createState() => _SimulatedPaymentPageState();
}

class _SimulatedPaymentPageState extends State<SimulatedPaymentPage> {
  late final PaymentController payment;
  late final bool ownsPayment;
  bool busy = false;
  String method = 'card';
  String? error;

  @override
  void initState() {
    super.initState();
    ownsPayment = widget.paymentController == null;
    payment =
        widget.paymentController ?? PaymentController(MockPaymentRepository());
  }

  @override
  void dispose() {
    if (ownsPayment) payment.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (busy || widget.draft.submissionInProgress) return;
    if (widget.draft.createdBooking != null) {
      _openSubmitted();
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });

    await Future<void>.delayed(const Duration(milliseconds: 350));
    await payment.pay(widget.draft.total);
    if (!mounted) return;
    if (payment.error != null || payment.result?['status'] != 'succeeded') {
      setState(() {
        busy = false;
        error = payment.error ?? 'The demo authorization was declined.';
      });
      return;
    }

    widget.draft.markAuthorized(
      payment.result?['id']?.toString() ?? 'simulated-authorization',
    );
    final booking = await widget.draft.createPending(
      context.read<BookingController>(),
    );
    if (!mounted) return;
    if (booking == null) {
      setState(() {
        busy = false;
        error = widget.draft.submissionError ??
            'The Pending request could not be created. Try again.';
      });
      return;
    }
    setState(() => busy = false);
    _openSubmitted();
  }

  void _openSubmitted() {
    Navigator.pushReplacement<void, void>(
      context,
      MaterialPageRoute(
        builder: (_) => BookingRequestSubmittedPage(
          draft: widget.draft,
          onOpenBookings: widget.onOpenBookings,
          onReturnHome: widget.onReturnHome,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: widget.draft,
        builder: (context, _) => Scaffold(
          appBar: const _StepAppBar(step: 3, title: 'Payment'),
          bottomNavigationBar: SafeArea(
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              color: AppColors.background,
              child: RentHubActionButton(
                label: widget.draft.createdBooking != null
                    ? 'View Submitted Request'
                    : 'Authorize ${formatMoney(widget.draft.total)}',
                icon: Icons.lock_outline,
                loading: busy,
                onPressed: _submit,
              ),
            ),
          ),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                _ListingSummary(draft: widget.draft),
                const SizedBox(height: 16),
                BookingPriceBreakdown(draft: widget.draft),
                const SizedBox(height: 16),
                Text(
                  'Payment Method',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                _PaymentMethodTile(
                  value: 'card',
                  groupValue: method,
                  title: 'Demo Card',
                  subtitle: 'Visa ···· 4242',
                  icon: Icons.credit_card,
                  onChanged: (value) => setState(() => method = value),
                ),
                const SizedBox(height: 8),
                _PaymentMethodTile(
                  value: 'fpx',
                  groupValue: method,
                  title: 'Mock FPX',
                  subtitle: 'Demo online banking',
                  icon: Icons.account_balance_outlined,
                  onChanged: (value) => setState(() => method = value),
                ),
                const SizedBox(height: 12),
                const _InlineMessage(
                  icon: Icons.info_outline,
                  message:
                      'Prototype payment only. This simulates an authorization; no real charge, bank, card, FPX session, or external payment service is used.',
                  color: AppColors.info,
                ),
                if (error != null) ...[
                  const SizedBox(height: 12),
                  _InlineMessage(
                    icon: Icons.error_outline,
                    message:
                        '$error You can retry safely; no duplicate request will be created.',
                    color: AppColors.error,
                  ),
                ],
              ],
            ),
          ),
        ),
      );
}

class BookingRequestSubmittedPage extends StatelessWidget {
  const BookingRequestSubmittedPage({
    super.key,
    required this.draft,
    required this.onOpenBookings,
    required this.onReturnHome,
  });

  final BookingDraft draft;
  final VoidCallback onOpenBookings;
  final VoidCallback onReturnHome;

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: false,
        child: Scaffold(
          bottomNavigationBar: SafeArea(
            child: Container(
              color: AppColors.background,
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RentHubActionButton(
                    label: 'View in My Bookings',
                    icon: Icons.calendar_month_outlined,
                    onPressed: onOpenBookings,
                  ),
                  const SizedBox(height: 8),
                  RentHubActionButton(
                    label: 'Return Home',
                    style: RentHubButtonStyle.secondary,
                    onPressed: onReturnHome,
                  ),
                ],
              ),
            ),
          ),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
              children: [
                Center(
                  child: CircleAvatar(
                    radius: 42,
                    backgroundColor: AppColors.background,
                    child: const Icon(
                      Icons.mark_email_read_outlined,
                      size: 48,
                      color: AppColors.success,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Booking request submitted',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                const Center(child: StatusBadge('Pending Owner Approval')),
                const SizedBox(height: 10),
                Text(
                  '${draft.listing.ownerName} must approve your request before the rental becomes active.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.secondaryText),
                ),
                const SizedBox(height: 20),
                AccountCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'REF: ${draft.createdBooking?.id ?? 'booking-pending'}',
                        style: const TextStyle(
                          color: AppColors.secondaryText,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        draft.listing.title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      _IconText(
                        icon: Icons.calendar_month_outlined,
                        text: formatDateRange(
                          draft.startDate!,
                          draft.endDate!,
                        ),
                      ),
                      _IconText(
                        icon: Icons.schedule,
                        text:
                            '${draft.rentalDays} days · Quantity ${draft.quantity}',
                      ),
                      _IconText(
                        icon: Icons.location_on_outlined,
                        text:
                            '${draft.fulfilmentLabel} · ${draft.fulfilmentLocation}',
                      ),
                      const Divider(height: 24),
                      Row(
                        children: [
                          const Expanded(child: Text('Total authorization')),
                          Text(
                            formatMoney(draft.total),
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                AccountCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: const [
                      Text(
                        'Request Status',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(height: 16),
                      _StatusStep(
                        color: AppColors.success,
                        title: 'Authorization simulated',
                        message: 'No real funds were charged or captured.',
                      ),
                      _StatusStep(
                        color: AppColors.warning,
                        title: 'Owner approval',
                        message: 'Waiting for the Owner to respond.',
                        last: true,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

class BookingPriceBreakdown extends StatelessWidget {
  const BookingPriceBreakdown({super.key, required this.draft});

  final BookingDraft draft;

  @override
  Widget build(BuildContext context) => AccountCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Price Breakdown',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const Divider(height: 20),
            _PriceRow(
              label:
                  'Rental subtotal (${draft.rentalDays} days × ${draft.quantity})',
              amount: draft.rentalSubtotal,
            ),
            if (draft.damageWaiverSelected)
              _PriceRow(label: 'Damage waiver', amount: draft.waiverAmount),
            if (draft.deliveryAmount > 0)
              _PriceRow(label: 'Delivery', amount: draft.deliveryAmount),
            _PriceRow(
              label: 'Refundable deposit',
              amount: draft.policy.deposit,
            ),
            const Divider(height: 22),
            _PriceRow(label: 'Total', amount: draft.total, bold: true),
            const SizedBox(height: 8),
            const _InlineMessage(
              icon: Icons.info_outline,
              message:
                  'The refundable deposit is included in the local demo authorization.',
              color: AppColors.info,
            ),
          ],
        ),
      );
}

class _StepAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _StepAppBar({required this.step, required this.title});

  final int step;
  final String title;

  @override
  Size get preferredSize => const Size.fromHeight(66);

  @override
  Widget build(BuildContext context) => AppBar(
        title: Column(
          children: [
            const Text(
              'RentHub',
              style: TextStyle(
                color: AppColors.primaryDark,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              'Step $step of 3 · $title',
              style: const TextStyle(
                color: AppColors.secondaryText,
                fontSize: 11,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
        centerTitle: true,
      );
}

class _ListingSummary extends StatelessWidget {
  const _ListingSummary({required this.draft});

  final BookingDraft draft;

  @override
  Widget build(BuildContext context) => AccountCard(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            Container(
              width: 68,
              height: 56,
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.photo_camera_outlined,
                color: AppColors.primaryDark,
                size: 30,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    draft.listing.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    '${formatMoney(draft.listing.dailyPrice)} / day · Qty ${draft.quantity}',
                    style: const TextStyle(
                      color: AppColors.secondaryText,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, this.trailing});

  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(
            child: Text(title, style: Theme.of(context).textTheme.titleMedium),
          ),
          if (trailing != null)
            Text(
              trailing!,
              style: const TextStyle(
                color: AppColors.primaryDark,
                fontSize: 12,
              ),
            ),
        ],
      );
}

class _SelectionTile extends StatelessWidget {
  const _SelectionTile({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: AppColors.background,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: AppColors.border),
          borderRadius: BorderRadius.circular(12),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: _labelStyle),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        value,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Icon(icon, size: 18, color: AppColors.primaryDark),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
}

class _LocationCard extends StatelessWidget {
  const _LocationCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.helper,
  });

  final IconData icon;
  final String title;
  final String value;
  final String helper;

  @override
  Widget build(BuildContext context) => AccountCard(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              backgroundColor: AppColors.primaryLight,
              child: Icon(icon, color: AppColors.primaryDark),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  Text(
                    value,
                    style: const TextStyle(color: AppColors.secondaryText),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    helper,
                    style: const TextStyle(
                      color: AppColors.primaryDark,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

class _MutedBox extends StatelessWidget {
  const _MutedBox({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(6),
        ),
        child: child,
      );
}

class _PaymentMethodTile extends StatelessWidget {
  const _PaymentMethodTile({
    required this.value,
    required this.groupValue,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onChanged,
  });

  final String value;
  final String groupValue;
  final String title;
  final String subtitle;
  final IconData icon;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final selected = value == groupValue;
    return Material(
      color: selected ? AppColors.blueSurface : AppColors.background,
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: selected ? AppColors.primary : AppColors.border,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => onChanged(value),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: selected ? AppColors.primary : AppColors.secondaryText,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: AppColors.secondaryText,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(icon, color: AppColors.primaryDark),
            ],
          ),
        ),
      ),
    );
  }
}

class _InlineMessage extends StatelessWidget {
  const _InlineMessage({
    required this.icon,
    required this.message,
    required this.color,
  });

  final IconData icon;
  final String message;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .08),
          border: Border.all(color: color.withValues(alpha: .35)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 8),
            Expanded(
                child: Text(message, style: const TextStyle(fontSize: 12))),
          ],
        ),
      );
}

class _PriceRow extends StatelessWidget {
  const _PriceRow({
    required this.label,
    required this.amount,
    this.bold = false,
  });

  final String label;
  final double amount;
  final bool bold;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(fontWeight: bold ? FontWeight.w700 : null),
              ),
            ),
            Text(
              formatMoney(amount),
              style: TextStyle(
                fontWeight: bold ? FontWeight.w800 : null,
                color: bold ? AppColors.primaryDark : null,
                fontSize: bold ? 18 : null,
              ),
            ),
          ],
        ),
      );
}

class _IconText extends StatelessWidget {
  const _IconText({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 17, color: AppColors.secondaryText),
            const SizedBox(width: 8),
            Expanded(child: Text(text)),
          ],
        ),
      );
}

class _StatusStep extends StatelessWidget {
  const _StatusStep({
    required this.color,
    required this.title,
    required this.message,
    this.last = false,
  });

  final Color color;
  final String title;
  final String message;
  final bool last;

  @override
  Widget build(BuildContext context) => IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 24,
              child: Column(
                children: [
                  Icon(Icons.circle, size: 12, color: color),
                  if (!last)
                    Expanded(
                        child: Container(width: 2, color: AppColors.border)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text(
                      message,
                      style: const TextStyle(
                        color: AppColors.secondaryText,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
}

const _labelStyle = TextStyle(
  color: AppColors.secondaryText,
  fontSize: 11,
  fontWeight: FontWeight.w700,
  letterSpacing: .4,
);

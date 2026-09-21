import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/network/idempotency_key.dart';
import '../../shared/models/domain_models.dart';
import '../../shared/widgets/account_components.dart';
import '../../shared/widgets/renthub_components.dart';
import '../renter/booking/booking_flow.dart' show formatDateRange, formatMoney;
import 'live_renthub_controller.dart';
import 'live_dispute_page.dart';
import 'live_review_page.dart';
import 'live_shared_pages.dart';

class LiveRenterShell extends StatefulWidget {
  const LiveRenterShell({
    super.key,
    required this.canSwitch,
    required this.onSwitchRole,
    required this.onLogout,
  });

  final bool canSwitch;
  final VoidCallback onSwitchRole;
  final Future<void> Function() onLogout;

  @override
  State<LiveRenterShell> createState() => _LiveRenterShellState();
}

class _LiveRenterShellState extends State<LiveRenterShell> {
  int index = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      await context.read<LiveRentHubController>().loadRenter();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<LiveRentHubController>();
    final pages = [
      LiveMarketplacePage(
        title: 'RentHub',
        featuredOnly: true,
        onOpenBookings: () => setState(() => index = 2),
      ),
      LiveMarketplacePage(
        title: 'Explore',
        onOpenBookings: () => setState(() => index = 2),
      ),
      const LiveRenterBookingsPage(),
      const LiveMessagesPage(),
      LiveProfilePage(
        role: 'Renter',
        canSwitch: widget.canSwitch,
        onSwitch: widget.onSwitchRole,
        onLogout: widget.onLogout,
      ),
    ];
    return Scaffold(
      body: controller.loading && controller.profile == null
          ? const SafeArea(
              child: RentHubFeedbackState(
                kind: FeedbackKind.loading,
                title: 'Connecting to RentHub',
                message: 'Loading your MongoDB marketplace data…',
              ),
            )
          : controller.error != null && controller.profile == null
              ? SafeArea(
                  child: RentHubFeedbackState(
                    kind: FeedbackKind.error,
                    title: 'Backend unavailable',
                    message: controller.error!,
                    actionLabel: 'Try Again',
                    onAction: _load,
                  ),
                )
              : IndexedStack(index: index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (value) => setState(() => index = value),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.search), label: 'Explore'),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            label: 'Bookings',
          ),
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            label: 'Messages',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

class LiveMarketplacePage extends StatefulWidget {
  const LiveMarketplacePage({
    super.key,
    required this.title,
    required this.onOpenBookings,
    this.featuredOnly = false,
  });

  final String title;
  final VoidCallback onOpenBookings;
  final bool featuredOnly;

  @override
  State<LiveMarketplacePage> createState() => _LiveMarketplacePageState();
}

class _LiveMarketplacePageState extends State<LiveMarketplacePage> {
  String query = '';
  String category = 'All';

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<LiveRentHubController>();
    var listings = controller.listings.where((listing) {
      final matchesQuery = query.isEmpty ||
          listing.title.toLowerCase().contains(query.toLowerCase()) ||
          listing.location.toLowerCase().contains(query.toLowerCase());
      return matchesQuery &&
          (category == 'All' || listing.category == category) &&
          listing.status == 'active';
    }).toList();
    if (widget.featuredOnly && listings.length > 6) {
      listings = listings.take(6).toList();
    }
    return Scaffold(
      appBar: AppBar(
        title: widget.featuredOnly ? const RentHubLogo() : Text(widget.title),
        actions: [
          IconButton(
            tooltip: 'Notifications',
            onPressed: () => Navigator.push<void>(
              context,
              MaterialPageRoute(
                builder: (_) => const LiveNotificationsPage(),
              ),
            ),
            icon: const Icon(Icons.notifications_outlined),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: controller.loadRenter,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            if (widget.featuredOnly) ...[
              Text(
                'Find something useful today',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
            ],
            TextField(
              onChanged: (value) => setState(() => query = value),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search rentals and services',
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 42,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final value in const [
                    'All',
                    'Devices',
                    'Vehicles',
                    'Equipment',
                    'Clothing',
                    'Books',
                    'Services',
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: Text(value),
                        selected: category == value,
                        onSelected: (_) => setState(() => category = value),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (listings.isEmpty)
              const SizedBox(
                height: 360,
                child: RentHubFeedbackState(
                  kind: FeedbackKind.empty,
                  title: 'No matching listings',
                  message: 'Try another category or search term.',
                ),
              )
            else
              for (final listing in listings)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Card(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => Navigator.push<void>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => LiveBookingPage(
                            listing: listing,
                            onSubmitted: widget.onOpenBookings,
                          ),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            Container(
                              width: 76,
                              height: 76,
                              decoration: BoxDecoration(
                                color: AppColors.primaryLight,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                listing.isService
                                    ? Icons.design_services_outlined
                                    : Icons.inventory_2_outlined,
                                color: AppColors.primaryDark,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    listing.title,
                                    style:
                                        Theme.of(context).textTheme.titleMedium,
                                  ),
                                  Text(
                                    '${listing.ownerName} · ${listing.location}',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: AppColors.secondaryText,
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(height: 7),
                                  Wrap(
                                    spacing: 8,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      if (listing.promotionActive)
                                        Text(
                                          formatMoney(listing.dailyPrice),
                                          style: const TextStyle(
                                            color: AppColors.secondaryText,
                                            decoration:
                                                TextDecoration.lineThrough,
                                          ),
                                        ),
                                      Text(
                                        '${formatMoney(listing.displayPrice)} / ${listing.priceUnit}',
                                        style: const TextStyle(
                                          color: AppColors.primaryDark,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      if (listing.promotionActive)
                                        StatusBadge(
                                          '${listing.promotionDiscountPercent.toStringAsFixed(0)}% off',
                                        ),
                                      if (listing.verified)
                                        const Chip(
                                          avatar: Icon(
                                            Icons.verified,
                                            size: 16,
                                            color: AppColors.success,
                                          ),
                                          label: Text('Verified'),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class LiveBookingPage extends StatefulWidget {
  const LiveBookingPage({
    super.key,
    required this.listing,
    required this.onSubmitted,
  });

  final Listing listing;
  final VoidCallback onSubmitted;

  @override
  State<LiveBookingPage> createState() => _LiveBookingPageState();
}

class _LiveBookingPageState extends State<LiveBookingPage> {
  late DateTime start = DateTime.now().add(const Duration(days: 7));
  late DateTime end = DateTime.now().add(const Duration(days: 9));
  TimeOfDay serviceTime = const TimeOfDay(hour: 14, minute: 0);
  String paymentMethod = 'card';
  String fulfilmentMethod = 'pickup';
  bool waiver = false;
  final venue = TextEditingController(text: 'Kuala Lumpur');
  final note = TextEditingController();
  bool submitting = false;
  late final String checkoutIdempotencyKey = newCheckoutIdempotencyKey();
  Future<List<Review>>? reviewFuture;

  @override
  void initState() {
    super.initState();
    final methods = widget.listing.fulfilmentMethods;
    if (methods.isNotEmpty) fulfilmentMethod = methods.first;
    waiver = widget.listing.damageWaiverAvailable;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    reviewFuture ??=
        context.read<LiveRentHubController>().listingReviews(widget.listing.id);
  }

  @override
  void dispose() {
    venue.dispose();
    note.dispose();
    super.dispose();
  }

  Future<void> _pick(bool startDate) async {
    final current = startDate ? start : end;
    final selected = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );
    if (selected == null) return;
    setState(() {
      if (startDate) {
        start = selected;
        if (end.isBefore(start)) end = start;
      } else {
        end = selected;
      }
    });
  }

  Future<void> _pickServiceTime() async {
    final selected = await showTimePicker(
      context: context,
      initialTime: serviceTime,
    );
    if (selected != null) setState(() => serviceTime = selected);
  }

  Future<void> _submit() async {
    if (submitting || end.isBefore(start)) return;
    if (widget.listing.isService && venue.text.trim().length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter the service venue.')),
      );
      return;
    }
    final accepted = await confirmAction(
      context,
      title: 'Create and authorize booking?',
      message:
          'RentHub will create the pending request first, then authorize the server-calculated total. No real payment is made.',
      action: 'Continue',
    );
    if (!accepted || !mounted) return;
    setState(() => submitting = true);
    try {
      final bookingStart = widget.listing.isService
          ? DateTime(
              start.year,
              start.month,
              start.day,
              serviceTime.hour,
              serviceTime.minute,
            )
          : start;
      final booking =
          await context.read<LiveRentHubController>().createAndAuthorizeBooking(
                listing: widget.listing,
                start: bookingStart,
                end: end,
                paymentMethod: paymentMethod,
                fulfilmentMethod: fulfilmentMethod,
                serviceVenue: venue.text.trim(),
                damageWaiverSelected: waiver,
                renterNote: note.text,
                idempotencyKey: checkoutIdempotencyKey,
              );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.check_circle, color: AppColors.success),
          title: const Text('Request submitted'),
          content: Text(
            '${booking.id}\nServer total: ${formatMoney(booking.total)}\nPayment: ${booking.paymentStatus}',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('View Bookings'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      Navigator.pop(context);
      widget.onSubmitted();
    } catch (exception) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(exception.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final listing = widget.listing;
    final days = end.difference(start).inDays + 1;
    final estimate = listing.isService
        ? listing.displayPrice * 1.05
        : listing.displayPrice * days +
            listing.securityDeposit +
            (waiver ? listing.damageWaiverFee : 0);
    return Scaffold(
      appBar:
          AppBar(title: Text(listing.isService ? 'Book Service' : 'Rent Item')),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(16),
        child: RentHubActionButton(
          label: 'Request & Authorize',
          loading: submitting,
          onPressed: submitting ? null : _submit,
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(listing.title,
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 4),
                    Text('${listing.ownerName} · ${listing.location}'),
                    if (!listing.isService)
                      Text('Condition: ${listing.condition}'),
                    if (listing.description.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(listing.description),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (listing.promotionActive || listing.bundleActive) ...[
              Card(
                color: AppColors.blueSurface,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (listing.promotionActive) ...[
                        Text(
                          listing.promotionLabel,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          '${listing.promotionDiscountPercent.toStringAsFixed(0)}% off: ${formatMoney(listing.dailyPrice)} → ${formatMoney(listing.displayPrice)} per ${listing.priceUnit}',
                        ),
                      ],
                      if (listing.bundleActive) ...[
                        if (listing.promotionActive) const SizedBox(height: 12),
                        Text(
                          listing.bundleTitle,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          '${listing.bundleListingIds.length} items · ${listing.bundleDiscountPercent.toStringAsFixed(0)}% bundle discount',
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: FutureBuilder<List<Review>>(
                  future: reviewFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const LinearProgressIndicator();
                    }
                    final reviews = snapshot.data ?? const <Review>[];
                    if (reviews.isEmpty) {
                      return const Text(
                        'No published reviews yet. Be the first after completing a booking.',
                        style: TextStyle(color: AppColors.secondaryText),
                      );
                    }
                    final average = reviews
                            .map((review) => review.rating)
                            .reduce((a, b) => a + b) /
                        reviews.length;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${average.toStringAsFixed(1)} / 5 from ${reviews.length} review${reviews.length == 1 ? '' : 's'}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        for (final review in reviews.take(2)) ...[
                          Text(
                            '${review.authorName} • ${review.rating}/5',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          Text(review.text),
                          const SizedBox(height: 8),
                        ],
                      ],
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                          listing.isService ? 'Service date' : 'Start date'),
                      subtitle:
                          Text('${start.day}/${start.month}/${start.year}'),
                      trailing: const Icon(Icons.calendar_today_outlined),
                      onTap: () => _pick(true),
                    ),
                    if (!listing.isService)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('End date'),
                        subtitle: Text('${end.day}/${end.month}/${end.year}'),
                        trailing: const Icon(Icons.calendar_today_outlined),
                        onTap: () => _pick(false),
                      ),
                    if (listing.isService)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Service time'),
                        subtitle: Text(serviceTime.format(context)),
                        trailing: const Icon(Icons.schedule_outlined),
                        onTap: _pickServiceTime,
                      ),
                    if (listing.isService)
                      TextField(
                        controller: venue,
                        decoration: const InputDecoration(
                          labelText: 'Service venue',
                        ),
                      )
                    else if (listing.fulfilmentMethods.isNotEmpty)
                      DropdownButtonFormField<String>(
                        initialValue: fulfilmentMethod,
                        decoration:
                            const InputDecoration(labelText: 'Fulfilment'),
                        items: listing.fulfilmentMethods
                            .map(
                              (method) => DropdownMenuItem(
                                value: method,
                                child: Text(
                                  method == 'pickup'
                                      ? 'Self pickup'
                                      : 'Owner delivery',
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (value) => setState(
                          () => fulfilmentMethod = value ?? fulfilmentMethod,
                        ),
                      ),
                    if (!listing.isService && listing.damageWaiverAvailable)
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: waiver,
                        title: const Text('Damage waiver'),
                        subtitle: Text(formatMoney(listing.damageWaiverFee)),
                        onChanged: (value) => setState(() => waiver = value),
                      ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: note,
                      maxLength: 1000,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Note to Owner (optional)',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Payment',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: paymentMethod,
                      decoration: const InputDecoration(labelText: 'Method'),
                      items: const [
                        DropdownMenuItem(
                            value: 'card', child: Text('Demo Card')),
                        DropdownMenuItem(value: 'fpx', child: Text('Mock FPX')),
                        DropdownMenuItem(
                            value: 'wallet', child: Text('Demo Wallet')),
                      ],
                      onChanged: (value) => setState(
                          () => paymentMethod = value ?? paymentMethod),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Estimated total: ${formatMoney(estimate)}',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const Text(
                      'The authoritative amount is calculated by the backend after the request is created.',
                      style: TextStyle(color: AppColors.secondaryText),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class LiveRenterBookingsPage extends StatefulWidget {
  const LiveRenterBookingsPage({super.key});

  @override
  State<LiveRenterBookingsPage> createState() => _LiveRenterBookingsPageState();
}

class _LiveRenterBookingsPageState extends State<LiveRenterBookingsPage> {
  Future<void> _refresh() async {
    try {
      await context.read<LiveRentHubController>().loadRenter();
    } catch (_) {}
  }

  Future<void> _cancel(Booking booking) async {
    final reason = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel booking?'),
        content: TextField(
          controller: reason,
          decoration: const InputDecoration(labelText: 'Cancellation reason'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep Booking'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cancel Booking'),
          ),
        ],
      ),
    );
    if (accepted == true && reason.text.trim().length >= 3 && mounted) {
      try {
        await context
            .read<LiveRentHubController>()
            .cancelBooking(booking.id, reason.text.trim());
      } catch (exception) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(exception.toString())));
        }
      }
    }
    reason.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<LiveRentHubController>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Bookings'),
        actions: [
          IconButton(
            tooltip: 'Notifications',
            onPressed: () => Navigator.push<void>(
              context,
              MaterialPageRoute(
                builder: (_) => const LiveNotificationsPage(),
              ),
            ),
            icon: const Icon(Icons.notifications_outlined),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: controller.bookings.isEmpty
            ? ListView(
                children: const [
                  SizedBox(
                    height: 520,
                    child: RentHubFeedbackState(
                      kind: FeedbackKind.empty,
                      title: 'No bookings yet',
                      message: 'Your MongoDB booking records will appear here.',
                    ),
                  ),
                ],
              )
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: controller.bookings.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final booking = controller.bookings[index];
                  final matchingRentals = controller.rentals
                      .where((item) => item.bookingId == booking.id)
                      .toList();
                  final rental =
                      matchingRentals.isEmpty ? null : matchingRentals.first;
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  booking.listingTitle,
                                  style:
                                      Theme.of(context).textTheme.titleMedium,
                                ),
                              ),
                              StatusBadge(booking.status),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(formatDateRange(booking.start, booking.end)),
                          Text(
                            '${formatMoney(booking.total)} · Payment ${booking.paymentStatus}',
                            style: const TextStyle(
                              color: AppColors.primaryDark,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (rental != null) ...[
                            const Divider(height: 22),
                            Text('Rental/order status: ${rental.status}'),
                            const SizedBox(height: 8),
                            _RenterRentalActions(rental: rental),
                          ],
                          if (['pending', 'approved'].contains(booking.status))
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: () => _cancel(booking),
                                child: const Text('Cancel Booking'),
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}

class _RenterRentalActions extends StatelessWidget {
  const _RenterRentalActions({required this.rental});

  final Rental rental;

  Future<void> _action(
    BuildContext context,
    String action,
    Map<String, dynamic>? body,
    String success,
  ) async {
    try {
      await context
          .read<LiveRentHubController>()
          .runRentalAction(rental, action, body: body);
      if (context.mounted) showMockSuccess(context, success);
    } catch (exception) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(exception.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final existingDispute =
        context.watch<LiveRentHubController>().disputeForRental(rental.id);
    final disputeButton = OutlinedButton.icon(
      onPressed: () => Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => LiveDisputePage(rental: rental, owner: false),
        ),
      ),
      icon: Icon(existingDispute == null
          ? Icons.gavel_outlined
          : Icons.manage_search_outlined),
      label: Text(existingDispute == null ? 'Raise Dispute' : 'Track Dispute'),
    );
    if (rental.status == 'completed') {
      final matching = context
          .watch<LiveRentHubController>()
          .reviews
          .where((review) => review.rentalId == rental.id)
          .toList();
      final existing = matching.isEmpty ? null : matching.first;
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          FilledButton.icon(
            onPressed: existing != null && !existing.canEdit
                ? null
                : () => Navigator.push<void>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => LiveReviewPage(
                          rental: rental,
                          subject: 'Owner for ${rental.listingId}',
                          existing: existing,
                        ),
                      ),
                    ),
            icon: const Icon(Icons.star_outline),
            label: Text(
              existing == null
                  ? 'Rate & Review'
                  : existing.canEdit
                      ? 'Edit Review'
                      : 'Review Submitted',
            ),
          ),
          disputeButton,
        ],
      );
    }
    if (rental.listingType == 'service' &&
        rental.status == 'completion_pending') {
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          FilledButton.icon(
            onPressed: () => _action(
              context,
              'service-completion',
              null,
              'Service completion confirmed',
            ),
            icon: const Icon(Icons.task_alt),
            label: const Text('Confirm Service Completion'),
          ),
          disputeButton,
        ],
      );
    }
    if (rental.listingType == 'physical' && rental.status == 'active') {
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          OutlinedButton(
            onPressed: rental.extensionStatus == 'pending'
                ? null
                : () async {
                    final requested = await showDatePicker(
                      context: context,
                      initialDate: (rental.end ?? DateTime.now())
                          .add(const Duration(days: 1)),
                      firstDate: (rental.end ?? DateTime.now())
                          .add(const Duration(days: 1)),
                      lastDate: DateTime.now().add(const Duration(days: 730)),
                    );
                    if (requested != null && context.mounted) {
                      await _action(
                        context,
                        'extension',
                        {
                          'requestedEndDate':
                              requested.toUtc().toIso8601String(),
                          'reason':
                              'I need the item for additional project work',
                        },
                        'Extension request submitted',
                      );
                    }
                  },
            child: Text(
              rental.extensionStatus == 'pending'
                  ? 'Extension Pending'
                  : 'Request Extension',
            ),
          ),
          FilledButton(
            onPressed: () async {
              final accepted = await confirmAction(
                context,
                title: 'Submit item return?',
                message:
                    'A local evidence placeholder and the current condition will be recorded.',
                action: 'Submit Return',
              );
              if (accepted && context.mounted) {
                await _action(
                  context,
                  'return',
                  {
                    'condition': 'Good',
                    'notes': 'Returned through the live Flutter flow.',
                    'evidence': ['local://return/flutter-evidence.jpg'],
                  },
                  'Return evidence submitted',
                );
              }
            },
            child: const Text('Submit Return'),
          ),
          disputeButton,
        ],
      );
    }
    if (rental.status == 'disputed') return disputeButton;
    if (!['cancelled', 'scheduled'].contains(rental.status)) {
      return disputeButton;
    }
    return const SizedBox.shrink();
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/renthub_categories.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/models/domain_models.dart';
import '../../shared/widgets/account_components.dart';
import '../../shared/widgets/renthub_components.dart';
import '../renter/booking/booking_flow.dart' show formatDateRange, formatMoney;
import 'live_renthub_controller.dart';
import 'live_review_page.dart';
import 'live_shared_pages.dart';

class LiveOwnerShell extends StatefulWidget {
  const LiveOwnerShell({
    super.key,
    required this.canSwitch,
    required this.onSwitchRole,
    required this.onLogout,
  });

  final bool canSwitch;
  final VoidCallback onSwitchRole;
  final Future<void> Function() onLogout;

  @override
  State<LiveOwnerShell> createState() => _LiveOwnerShellState();
}

class _LiveOwnerShellState extends State<LiveOwnerShell> {
  int index = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      await context.read<LiveRentHubController>().loadOwner();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<LiveRentHubController>();
    final pages = [
      LiveOwnerDashboard(onOpenRequests: () => setState(() => index = 2)),
      const LiveOwnerListingsPage(),
      const LiveOwnerRequestsPage(),
      const LiveMessagesPage(),
      LiveProfilePage(
        role: 'Owner',
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
                title: 'Loading Owner workspace',
                message: 'Reading listings and requests from MongoDB…',
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
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.inventory_2_outlined),
            label: 'Listings',
          ),
          NavigationDestination(
            icon: Icon(Icons.assignment_outlined),
            label: 'Requests',
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

class LiveOwnerDashboard extends StatelessWidget {
  const LiveOwnerDashboard({super.key, required this.onOpenRequests});

  final VoidCallback onOpenRequests;

  Future<void> _flag(BuildContext context, Review review) async {
    final reason = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Flag suspicious review?'),
        content: TextField(
          controller: reason,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'Reason for administrator review',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Submit Flag'),
          ),
        ],
      ),
    );
    if (accepted == true && reason.text.trim().length >= 5 && context.mounted) {
      try {
        await context
            .read<LiveRentHubController>()
            .flagReview(review.id, reason.text);
      } catch (exception) {
        if (context.mounted) {
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
    final pending =
        controller.bookings.where((item) => item.status == 'pending').length;
    final active =
        controller.rentals.where((item) => item.status == 'active').length;
    return Scaffold(
      appBar: AppBar(
        title: const RentHubLogo(),
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
        onRefresh: controller.loadOwner,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Welcome, ${controller.profile?.name ?? 'Owner'}',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const Text(
              'Live marketplace activity from MongoDB',
              style: TextStyle(color: AppColors.secondaryText),
            ),
            const SizedBox(height: 20),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.35,
              children: [
                _LiveMetric(
                  'My listings',
                  '${controller.ownerListings.length}',
                  Icons.inventory_2_outlined,
                ),
                _LiveMetric('Pending requests', '$pending', Icons.schedule),
                _LiveMetric(
                    'Active orders', '$active', Icons.local_shipping_outlined),
                _LiveMetric(
                  'Trust score',
                  controller.profile?.trustScore.toStringAsFixed(0) ?? '—',
                  Icons.verified_user_outlined,
                ),
              ],
            ),
            const SizedBox(height: 24),
            Card(
              child: ListTile(
                leading: const CircleAvatar(
                  backgroundColor: AppColors.primaryLight,
                  child: Icon(Icons.assignment_outlined),
                ),
                title: Text('$pending booking requests need a decision'),
                subtitle: const Text(
                  'Approval requires the renter’s payment authorization.',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: onOpenRequests,
              ),
            ),
            const SizedBox(height: 16),
            Text('Rental and service actions',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            if (controller.rentals.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Text('No active rental or service actions.'),
                ),
              )
            else
              for (final rental in controller.rentals)
                _OwnerRentalCard(rental: rental),
            const SizedBox(height: 20),
            Text('Reviews received',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            if (controller.receivedReviews.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Text('Completed-order reviews will appear here.'),
                ),
              )
            else
              for (final review in controller.receivedReviews.take(3))
                Card(
                  child: ListTile(
                    leading: CircleAvatar(child: Text('${review.rating}')),
                    title:
                        Text('${review.authorName} • ${review.listingTitle}'),
                    subtitle: Text(review.text),
                    trailing: review.flagged
                        ? const StatusBadge('Flagged')
                        : IconButton(
                            tooltip: 'Flag suspicious review',
                            onPressed: () => _flag(context, review),
                            icon: const Icon(Icons.flag_outlined),
                          ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class _LiveMetric extends StatelessWidget {
  const _LiveMetric(this.label, this.value, this.icon);

  final String label, value;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: AppColors.primary),
              const Spacer(),
              Text(value, style: Theme.of(context).textTheme.titleLarge),
              Text(label,
                  style: const TextStyle(
                    color: AppColors.secondaryText,
                    fontSize: 12,
                  )),
            ],
          ),
        ),
      );
}

class LiveOwnerListingsPage extends StatelessWidget {
  const LiveOwnerListingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<LiveRentHubController>();
    return Scaffold(
      appBar: AppBar(title: const Text('My Listings')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showModalBottomSheet<void>(
          context: context,
          showDragHandle: true,
          builder: (sheetContext) => Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Create listing',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(sheetContext);
                    Navigator.push<void>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const LiveListingForm(isService: false),
                      ),
                    );
                  },
                  icon: const Icon(Icons.inventory_2_outlined),
                  label: const Text('Physical Item'),
                ),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(sheetContext);
                    Navigator.push<void>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const LiveListingForm(isService: true),
                      ),
                    );
                  },
                  icon: const Icon(Icons.design_services_outlined),
                  label: const Text('Service'),
                ),
              ],
            ),
          ),
        ),
        icon: const Icon(Icons.add),
        label: const Text('New Listing'),
      ),
      body: RefreshIndicator(
        onRefresh: controller.loadOwner,
        child: controller.ownerListings.isEmpty
            ? ListView(
                children: const [
                  SizedBox(
                    height: 520,
                    child: RentHubFeedbackState(
                      kind: FeedbackKind.empty,
                      title: 'No listings yet',
                      message: 'Create an item or service listing to begin.',
                    ),
                  ),
                ],
              )
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: controller.ownerListings.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final listing = controller.ownerListings[index];
                  return Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        child: Icon(listing.isService
                            ? Icons.design_services_outlined
                            : Icons.inventory_2_outlined),
                      ),
                      title: Text(listing.title),
                      subtitle: Text(
                        '${formatMoney(listing.dailyPrice)} · ${listing.status.replaceAll('_', ' ')}',
                      ),
                      trailing: listing.status == 'inactive'
                          ? const StatusBadge('Inactive')
                          : PopupMenuButton<String>(
                              onSelected: (value) async {
                                if (value != 'deactivate') return;
                                final accepted = await confirmAction(
                                  context,
                                  title: 'Deactivate listing?',
                                  message:
                                      'The listing will no longer appear in renter discovery.',
                                  action: 'Deactivate',
                                  destructive: true,
                                );
                                if (accepted && context.mounted) {
                                  await controller
                                      .deactivateListing(listing.id);
                                }
                              },
                              itemBuilder: (_) => const [
                                PopupMenuItem(
                                  value: 'deactivate',
                                  child: Text('Deactivate'),
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

class LiveListingForm extends StatefulWidget {
  const LiveListingForm({super.key, required this.isService});

  final bool isService;

  @override
  State<LiveListingForm> createState() => _LiveListingFormState();
}

class _LiveListingFormState extends State<LiveListingForm> {
  final formKey = GlobalKey<FormState>();
  final title = TextEditingController();
  final description = TextEditingController();
  final price = TextEditingController();
  final location = TextEditingController(text: 'Kuala Lumpur');
  final deposit = TextEditingController(text: '0');
  final duration = TextEditingController(text: '60');
  String category = RentHubCategories.devices;
  String condition = 'Excellent';
  bool saving = false;

  @override
  void initState() {
    super.initState();
    if (widget.isService) category = RentHubCategories.services;
  }

  @override
  void dispose() {
    title.dispose();
    description.dispose();
    price.dispose();
    location.dispose();
    deposit.dispose();
    duration.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!formKey.currentState!.validate() || saving) return;
    setState(() => saving = true);
    final payload = <String, dynamic>{
      'title': title.text.trim(),
      'description': description.text.trim(),
      'category': category,
      'listingType': widget.isService ? 'service' : 'physical',
      'dailyPrice': double.parse(price.text),
      'location': location.text.trim(),
      'state': location.text.toLowerCase().contains('selangor')
          ? 'Selangor'
          : 'Kuala Lumpur',
      if (widget.isService) ...{
        'priceUnit': 'package',
        'serviceDetails': {
          'packageName': title.text.trim(),
          'durationMinutes': int.parse(duration.text),
          'venueMode': 'flexible',
          'inclusions': ['Service package as described'],
        },
      } else ...{
        'priceUnit': 'day',
        'condition': condition,
        'securityDeposit': double.parse(deposit.text),
        'damageWaiverAvailable': false,
        'damageWaiverFee': 0,
        'fulfilmentMethods': ['pickup', 'owner_delivery'],
      },
    };
    try {
      await context.read<LiveRentHubController>().createOwnerListing(payload);
      if (!mounted) return;
      showMockSuccess(context, 'Listing submitted for moderation');
      Navigator.pop(context);
    } catch (exception) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(exception.toString())));
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(widget.isService ? 'Create Service' : 'Create Item'),
        ),
        body: SafeArea(
          child: Form(
            key: formKey,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                TextFormField(
                  controller: title,
                  decoration: const InputDecoration(labelText: 'Title'),
                  validator: (value) => (value?.trim().length ?? 0) >= 3
                      ? null
                      : 'Enter at least 3 characters',
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: description,
                  maxLines: 4,
                  decoration: const InputDecoration(labelText: 'Description'),
                ),
                const SizedBox(height: 12),
                if (!widget.isService)
                  DropdownButtonFormField<String>(
                    initialValue: category,
                    decoration: const InputDecoration(labelText: 'Category'),
                    items: const [
                      RentHubCategories.devices,
                      RentHubCategories.vehicles,
                      RentHubCategories.equipment,
                      RentHubCategories.clothing,
                      RentHubCategories.books,
                    ]
                        .map((value) =>
                            DropdownMenuItem(value: value, child: Text(value)))
                        .toList(),
                    onChanged: (value) => setState(() => category = value!),
                  ),
                if (!widget.isService) const SizedBox(height: 12),
                TextFormField(
                  controller: price,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: widget.isService
                        ? 'Package price (RM)'
                        : 'Daily price (RM)',
                  ),
                  validator: (value) => (double.tryParse(value ?? '') ?? 0) > 0
                      ? null
                      : 'Enter a valid price',
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: location,
                  decoration: const InputDecoration(labelText: 'Location'),
                  validator: (value) => (value?.trim().length ?? 0) >= 2
                      ? null
                      : 'Enter a location',
                ),
                const SizedBox(height: 12),
                if (widget.isService)
                  TextFormField(
                    controller: duration,
                    keyboardType: TextInputType.number,
                    decoration:
                        const InputDecoration(labelText: 'Duration (minutes)'),
                    validator: (value) {
                      final parsed = int.tryParse(value ?? '');
                      return parsed != null && parsed >= 15
                          ? null
                          : 'Minimum duration is 15 minutes';
                    },
                  )
                else ...[
                  DropdownButtonFormField<String>(
                    initialValue: condition,
                    decoration: const InputDecoration(labelText: 'Condition'),
                    items: const [
                      'Fair',
                      'Good',
                      'Very good',
                      'Excellent',
                      'Like New'
                    ]
                        .map((value) =>
                            DropdownMenuItem(value: value, child: Text(value)))
                        .toList(),
                    onChanged: (value) => setState(() => condition = value!),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: deposit,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                        labelText: 'Security deposit (RM)'),
                    validator: (value) => double.tryParse(value ?? '') == null
                        ? 'Enter a valid deposit'
                        : null,
                  ),
                ],
                const SizedBox(height: 20),
                RentHubActionButton(
                  label: 'Save & Submit for Review',
                  loading: saving,
                  onPressed: saving ? null : _save,
                ),
              ],
            ),
          ),
        ),
      );
}

class LiveOwnerRequestsPage extends StatelessWidget {
  const LiveOwnerRequestsPage({super.key});

  Future<void> _decide(
    BuildContext context,
    Booking booking,
    String status,
  ) async {
    final reason = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${status == 'approved' ? 'Approve' : 'Reject'} booking?'),
        content: status == 'rejected'
            ? TextField(
                controller: reason,
                decoration: const InputDecoration(labelText: 'Reason'),
              )
            : Text(
                'Confirm ${booking.listingTitle}. The payment will be captured at handover or service start.',
              ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Back'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(status == 'approved' ? 'Approve' : 'Reject'),
          ),
        ],
      ),
    );
    if (accepted == true && context.mounted) {
      if (status == 'rejected' && reason.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('A rejection reason is required.')),
        );
      } else {
        try {
          await context.read<LiveRentHubController>().decideBooking(
                booking.id,
                status,
                reason: reason.text,
              );
          if (context.mounted) {
            showMockSuccess(context,
                'Booking ${status == 'approved' ? 'approved' : 'rejected'}');
          }
        } catch (exception) {
          if (context.mounted) {
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text(exception.toString())));
          }
        }
      }
    }
    reason.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<LiveRentHubController>();
    return Scaffold(
      appBar: AppBar(title: const Text('Booking Requests')),
      body: RefreshIndicator(
        onRefresh: controller.loadOwner,
        child: controller.bookings.isEmpty
            ? ListView(
                children: const [
                  SizedBox(
                    height: 520,
                    child: RentHubFeedbackState(
                      kind: FeedbackKind.empty,
                      title: 'No booking requests',
                      message: 'Renter requests will appear here.',
                    ),
                  ),
                ],
              )
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: controller.bookings.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final booking = controller.bookings[index];
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(booking.listingTitle,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium),
                              ),
                              StatusBadge(booking.status),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text('${booking.renterName} · ${booking.id}'),
                          Text(formatDateRange(booking.start, booking.end)),
                          Text(
                            '${formatMoney(booking.total)} · ${booking.paymentStatus}',
                            style: const TextStyle(
                              color: AppColors.primaryDark,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (booking.status == 'pending') ...[
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: () =>
                                        _decide(context, booking, 'rejected'),
                                    child: const Text('Reject'),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: FilledButton(
                                    onPressed:
                                        booking.paymentStatus == 'authorized'
                                            ? () => _decide(
                                                  context,
                                                  booking,
                                                  'approved',
                                                )
                                            : null,
                                    child: const Text('Approve'),
                                  ),
                                ),
                              ],
                            ),
                          ],
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

class _OwnerRentalCard extends StatelessWidget {
  const _OwnerRentalCard({required this.rental});

  final Rental rental;

  Future<void> _run(
    BuildContext context,
    String action, {
    Map<String, dynamic>? body,
  }) async {
    try {
      await context.read<LiveRentHubController>().runRentalAction(
            rental,
            action,
            body: body,
            owner: true,
          );
      if (context.mounted) showMockSuccess(context, 'Rental status updated');
    } catch (exception) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(exception.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget? action;
    if (rental.status == 'completed') {
      final matching = context
          .watch<LiveRentHubController>()
          .reviews
          .where((review) => review.rentalId == rental.id)
          .toList();
      final existing = matching.isEmpty ? null : matching.first;
      action = OutlinedButton.icon(
        onPressed: existing != null && !existing.canEdit
            ? null
            : () => Navigator.push<void>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => LiveReviewPage(
                      rental: rental,
                      subject: 'Renter for ${rental.listingId}',
                      existing: existing,
                      reviewingRenter: true,
                    ),
                  ),
                ),
        icon: const Icon(Icons.rate_review_outlined),
        label: Text(
          existing == null
              ? 'Review Renter'
              : existing.canEdit
                  ? 'Edit Renter Review'
                  : 'Renter Reviewed',
        ),
      );
    } else if (rental.status == 'scheduled') {
      action = FilledButton(
        onPressed: () => rental.listingType == 'service'
            ? _run(context, 'start-service')
            : _run(
                context,
                'handover',
                body: const {
                  'condition': 'Excellent',
                  'notes': 'Confirmed through the live Owner interface.',
                  'evidence': ['local://handover/flutter-evidence.jpg'],
                },
              ),
        child: Text(rental.listingType == 'service'
            ? 'Start Service'
            : 'Confirm Handover'),
      );
    } else if (rental.listingType == 'service' && rental.status == 'active') {
      action = FilledButton(
        onPressed: () => _run(context, 'service-delivered'),
        child: const Text('Mark Service Delivered'),
      );
    } else if (rental.status == 'return_submitted') {
      action = FilledButton(
        onPressed: () => _run(
          context,
          'return-confirm',
          body: const {
            'condition': 'Good',
            'notes': 'Return inspected in the live Owner interface.',
            'depositDeduction': 0,
          },
        ),
        child: const Text('Confirm Return'),
      );
    } else if (rental.extensionStatus == 'pending') {
      action = Wrap(
        spacing: 8,
        children: [
          OutlinedButton(
            onPressed: () => _run(
              context,
              'extension-decision',
              body: const {
                'status': 'rejected',
                'reason': 'The item is committed to another renter',
              },
            ),
            child: const Text('Reject Extension'),
          ),
          FilledButton(
            onPressed: () => _run(
              context,
              'extension-decision',
              body: const {'status': 'approved'},
            ),
            child: const Text('Approve Extension'),
          ),
        ],
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(rental.listingId)),
                StatusBadge(rental.status),
              ],
            ),
            Text('Booking ${rental.bookingId}'),
            if (action != null) ...[
              const SizedBox(height: 10),
              action,
            ],
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/renthub_categories.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/models/domain_models.dart';
import '../../shared/widgets/account_components.dart';
import '../../shared/widgets/renthub_components.dart';
import '../renter/booking/booking_flow.dart' show formatDateRange, formatMoney;
import 'live_renthub_controller.dart';
import 'live_dispute_page.dart';
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
                        '${formatMoney(listing.dailyPrice)} · ${listing.status.replaceAll('_', ' ')}'
                        '${listing.promotionActive ? '\n${listing.promotionLabel} · ${listing.promotionDiscountPercent.toStringAsFixed(0)}% off' : ''}'
                        '${listing.bundleActive ? '\n${listing.bundleTitle}' : ''}',
                      ),
                      isThreeLine:
                          listing.promotionActive || listing.bundleActive,
                      trailing: listing.status == 'inactive'
                          ? const StatusBadge('Inactive')
                          : PopupMenuButton<String>(
                              onSelected: (value) async {
                                if (value == 'edit') {
                                  await Navigator.push<void>(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => LiveListingForm(
                                        isService: listing.isService,
                                        listing: listing,
                                      ),
                                    ),
                                  );
                                } else if (value == 'availability') {
                                  await Navigator.push<void>(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          LiveAvailabilityPage(listing),
                                    ),
                                  );
                                } else if (value == 'promotion') {
                                  await Navigator.push<void>(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          LivePromotionPage(listing),
                                    ),
                                  );
                                } else if (value == 'bundle') {
                                  await Navigator.push<void>(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => LiveBundlePage(listing),
                                    ),
                                  );
                                } else if (value == 'deactivate') {
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
                                }
                              },
                              itemBuilder: (_) => [
                                if (listing.status != 'pending_review')
                                  const PopupMenuItem(
                                    value: 'edit',
                                    child: Text('Edit listing'),
                                  ),
                                const PopupMenuItem(
                                  value: 'availability',
                                  child: Text('Availability'),
                                ),
                                const PopupMenuItem(
                                  value: 'promotion',
                                  child: Text('Promotion'),
                                ),
                                if (!listing.isService &&
                                    listing.status == 'active')
                                  const PopupMenuItem(
                                    value: 'bundle',
                                    child: Text('Bundle offer'),
                                  ),
                                const PopupMenuItem(
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
  const LiveListingForm({
    super.key,
    required this.isService,
    this.listing,
  });

  final bool isService;
  final Listing? listing;

  @override
  State<LiveListingForm> createState() => _LiveListingFormState();
}

class _LiveListingFormState extends State<LiveListingForm> {
  final formKey = GlobalKey<FormState>();
  late final title = TextEditingController(text: widget.listing?.title);
  late final description =
      TextEditingController(text: widget.listing?.description);
  late final price = TextEditingController(
    text: widget.listing?.dailyPrice.toStringAsFixed(2),
  );
  late final location = TextEditingController(
    text: widget.listing?.location ?? 'Kuala Lumpur',
  );
  late final deposit = TextEditingController(
    text: widget.listing?.securityDeposit.toStringAsFixed(2) ?? '0',
  );
  late final duration = TextEditingController(
    text: widget.listing?.serviceDurationMinutes?.toString() ?? '60',
  );
  String category = RentHubCategories.devices;
  String condition = 'Excellent';
  bool saving = false;
  late final List<String> images;

  Future<void> _addImage() async {
    if (images.length >= 10) return;
    try {
      final reference =
          await context.read<LiveRentHubController>().pickAndUpload(
                purpose: 'listing_image',
                publicUrl: true,
              );
      if (reference != null && mounted) setState(() => images.add(reference));
    } catch (exception) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(exception.toString())));
      }
    }
  }

  Future<void> _removeImage(int index) async {
    final reference = images[index];
    try {
      await context.read<LiveRentHubController>().deleteUpload(reference);
      if (mounted) setState(() => images.remove(reference));
    } catch (exception) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(exception.toString())));
      }
    }
  }

  @override
  void initState() {
    super.initState();
    images = [...?widget.listing?.images];
    if (widget.isService) {
      category = RentHubCategories.services;
    } else if (widget.listing != null) {
      category = widget.listing!.category;
      condition = widget.listing!.condition;
    }
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
      if (images.isNotEmpty) 'images': images,
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
      if (widget.listing == null) {
        await context.read<LiveRentHubController>().createOwnerListing(payload);
      } else {
        await context
            .read<LiveRentHubController>()
            .updateOwnerListing(widget.listing!.id, payload);
      }
      if (!mounted) return;
      showMockSuccess(
        context,
        widget.listing == null
            ? 'Listing submitted for moderation'
            : 'Changes submitted for moderation',
      );
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
          title: Text(
            widget.listing == null
                ? (widget.isService ? 'Create Service' : 'Create Item')
                : 'Edit Listing',
          ),
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
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'Listing images',
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),
                            ),
                            Text('${images.length}/10'),
                            IconButton(
                              tooltip: 'Upload listing image',
                              onPressed: saving || images.length >= 10
                                  ? null
                                  : _addImage,
                              icon: const Icon(
                                  Icons.add_photo_alternate_outlined),
                            ),
                          ],
                        ),
                        const Text(
                          'JPEG, PNG, or WebP. Uploaded images are public after the listing is published.',
                          style: TextStyle(color: AppColors.secondaryText),
                        ),
                        for (var index = 0; index < images.length; index++)
                          ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.image_outlined),
                            title: Text('Image ${index + 1}'),
                            trailing: IconButton(
                              tooltip: 'Remove image',
                              onPressed:
                                  saving ? null : () => _removeImage(index),
                              icon: const Icon(Icons.close),
                            ),
                          ),
                      ],
                    ),
                  ),
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
                  label: widget.listing == null
                      ? 'Save & Submit for Review'
                      : 'Save Changes & Resubmit',
                  loading: saving,
                  onPressed: saving ? null : _save,
                ),
              ],
            ),
          ),
        ),
      );
}

class LiveAvailabilityPage extends StatefulWidget {
  const LiveAvailabilityPage(this.listing, {super.key});

  final Listing listing;

  @override
  State<LiveAvailabilityPage> createState() => _LiveAvailabilityPageState();
}

class _LiveAvailabilityPageState extends State<LiveAvailabilityPage> {
  final notice = TextEditingController(text: '0');
  final buffer = TextEditingController(text: '0');
  List<Map<String, dynamic>> ranges = [];
  List<Map<String, dynamic>> weeklyHours = [];
  bool loading = true;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await context
          .read<LiveRentHubController>()
          .getListingAvailability(widget.listing.id);
      ranges = ((data['unavailableRanges'] as List?) ?? const [])
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
      weeklyHours = ((data['weeklyHours'] as List?) ?? const [])
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
      notice.text = '${data['minimumNoticeHours'] ?? 0}';
      buffer.text = '${data['bufferHours'] ?? 0}';
    } catch (exception) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(exception.toString())));
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  void dispose() {
    notice.dispose();
    buffer.dispose();
    super.dispose();
  }

  Future<void> _addRange() async {
    final today = DateTime.now();
    final start = await showDatePicker(
      context: context,
      initialDate: today.add(const Duration(days: 1)),
      firstDate: today,
      lastDate: today.add(const Duration(days: 730)),
    );
    if (start == null || !mounted) return;
    final lastDay = await showDatePicker(
      context: context,
      initialDate: start,
      firstDate: start,
      lastDate: start.add(const Duration(days: 365)),
    );
    if (lastDay == null || !mounted) return;
    final reason = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Block these dates?'),
        content: TextField(
          controller: reason,
          decoration: const InputDecoration(
            labelText: 'Reason (optional)',
            hintText: 'Maintenance or personal use',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, reason.text.trim()),
            child: const Text('Block Dates'),
          ),
        ],
      ),
    );
    reason.dispose();
    if (value == null) return;
    setState(() {
      ranges.add({
        'start': start.toUtc().toIso8601String(),
        'end': lastDay.add(const Duration(days: 1)).toUtc().toIso8601String(),
        'reason': value,
      });
      ranges.sort(
        (left, right) => DateTime.parse(left['start'] as String)
            .compareTo(DateTime.parse(right['start'] as String)),
      );
    });
  }

  Future<void> _removeRange(int index) async {
    final accepted = await confirmAction(
      context,
      title: 'Remove blocked dates?',
      message: 'Renters will be able to request these dates again.',
      action: 'Remove',
      destructive: true,
    );
    if (accepted && mounted) setState(() => ranges.removeAt(index));
  }

  Future<void> _save() async {
    setState(() => saving = true);
    try {
      await context.read<LiveRentHubController>().saveListingAvailability(
        widget.listing.id,
        {
          'unavailableRanges': ranges,
          'weeklyHours': weeklyHours,
          'minimumNoticeHours': int.tryParse(notice.text) ?? 0,
          'bufferHours': int.tryParse(buffer.text) ?? 0,
        },
      );
      if (mounted) Navigator.pop(context);
    } catch (exception) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(exception.toString())));
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  String _date(String value, {bool exclusiveEnd = false}) {
    var date = DateTime.parse(value).toLocal();
    if (exclusiveEnd) date = date.subtract(const Duration(days: 1));
    return '${date.day}/${date.month}/${date.year}';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Manage Availability')),
        bottomNavigationBar: SafeArea(
          minimum: const EdgeInsets.all(16),
          child: RentHubActionButton(
            label: 'Save Availability',
            loading: saving,
            onPressed: loading || saving ? null : _save,
          ),
        ),
        body: loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(widget.listing.title,
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: notice,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Minimum notice (hours)',
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: buffer,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Buffer (hours)',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: Text('Unavailable dates',
                            style: Theme.of(context).textTheme.titleMedium),
                      ),
                      TextButton.icon(
                        onPressed: _addRange,
                        icon: const Icon(Icons.add),
                        label: const Text('Block Dates'),
                      ),
                    ],
                  ),
                  if (ranges.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('No dates are currently blocked.'),
                      ),
                    )
                  else
                    for (var index = 0; index < ranges.length; index++)
                      Card(
                        child: ListTile(
                          leading: const Icon(Icons.event_busy_outlined),
                          title: Text(
                            '${_date(ranges[index]['start'] as String)} - ${_date(ranges[index]['end'] as String, exclusiveEnd: true)}',
                          ),
                          subtitle: Text(
                            (ranges[index]['reason'] as String?)?.isEmpty ??
                                    true
                                ? 'Owner unavailable'
                                : ranges[index]['reason'] as String,
                          ),
                          trailing: IconButton(
                            tooltip: 'Remove blocked dates',
                            onPressed: () => _removeRange(index),
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ),
                      ),
                ],
              ),
      );
}

class LivePromotionPage extends StatefulWidget {
  const LivePromotionPage(this.listing, {super.key});

  final Listing listing;

  @override
  State<LivePromotionPage> createState() => _LivePromotionPageState();
}

class _LivePromotionPageState extends State<LivePromotionPage> {
  late final label = TextEditingController(
    text: widget.listing.promotionLabel.isEmpty
        ? 'Limited-time deal'
        : widget.listing.promotionLabel,
  );
  late final discount = TextEditingController(
    text: widget.listing.promotionDiscountPercent == 0
        ? '10'
        : widget.listing.promotionDiscountPercent.toStringAsFixed(0),
  );
  late DateTime start = widget.listing.promotionStartsAt ?? DateTime.now();
  late DateTime end = widget.listing.promotionEndsAt ??
      DateTime.now().add(const Duration(days: 30));
  bool saving = false;

  @override
  void dispose() {
    label.dispose();
    discount.dispose();
    super.dispose();
  }

  Future<void> _pick(bool isStart) async {
    final selected = await showDatePicker(
      context: context,
      initialDate: isStart ? start : end,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );
    if (selected == null) return;
    setState(() {
      if (isStart) {
        start = selected;
        if (!end.isAfter(start)) end = start.add(const Duration(days: 1));
      } else {
        end = selected;
      }
    });
  }

  Future<void> _save() async {
    final percentage = double.tryParse(discount.text);
    if (label.text.trim().length < 2 ||
        percentage == null ||
        percentage < 5 ||
        percentage > 80 ||
        !end.isAfter(start)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Check the promotion details.')),
      );
      return;
    }
    setState(() => saving = true);
    try {
      await context.read<LiveRentHubController>().saveListingPromotion(
        widget.listing.id,
        {
          'enabled': true,
          'label': label.text.trim(),
          'discountPercent': percentage,
          'startsAt': start.toUtc().toIso8601String(),
          'endsAt': end.add(const Duration(days: 1)).toUtc().toIso8601String(),
        },
      );
      if (mounted) Navigator.pop(context);
    } catch (exception) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(exception.toString())));
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> _clear() async {
    final accepted = await confirmAction(
      context,
      title: 'Remove promotion?',
      message: 'Renters will see the regular listing price.',
      action: 'Remove',
      destructive: true,
    );
    if (!accepted || !mounted) return;
    await context
        .read<LiveRentHubController>()
        .clearListingPromotion(widget.listing.id);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Promotion')),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(widget.listing.title,
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              TextField(
                controller: label,
                decoration: const InputDecoration(labelText: 'Promotion label'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: discount,
                keyboardType: TextInputType.number,
                decoration:
                    const InputDecoration(labelText: 'Discount percentage'),
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Starts'),
                subtitle: Text('${start.day}/${start.month}/${start.year}'),
                trailing: const Icon(Icons.calendar_today_outlined),
                onTap: () => _pick(true),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Ends'),
                subtitle: Text('${end.day}/${end.month}/${end.year}'),
                trailing: const Icon(Icons.calendar_today_outlined),
                onTap: () => _pick(false),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: saving ? null : _save,
                child: Text(saving ? 'Saving…' : 'Save Promotion'),
              ),
              if (widget.listing.promotionLabel.isNotEmpty)
                TextButton(
                  onPressed: saving ? null : _clear,
                  child: const Text('Remove Promotion'),
                ),
            ],
          ),
        ),
      );
}

class LiveBundlePage extends StatefulWidget {
  const LiveBundlePage(this.listing, {super.key});

  final Listing listing;

  @override
  State<LiveBundlePage> createState() => _LiveBundlePageState();
}

class _LiveBundlePageState extends State<LiveBundlePage> {
  late final title = TextEditingController(
    text: widget.listing.bundleTitle.isEmpty
        ? '${widget.listing.title} Bundle'
        : widget.listing.bundleTitle,
  );
  late final discount = TextEditingController(
    text: widget.listing.bundleDiscountPercent == 0
        ? '10'
        : widget.listing.bundleDiscountPercent.toStringAsFixed(0),
  );
  late final selected = widget.listing.bundleListingIds.isEmpty
      ? <String>{widget.listing.id}
      : widget.listing.bundleListingIds.toSet();
  bool saving = false;

  @override
  void dispose() {
    title.dispose();
    discount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final percentage = double.tryParse(discount.text);
    if (title.text.trim().length < 3 ||
        selected.length < 2 ||
        percentage == null ||
        percentage < 5 ||
        percentage > 50) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Select at least two items and check the discount.'),
        ),
      );
      return;
    }
    setState(() => saving = true);
    try {
      await context.read<LiveRentHubController>().saveListingBundle(
        widget.listing.id,
        {
          'active': true,
          'title': title.text.trim(),
          'listingIds': selected.toList(),
          'discountPercent': percentage,
        },
      );
      if (mounted) Navigator.pop(context);
    } catch (exception) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(exception.toString())));
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> _clear() async {
    final accepted = await confirmAction(
      context,
      title: 'Remove bundle offer?',
      message: 'The bundle will no longer appear on this listing.',
      action: 'Remove',
      destructive: true,
    );
    if (!accepted || !mounted) return;
    await context
        .read<LiveRentHubController>()
        .clearListingBundle(widget.listing.id);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final options = context
        .watch<LiveRentHubController>()
        .ownerListings
        .where((item) => !item.isService && item.status == 'active')
        .toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Bundle Offer')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              controller: title,
              decoration: const InputDecoration(labelText: 'Bundle title'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: discount,
              keyboardType: TextInputType.number,
              decoration:
                  const InputDecoration(labelText: 'Bundle discount (%)'),
            ),
            const SizedBox(height: 16),
            Text('Select 2 to 5 physical listings',
                style: Theme.of(context).textTheme.titleMedium),
            for (final item in options)
              CheckboxListTile(
                value: selected.contains(item.id),
                title: Text(item.title),
                subtitle: Text(formatMoney(item.dailyPrice)),
                onChanged: item.id == widget.listing.id
                    ? null
                    : (value) => setState(() {
                          if (value == true && selected.length < 5) {
                            selected.add(item.id);
                          } else if (value == false) {
                            selected.remove(item.id);
                          }
                        }),
              ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: saving ? null : _save,
              child: Text(saving ? 'Saving…' : 'Save Bundle'),
            ),
            if (widget.listing.bundleTitle.isNotEmpty)
              TextButton(
                onPressed: saving ? null : _clear,
                child: const Text('Remove Bundle'),
              ),
          ],
        ),
      ),
    );
  }
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
        onPressed: () async {
          if (rental.listingType == 'service') {
            await _run(context, 'start-service');
            return;
          }
          try {
            final evidence = await context
                .read<LiveRentHubController>()
                .pickAndUpload(purpose: 'handover_evidence');
            if (evidence != null && context.mounted) {
              await _run(
                context,
                'handover',
                body: {
                  'condition': 'Excellent',
                  'notes': 'Confirmed through the live Owner interface.',
                  'evidence': [evidence],
                },
              );
            }
          } catch (exception) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(exception.toString())),
              );
            }
          }
        },
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
    final existingDispute =
        context.watch<LiveRentHubController>().disputeForRental(rental.id);
    final canDispute = !['cancelled', 'scheduled'].contains(rental.status);
    final disputeAction = canDispute
        ? OutlinedButton.icon(
            onPressed: () => Navigator.push<void>(
              context,
              MaterialPageRoute(
                builder: (_) => LiveDisputePage(rental: rental, owner: true),
              ),
            ),
            icon: Icon(existingDispute == null
                ? Icons.gavel_outlined
                : Icons.manage_search_outlined),
            label: Text(
              existingDispute == null ? 'Raise Dispute' : 'Manage Dispute',
            ),
          )
        : null;
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
            if (action != null || disputeAction != null) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (action != null) action,
                  if (disputeAction != null) disputeAction,
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

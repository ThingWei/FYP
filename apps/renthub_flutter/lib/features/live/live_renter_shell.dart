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
  final queryController = TextEditingController();
  String category = 'All';
  DiscoveryFilters filters = const DiscoveryFilters();
  List<Listing>? results;
  bool searching = false;

  @override
  void dispose() {
    queryController.dispose();
    super.dispose();
  }

  Future<void> _applyFilters({String? quickCategory}) async {
    final nextCategory = quickCategory ?? category;
    setState(() => searching = true);
    try {
      final found =
          await context.read<LiveRentHubController>().discoverListings({
        'search': queryController.text,
        if (nextCategory != 'All') 'category': nextCategory,
        if (filters.type != 'all') 'type': filters.type,
        'location': filters.location,
        'minPrice': filters.minimumPrice,
        'maxPrice': filters.maximumPrice,
        if (filters.verifiedOnly) 'verified': 'true',
        if (filters.promotionsOnly) 'promoted': 'true',
        'sort': filters.sort,
        if (filters.dates != null)
          'availableFrom': filters.dates!.start.toIso8601String(),
        if (filters.dates != null)
          'availableTo':
              filters.dates!.end.add(const Duration(days: 1)).toIso8601String(),
        'limit': '100',
      });
      if (mounted) {
        setState(() {
          category = nextCategory;
          results = found;
        });
      }
    } catch (exception) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(exception.toString())));
      }
    } finally {
      if (mounted) setState(() => searching = false);
    }
  }

  Future<void> _openFilters() async {
    final selected = await Navigator.push<DiscoveryFilters>(
      context,
      MaterialPageRoute(
        builder: (_) => LiveDiscoveryFilterPage(initial: filters),
      ),
    );
    if (selected == null || !mounted) return;
    filters = selected;
    await _applyFilters();
  }

  Future<void> _refresh() async {
    await context.read<LiveRentHubController>().loadRenter();
    if (mounted) setState(() => results = null);
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<LiveRentHubController>();
    var listings = (results ??
            (widget.featuredOnly && controller.recommendedListings.isNotEmpty
                ? controller.recommendedListings
                : controller.listings))
        .where((listing) => listing.status == 'active')
        .toList();
    if (widget.featuredOnly && listings.length > 6) {
      listings = listings.take(6).toList();
    }
    return Scaffold(
      appBar: AppBar(
        title: widget.featuredOnly ? const RentHubLogo() : Text(widget.title),
        actions: [
          IconButton(
            tooltip: 'Wishlist',
            onPressed: () => Navigator.push<void>(
              context,
              MaterialPageRoute(
                builder: (_) => const LiveSavedListingsPage(),
              ),
            ),
            icon: const Icon(Icons.favorite_outline),
          ),
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
              controller: queryController,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _applyFilters(),
              decoration: InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search rentals and services',
                suffixIcon: IconButton(
                  tooltip: 'Search',
                  onPressed: searching ? null : _applyFilters,
                  icon: const Icon(Icons.arrow_forward),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: searching ? null : _openFilters,
                    icon: const Icon(Icons.tune),
                    label: Text(
                      filters.activeCount == 0
                          ? 'Filters & sorting'
                          : '${filters.activeCount} filters active',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () => Navigator.push<void>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const LiveComparisonPage(),
                    ),
                  ),
                  icon: const Icon(Icons.compare_arrows),
                  label:
                      Text('Compare (${controller.comparisonListings.length})'),
                ),
              ],
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
                        onSelected: (_) => _applyFilters(quickCategory: value),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (searching) const LinearProgressIndicator(),
            if (searching) const SizedBox(height: 8),
            if (widget.featuredOnly)
              Text(
                controller.recommendedListings.isEmpty
                    ? 'Marketplace highlights'
                    : 'Recommended for you',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            Text(
              '${listings.length} listing${listings.length == 1 ? '' : 's'}',
              style: const TextStyle(color: AppColors.secondaryText),
            ),
            const SizedBox(height: 8),
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
                              clipBehavior: Clip.antiAlias,
                              decoration: BoxDecoration(
                                color: AppColors.primaryLight,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: listing.images.isEmpty
                                  ? Icon(
                                      listing.isService
                                          ? Icons.design_services_outlined
                                          : Icons.inventory_2_outlined,
                                      color: AppColors.primaryDark,
                                    )
                                  : Image.network(
                                      controller.api
                                          .absoluteUrl(listing.images.first),
                                      fit: BoxFit.cover,
                                      semanticLabel: '${listing.title} image',
                                      errorBuilder: (_, __, ___) => Icon(
                                        listing.isService
                                            ? Icons.design_services_outlined
                                            : Icons.inventory_2_outlined,
                                        color: AppColors.primaryDark,
                                      ),
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
                            Column(
                              children: [
                                IconButton(
                                  tooltip: controller.isSaved(listing.id)
                                      ? 'Remove from wishlist'
                                      : 'Save to wishlist',
                                  onPressed: () =>
                                      controller.toggleSavedListing(listing),
                                  icon: Icon(
                                    controller.isSaved(listing.id)
                                        ? Icons.favorite
                                        : Icons.favorite_outline,
                                    color: controller.isSaved(listing.id)
                                        ? AppColors.error
                                        : AppColors.secondaryText,
                                  ),
                                ),
                                IconButton(
                                  tooltip: controller.isCompared(listing.id)
                                      ? 'Remove from comparison'
                                      : 'Add to comparison',
                                  onPressed: () async {
                                    try {
                                      await controller
                                          .toggleComparisonListing(listing);
                                    } catch (exception) {
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          SnackBar(
                                            content: Text(exception.toString()),
                                          ),
                                        );
                                      }
                                    }
                                  },
                                  icon: Icon(
                                    controller.isCompared(listing.id)
                                        ? Icons.compare_arrows
                                        : Icons.compare_arrows_outlined,
                                    color: controller.isCompared(listing.id)
                                        ? AppColors.primary
                                        : AppColors.secondaryText,
                                  ),
                                ),
                              ],
                            ),
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

class DiscoveryFilters {
  const DiscoveryFilters({
    this.type = 'all',
    this.location = '',
    this.minimumPrice = '',
    this.maximumPrice = '',
    this.verifiedOnly = false,
    this.promotionsOnly = false,
    this.sort = 'recommended',
    this.dates,
  });

  final String type, location, minimumPrice, maximumPrice, sort;
  final bool verifiedOnly, promotionsOnly;
  final DateTimeRange? dates;

  int get activeCount =>
      (type == 'all' ? 0 : 1) +
      (location.isEmpty ? 0 : 1) +
      (minimumPrice.isEmpty && maximumPrice.isEmpty ? 0 : 1) +
      (verifiedOnly ? 1 : 0) +
      (promotionsOnly ? 1 : 0) +
      (dates == null ? 0 : 1) +
      (sort == 'recommended' ? 0 : 1);
}

class LiveDiscoveryFilterPage extends StatefulWidget {
  const LiveDiscoveryFilterPage({super.key, required this.initial});

  final DiscoveryFilters initial;

  @override
  State<LiveDiscoveryFilterPage> createState() =>
      _LiveDiscoveryFilterPageState();
}

class _LiveDiscoveryFilterPageState extends State<LiveDiscoveryFilterPage> {
  late String type = widget.initial.type;
  late String sort = widget.initial.sort;
  late bool verifiedOnly = widget.initial.verifiedOnly;
  late bool promotionsOnly = widget.initial.promotionsOnly;
  late DateTimeRange? dates = widget.initial.dates;
  late final location = TextEditingController(text: widget.initial.location);
  late final minimumPrice =
      TextEditingController(text: widget.initial.minimumPrice);
  late final maximumPrice =
      TextEditingController(text: widget.initial.maximumPrice);

  @override
  void dispose() {
    location.dispose();
    minimumPrice.dispose();
    maximumPrice.dispose();
    super.dispose();
  }

  Future<void> _pickDates() async {
    final selected = await showDateRangePicker(
      context: context,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 730)),
      initialDateRange: dates,
    );
    if (selected != null) setState(() => dates = selected);
  }

  void _apply() {
    final minimum = double.tryParse(minimumPrice.text);
    final maximum = double.tryParse(maximumPrice.text);
    if (minimum != null && maximum != null && minimum > maximum) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Minimum price cannot exceed maximum.')),
      );
      return;
    }
    Navigator.pop(
      context,
      DiscoveryFilters(
        type: type,
        location: location.text.trim(),
        minimumPrice: minimumPrice.text.trim(),
        maximumPrice: maximumPrice.text.trim(),
        verifiedOnly: verifiedOnly,
        promotionsOnly: promotionsOnly,
        sort: sort,
        dates: dates,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Discovery Filters'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(
                context,
                const DiscoveryFilters(),
              ),
              child: const Text('Reset'),
            ),
          ],
        ),
        bottomNavigationBar: SafeArea(
          minimum: const EdgeInsets.all(16),
          child: FilledButton(
            onPressed: _apply,
            child: const Text('Apply Filters'),
          ),
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              DropdownButtonFormField<String>(
                initialValue: type,
                decoration: const InputDecoration(labelText: 'Listing type'),
                items: const [
                  DropdownMenuItem(
                      value: 'all', child: Text('Items and services')),
                  DropdownMenuItem(
                      value: 'physical', child: Text('Physical items')),
                  DropdownMenuItem(value: 'service', child: Text('Services')),
                ],
                onChanged: (value) => setState(() => type = value ?? 'all'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: location,
                decoration: const InputDecoration(
                  labelText: 'Location',
                  hintText: 'Kuala Lumpur',
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: minimumPrice,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Min RM'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: maximumPrice,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Max RM'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Availability'),
                subtitle: Text(
                  dates == null
                      ? 'Any date'
                      : formatDateRange(dates!.start, dates!.end),
                ),
                trailing: dates == null
                    ? const Icon(Icons.calendar_month_outlined)
                    : IconButton(
                        tooltip: 'Clear dates',
                        onPressed: () => setState(() => dates = null),
                        icon: const Icon(Icons.close),
                      ),
                onTap: _pickDates,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Verified Owners only'),
                value: verifiedOnly,
                onChanged: (value) => setState(() => verifiedOnly = value),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Active promotions only'),
                value: promotionsOnly,
                onChanged: (value) => setState(() => promotionsOnly = value),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: sort,
                decoration: const InputDecoration(labelText: 'Sort by'),
                items: const [
                  DropdownMenuItem(
                      value: 'recommended', child: Text('Recommended')),
                  DropdownMenuItem(
                      value: 'price_asc', child: Text('Price: low to high')),
                  DropdownMenuItem(
                      value: 'price_desc', child: Text('Price: high to low')),
                  DropdownMenuItem(
                      value: 'rating', child: Text('Highest rated')),
                  DropdownMenuItem(value: 'newest', child: Text('Newest')),
                  DropdownMenuItem(
                      value: 'trust', child: Text('Owner trust score')),
                ],
                onChanged: (value) =>
                    setState(() => sort = value ?? 'recommended'),
              ),
            ],
          ),
        ),
      );
}

class LiveSavedListingsPage extends StatelessWidget {
  const LiveSavedListingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<LiveRentHubController>();
    return Scaffold(
      appBar: AppBar(title: const Text('Wishlist')),
      body: controller.savedListings.isEmpty
          ? const RentHubFeedbackState(
              kind: FeedbackKind.empty,
              title: 'Your wishlist is empty',
              message: 'Save listings from Home or Explore to find them here.',
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: controller.savedListings.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final listing = controller.savedListings[index];
                return Card(
                  child: ListTile(
                    leading: Icon(
                      listing.isService
                          ? Icons.design_services_outlined
                          : Icons.inventory_2_outlined,
                    ),
                    title: Text(listing.title),
                    subtitle: Text(
                      '${formatMoney(listing.displayPrice)} / ${listing.priceUnit} · ${listing.location}',
                    ),
                    trailing: IconButton(
                      tooltip: 'Remove from wishlist',
                      onPressed: () => controller.toggleSavedListing(listing),
                      icon: const Icon(Icons.favorite, color: AppColors.error),
                    ),
                    onTap: () => Navigator.push<void>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => LiveBookingPage(
                          listing: listing,
                          onSubmitted: () {},
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class LiveComparisonPage extends StatelessWidget {
  const LiveComparisonPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<LiveRentHubController>();
    final listings = controller.comparisonListings;
    return Scaffold(
      appBar: AppBar(
        title: Text('Compare (${listings.length}/4)'),
        actions: [
          if (listings.isNotEmpty)
            IconButton(
              tooltip: 'Clear comparison',
              onPressed: () async {
                final accepted = await confirmAction(
                  context,
                  title: 'Clear comparison?',
                  message: 'All selected listings will be removed.',
                  action: 'Clear',
                );
                if (accepted) await controller.clearComparison();
              },
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ),
      body: listings.isEmpty
          ? const RentHubFeedbackState(
              kind: FeedbackKind.empty,
              title: 'Nothing to compare',
              message: 'Select up to four listings from Home or Explore.',
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              scrollDirection: Axis.horizontal,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final listing in listings)
                    SizedBox(
                      width: 260,
                      child: Card(
                        margin: const EdgeInsets.only(right: 12),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                listing.isService
                                    ? Icons.design_services_outlined
                                    : Icons.inventory_2_outlined,
                                size: 40,
                                color: AppColors.primary,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                listing.title,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const Divider(height: 24),
                              Text(
                                  '${formatMoney(listing.displayPrice)} / ${listing.priceUnit}'),
                              Text(
                                  'Type: ${listing.isService ? 'Service' : 'Physical item'}'),
                              if (!listing.isService)
                                Text('Condition: ${listing.condition}'),
                              Text(
                                  'Rating: ${listing.rating.toStringAsFixed(1)} / 5'),
                              Text(
                                  'Owner trust: ${listing.ownerTrustScore.toStringAsFixed(0)} / 100'),
                              Text('Location: ${listing.location}'),
                              Text(
                                  'Verified: ${listing.verified ? 'Yes' : 'No'}'),
                              const SizedBox(height: 12),
                              OutlinedButton.icon(
                                onPressed: () =>
                                    controller.toggleComparisonListing(listing),
                                icon: const Icon(Icons.close),
                                label: const Text('Remove'),
                              ),
                            ],
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

  Future<void> _reportTarget(
    String targetType,
    String targetId,
    String label,
  ) async {
    var reason = 'misleading';
    final details = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Report $label'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: reason,
                decoration: const InputDecoration(labelText: 'Reason'),
                items: const [
                  DropdownMenuItem(
                    value: 'misleading',
                    child: Text('Misleading'),
                  ),
                  DropdownMenuItem(
                    value: 'prohibited',
                    child: Text('Prohibited content'),
                  ),
                  DropdownMenuItem(
                      value: 'scam', child: Text('Suspected scam')),
                  DropdownMenuItem(
                    value: 'harassment',
                    child: Text('Harassment'),
                  ),
                  DropdownMenuItem(
                    value: 'inappropriate',
                    child: Text('Inappropriate'),
                  ),
                  DropdownMenuItem(value: 'other', child: Text('Other')),
                ],
                onChanged: (value) =>
                    setDialogState(() => reason = value ?? reason),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: details,
                maxLines: 3,
                maxLength: 1000,
                decoration: InputDecoration(
                  labelText: reason == 'other'
                      ? 'Details (required)'
                      : 'Details (optional)',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(
                context,
                reason != 'other' || details.text.trim().length >= 5,
              ),
              child: const Text('Submit Report'),
            ),
          ],
        ),
      ),
    );
    if (accepted != true || !mounted) {
      details.dispose();
      return;
    }
    try {
      await context.read<LiveRentHubController>().submitModerationReport(
            targetType: targetType,
            targetId: targetId,
            reason: reason,
            details: details.text,
          );
      if (mounted) showMockSuccess(context, 'Report submitted for review');
    } catch (exception) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(exception.toString())));
      }
    }
    details.dispose();
  }

  Future<void> _blockOwner() async {
    final accepted = await confirmAction(
      context,
      title: 'Block ${widget.listing.ownerName}?',
      message:
          'They will be added to your blocked-user list. Existing bookings are not cancelled.',
      action: 'Block Owner',
    );
    if (!accepted || !mounted) return;
    try {
      await context
          .read<LiveRentHubController>()
          .blockUser(widget.listing.ownerId);
      if (mounted) showMockSuccess(context, 'Owner blocked');
    } catch (exception) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(exception.toString())));
      }
    }
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
      appBar: AppBar(
        title: Text(listing.isService ? 'Book Service' : 'Rent Item'),
        actions: [
          Consumer<LiveRentHubController>(
            builder: (context, controller, _) => IconButton(
              tooltip: controller.isSaved(listing.id)
                  ? 'Remove from wishlist'
                  : 'Save to wishlist',
              onPressed: () => controller.toggleSavedListing(listing),
              icon: Icon(
                controller.isSaved(listing.id)
                    ? Icons.favorite
                    : Icons.favorite_outline,
              ),
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Safety actions',
            onSelected: (value) {
              if (value == 'listing') {
                _reportTarget('listing', listing.id, 'listing');
              } else if (value == 'owner') {
                _reportTarget('user', listing.ownerId, 'Owner');
              } else if (value == 'block') {
                _blockOwner();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'listing', child: Text('Report listing')),
              PopupMenuItem(value: 'owner', child: Text('Report Owner')),
              PopupMenuItem(value: 'block', child: Text('Block Owner')),
            ],
          ),
        ],
      ),
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
            if (listing.images.isNotEmpty) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Image.network(
                    context
                        .read<LiveRentHubController>()
                        .api
                        .absoluteUrl(listing.images.first),
                    fit: BoxFit.cover,
                    semanticLabel: '${listing.title} image',
                    errorBuilder: (_, __, ___) => ColoredBox(
                      color: AppColors.primaryLight,
                      child: Icon(
                        listing.isService
                            ? Icons.design_services_outlined
                            : Icons.inventory_2_outlined,
                        size: 56,
                        color: AppColors.primaryDark,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
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
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${review.authorName} • ${review.rating}/5',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              TextButton(
                                onPressed: () => _reportTarget(
                                  'review',
                                  review.id,
                                  'review',
                                ),
                                child: const Text('Report'),
                              ),
                            ],
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
                            if (rental.listingType == 'physical')
                              Text(
                                'Local agreement: ${rental.blockchainStatus}',
                                style: const TextStyle(
                                  color: AppColors.secondaryText,
                                ),
                              ),
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
                    'Select a condition photo after confirming. The file will be stored privately with the rental.',
                action: 'Submit Return',
              );
              if (accepted && context.mounted) {
                try {
                  final evidence = await context
                      .read<LiveRentHubController>()
                      .pickAndUpload(purpose: 'return_evidence');
                  if (evidence != null && context.mounted) {
                    await _action(
                      context,
                      'return',
                      {
                        'condition': 'Good',
                        'notes': 'Returned through the live Flutter flow.',
                        'evidence': [evidence],
                      },
                      'Return evidence submitted',
                    );
                  }
                } catch (exception) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(exception.toString())),
                    );
                  }
                }
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

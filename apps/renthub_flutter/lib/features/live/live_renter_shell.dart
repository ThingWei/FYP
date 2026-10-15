import 'live_location_picker.dart';
import 'live_location_field.dart';
import 'live_booking_locations.dart';
import 'live_booking_charges.dart';
import '../../core/network/user_facing_error.dart';
import '../../core/validation/input_validation.dart';
import '../../core/validation/input_rules.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/network/idempotency_key.dart';
import '../../core/network/api_client.dart';
import '../../core/utils/calendar_date.dart';
import '../../shared/models/domain_models.dart';
import '../../shared/widgets/account_components.dart';
import '../../shared/widgets/renthub_components.dart';
import '../renter/booking/booking_flow.dart' show formatDateRange, formatMoney;
import 'live_renthub_controller.dart';
import 'live_photo_widgets.dart';
import 'live_agreement.dart';
import 'live_checkout_page.dart';
import 'live_dispute_page.dart';
import 'live_review_page.dart';
import 'live_recommendations.dart';
import 'live_listing_collection.dart';
import 'live_comparison.dart';
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
    final index = controller.renterTabIndex;
    final pages = [
      LiveMarketplacePage(
        title: 'RentHub',
        featuredOnly: true,
        onOpenBookings: () => controller.selectRenterTab(2),
      ),
      LiveMarketplacePage(
        title: 'Explore',
        onOpenBookings: () => controller.selectRenterTab(2),
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
                message: 'Getting your marketplace ready…',
              ),
            )
          : controller.error != null && controller.profile == null
              ? SafeArea(
                  child: RentHubFeedbackState(
                    kind: FeedbackKind.error,
                    title: controller.errorTitle,
                    message: controller.error!,
                    actionLabel: controller.sessionExpired
                        ? 'Sign in again'
                        : 'Try Again',
                    onAction:
                        controller.sessionExpired ? widget.onLogout : _load,
                  ),
                )
              : IndexedStack(index: index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: controller.selectRenterTab,
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
  DiscoveryFilters filters = const DiscoveryFilters();
  List<Listing>? results;
  bool searching = false;
  int searchGeneration = 0;
  String? resultQuery;
  String? _marketplaceAccount;
  late ListingViewMode viewMode =
      widget.featuredOnly ? ListingViewMode.carousel : ListingViewMode.grid;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final account = context.watch<LiveRentHubController>().profile?.id;
    if (_marketplaceAccount != account) {
      _marketplaceAccount = account;
      results = null;
      resultQuery = null;
      filters = const DiscoveryFilters();
      queryController.clear();
      searchGeneration++;
      searching = false;
    }
  }

  @override
  void dispose() {
    queryController.dispose();
    super.dispose();
  }

  Future<void> _applyFilters() async {
    if (!InputValidation.validate(context)) return;
    final nextCategory = filters.category;
    final request = ++searchGeneration;
    final useRecommendations =
        widget.featuredOnly && filters.sort == 'recommended';
    setState(() => searching = true);
    try {
      final parameters = <String, String>{
        'search': queryController.text,
        if (nextCategory != 'All') 'category': nextCategory,
        if (filters.type != 'all') 'type': filters.type,
        if (filters.centre == null) 'location': filters.location,
        if (filters.centre != null) ...{
          'latitude': filters.centre!.point.latitude.toString(),
          'longitude': filters.centre!.point.longitude.toString(),
          'radiusKm': filters.radiusKm.toString()
        },
        'minPrice': filters.minimumPrice,
        'maxPrice': filters.maximumPrice,
        if (filters.verifiedOnly) 'verified': 'true',
        if (filters.promotionsOnly) 'promoted': 'true',
        if (filters.dates != null)
          'availableFrom': calendarDateApiValue(filters.dates!.start),
        if (filters.dates != null)
          'availableTo': calendarDateApiValue(
            filters.dates!.end.add(const Duration(days: 1)),
          ),
      };
      final queryKey =
          Uri(queryParameters: {...parameters, 'sort': filters.sort}).query;
      if (queryKey != resultQuery) {
        setState(() {
          results = [];
          resultQuery = queryKey;
        });
      }
      final controller = context.read<LiveRentHubController>();
      if (widget.featuredOnly) {
        controller.recommendationFilters = {
          for (final entry in parameters.entries)
            if (entry.value.isNotEmpty &&
                !['latitude', 'longitude', 'radiusKm'].contains(entry.key))
              entry.key: entry.value
        };
        controller.setRecommendationArea(filters.centre, filters.radiusKm);
      }
      final found = useRecommendations
          ? await controller.recommendListings({
              ...parameters,
              'limit': '30',
            })
          : await controller.discoverListings({
              ...parameters,
              'sort': filters.sort,
              'limit': '100',
            });
      if (mounted && request == searchGeneration) {
        setState(() {
          results = found;
        });
      }
    } catch (exception) {
      if (mounted && request == searchGeneration) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyError(exception))));
      }
    } finally {
      if (mounted && request == searchGeneration) {
        setState(() => searching = false);
      }
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
    if (mounted && widget.featuredOnly) {
      await context.read<LiveRentHubController>().refreshRecommendationFeed();
    }
    if (!mounted) return;
    if (filters.activeCount > 0 || queryController.text.isNotEmpty) {
      await _applyFilters();
    } else {
      setState(() => results = null);
    }
  }

  Future<void> _openListing(Listing listing) => Navigator.push<void>(
      context,
      MaterialPageRoute(
          builder: (_) => LiveBookingPage(
              listing: listing, onSubmitted: widget.onOpenBookings)));

  Widget _recommendationActions(Listing listing) {
    final controller = context.read<LiveRentHubController>();
    return Row(mainAxisSize: MainAxisSize.min, children: [
      IconButton(
          tooltip: controller.isSaved(listing.id)
              ? 'Remove from wishlist'
              : 'Save to wishlist',
          onPressed: () async {
            try {
              await controller.toggleSavedListing(listing);
            } catch (e) {
              if (mounted) {
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text(friendlyError(e))));
              }
            }
          },
          color: controller.isSaved(listing.id) ? AppColors.error : null,
          icon: Icon(controller.isSaved(listing.id)
              ? Icons.favorite
              : Icons.favorite_outline)),
      if (!listing.isService)
        IconButton(
            tooltip: controller.isCompared(listing.id)
                ? 'Remove from comparison'
                : 'Add to comparison',
            onPressed: () => toggleLiveComparison(context, listing),
            icon: Icon(controller.isCompared(listing.id)
                ? Icons.compare_arrows
                : Icons.compare_arrows_outlined)),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<LiveRentHubController>();
    final showingAiRecommendations =
        widget.featuredOnly && filters.sort == 'recommended';
    var listings = ((widget.featuredOnly &&
                    results != null &&
                    filters.sort == 'recommended'
                ? controller.recommendationSections['recommended']?.items
                : null) ??
            results ??
            (widget.featuredOnly && controller.recommendedListings.isNotEmpty
                ? controller.recommendedListings
                : controller.listings))
        .where((listing) => listing.status == 'active')
        .toList();
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
            TextFormField(
              controller: queryController,
              textInputAction: TextInputAction.search,
              onFieldSubmitted: (_) => _applyFilters(),
              onChanged: (_) => setState(() {}),
              decoration: (InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search rentals and services',
                suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (queryController.text.isNotEmpty)
                    IconButton(
                      tooltip: 'Clear search',
                      onPressed: () {
                        queryController.clear();
                        _applyFilters();
                      },
                      icon: const Icon(Icons.close),
                    ),
                  IconButton(
                    tooltip: 'Search',
                    onPressed: searching ? null : _applyFilters,
                    icon: const Icon(Icons.arrow_forward),
                  )
                ]),
              )).copyWith(counterText: '', errorMaxLines: 3),
              validator: InputRules.searchRentalsAndServices.validate,
              inputFormatters: InputValidation.formatters(
                  InputRules.searchRentalsAndServices, queryController),
              autovalidateMode: AutovalidateMode.onUserInteraction,
              maxLength: InputRules.searchRentalsAndServices.maxLength,
              maxLengthEnforcement: InputValidation.lengthEnforcement,
            ),
            const SizedBox(height: 12),
            Row(children: [
              IconButton.outlined(
                  tooltip: 'Filters and sorting',
                  onPressed: searching ? null : _openFilters,
                  icon: Badge(
                      isLabelVisible: filters.activeCount > 0,
                      label: Text('${filters.activeCount}'),
                      child: const Icon(Icons.tune))),
              const SizedBox(width: 8),
              IconButton(
                  tooltip: 'Compare (${controller.comparisonListings.length})',
                  onPressed: () => Navigator.push<void>(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const LiveComparisonPage())),
                  icon: Badge(
                      isLabelVisible: controller.comparisonListings.isNotEmpty,
                      label: Text('${controller.comparisonListings.length}'),
                      child: const Icon(Icons.compare_arrows))),
              const Spacer(),
              ListingViewSwitcher(
                  value: viewMode,
                  carousel: widget.featuredOnly,
                  onChanged: (value) => setState(() => viewMode = value)),
            ]),
            const SizedBox(height: 16),
            if (widget.featuredOnly && results == null)
              LiveRecommendationHomeContent(
                  onOpen: _openListing,
                  actions: _recommendationActions,
                  viewMode: viewMode)
            else ...[
              if (widget.featuredOnly)
                TextButton(
                    onPressed: () => setState(() => results = null),
                    child: const Text('Back to recommendations')),
              if (searching) const LinearProgressIndicator(),
              if (searching) const SizedBox(height: 8),
              if (widget.featuredOnly)
                Text(
                  showingAiRecommendations
                      ? ((results == null &&
                              controller.recommendedListings.isEmpty)
                          ? 'Marketplace highlights'
                          : 'Recommended for you')
                      : 'Marketplace results',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              Text(
                '${listings.length} listing${listings.length == 1 ? '' : 's'}',
                style: const TextStyle(color: AppColors.secondaryText),
              ),
              const SizedBox(height: 8),
              if (searching && listings.isEmpty)
                const SizedBox(
                    height: 200,
                    child: Center(child: CircularProgressIndicator()))
              else if (listings.isEmpty)
                const SizedBox(
                  height: 360,
                  child: RentHubFeedbackState(
                    kind: FeedbackKind.empty,
                    title: 'No matching listings',
                    message: 'Try another category or search term.',
                  ),
                )
              else
                ListingCollection(
                    items: listings,
                    mode: viewMode == ListingViewMode.carousel
                        ? ListingViewMode.grid
                        : viewMode,
                    onOpen: _openListing,
                    actions: _recommendationActions),
            ],
          ],
        ),
      ),
    );
  }
}

class DiscoveryFilters {
  const DiscoveryFilters({
    this.category = 'All',
    this.type = 'all',
    this.location = '',
    this.centre,
    this.radiusKm = 10,
    this.minimumPrice = '',
    this.maximumPrice = '',
    this.verifiedOnly = false,
    this.promotionsOnly = false,
    this.sort = 'recommended',
    this.dates,
  });

  final String category, type, location, minimumPrice, maximumPrice, sort;
  final ListingLocationSelection? centre;
  final int radiusKm;
  final bool verifiedOnly, promotionsOnly;
  final DateTimeRange? dates;

  int get activeCount =>
      (category == 'All' ? 0 : 1) +
      (type == 'all' ? 0 : 1) +
      (location.isEmpty && centre == null ? 0 : 1) +
      (minimumPrice.isEmpty && maximumPrice.isEmpty ? 0 : 1) +
      (verifiedOnly ? 1 : 0) +
      (promotionsOnly ? 1 : 0) +
      (dates == null ? 0 : 1) +
      (sort == 'recommended' ? 0 : 1);
}

class LiveDiscoveryFilterPage extends StatefulWidget {
  const LiveDiscoveryFilterPage(
      {super.key, required this.initial, this.locationMapBuilder});

  final DiscoveryFilters initial;
  final LocationMapBuilder? locationMapBuilder;

  @override
  State<LiveDiscoveryFilterPage> createState() =>
      _LiveDiscoveryFilterPageState();
}

class _LiveDiscoveryFilterPageState extends State<LiveDiscoveryFilterPage> {
  late String category = widget.initial.category;
  late ListingLocationSelection? centre = widget.initial.centre;
  late int radiusKm = widget.initial.radiusKm;
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
    if (!InputValidation.validate(context)) return;
    final minimum = double.tryParse(minimumPrice.text);
    final maximum = double.tryParse(maximumPrice.text);
    if (minimum != null && maximum != null && minimum > maximum) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Minimum price cannot exceed maximum.')),
      );
      return;
    }
    InputValidation.popIfValid(
      context,
      DiscoveryFilters(
        category: category,
        type: type,
        location: centre == null ? location.text.trim() : '',
        centre: centre,
        radiusKm: radiusKm,
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
              Text('Categories',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 4, children: [
                for (final value in const [
                  'All',
                  'Devices',
                  'Vehicles',
                  'Equipment',
                  'Clothing',
                  'Books',
                  'Services'
                ])
                  FilterChip(
                      label: Text(value),
                      selected: category == value,
                      onSelected: (_) => setState(() => category = value)),
              ]),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                isExpanded: true,
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
              LiveLocationField(
                  mapBuilder: widget.locationMapBuilder,
                  api: ListingLocationApi(
                      context.read<LiveRentHubController>().api),
                  controller: location,
                  value: centre,
                  searchAreaOnly: true,
                  requirePin: false,
                  allowEmpty: true,
                  maxLength: 100,
                  onChanged: (value) => setState(() => centre = value)),
              if (centre != null) ...[
                DropdownButtonFormField<int>(
                    isExpanded: true,
                    initialValue: radiusKm,
                    decoration:
                        const InputDecoration(labelText: 'Search radius'),
                    items: [5, 10, 25, 50]
                        .map((km) =>
                            DropdownMenuItem(value: km, child: Text('$km km')))
                        .toList(),
                    onChanged: (value) => setState(() => radiusKm = value!)),
                const Text(
                    'Nearby results use approximate public locations. Listings without pins are not included.')
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: minimumPrice,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: (const InputDecoration(labelText: 'Min RM'))
                          .copyWith(counterText: '', errorMaxLines: 3),
                      validator: InputRules.minRm.validate,
                      inputFormatters: InputValidation.formatters(
                          InputRules.minRm, minimumPrice),
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                      maxLength: InputRules.minRm.maxLength,
                      maxLengthEnforcement: InputValidation.lengthEnforcement,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: maximumPrice,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: (const InputDecoration(labelText: 'Max RM'))
                          .copyWith(counterText: '', errorMaxLines: 3),
                      validator: (value) {
                        final error = InputRules.maxRm.validate(value);
                        if (error != null) return error;
                        final minimum = double.tryParse(minimumPrice.text);
                        final maximum = double.tryParse(value ?? '');
                        return minimum != null &&
                                maximum != null &&
                                minimum > maximum
                            ? 'Maximum price must be at least minimum price'
                            : null;
                      },
                      inputFormatters: InputValidation.formatters(
                          InputRules.maxRm, maximumPrice),
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                      maxLength: InputRules.maxRm.maxLength,
                      maxLengthEnforcement: InputValidation.lengthEnforcement,
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
                isExpanded: true,
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
    final c = context.watch<LiveRentHubController>();
    void open(Listing listing, {bool chooseDates = false}) {
      Navigator.push<void>(
          context,
          MaterialPageRoute(
              builder: (_) => LiveBookingPage(
                  listing: listing,
                  chooseDatesInitially: chooseDates,
                  onSubmitted: () => c.selectRenterTab(2))));
    }

    return Scaffold(
        appBar: AppBar(
            title: Text('Compare (${c.comparisonListings.length}/3)'),
            actions: [
              if (c.comparisonListings.isNotEmpty)
                IconButton(
                    tooltip: 'Clear comparison',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      final accepted = await confirmAction(context,
                          title: 'Clear comparison?',
                          message: 'All selected listings will be removed.',
                          action: 'Clear');
                      if (accepted) {
                        try {
                          await c.clearComparison();
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(friendlyError(e))));
                          }
                        }
                      }
                    }),
            ]),
        body: LiveComparisonContent(
            onOpen: (listing) => open(listing),
            onChooseDates: (listing) => open(listing, chooseDates: true)));
  }
}

class LiveBookingPage extends StatefulWidget {
  const LiveBookingPage({
    super.key,
    required this.listing,
    required this.onSubmitted,
    this.locationMapBuilder,
    this.chooseDatesInitially = false,
  });

  final Listing listing;
  final VoidCallback onSubmitted;
  final LocationMapBuilder? locationMapBuilder;
  final bool chooseDatesInitially;

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
  bool agreementAccepted = false;
  String? reviewedAgreementVersion;
  final venue = TextEditingController(text: '');
  final delivery = TextEditingController();
  ListingLocationSelection? serviceLocation, deliveryLocation;
  final note = TextEditingController();
  bool submitting = false;
  bool checkingIdentity = false;
  bool availabilityLoading = true;
  bool availabilityRequested = false;
  bool initialDatePickerOpened = false;
  String? availabilityError;
  ListingAvailability? availability;
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
    if (!availabilityRequested) {
      availabilityRequested = true;
      context
          .read<LiveRentHubController>()
          .recordListingView(widget.listing.id);
      _loadAvailability();
    }
  }

  Future<void> _loadAvailability() async {
    if (mounted) {
      setState(() {
        availabilityLoading = true;
        availabilityError = null;
      });
    }
    try {
      final loaded = await context
          .read<LiveRentHubController>()
          .getRenterListingAvailability(widget.listing.id);
      if (mounted) setState(() => availability = loaded);
    } catch (exception) {
      if (mounted) setState(() => availabilityError = friendlyError(exception));
    } finally {
      if (mounted) setState(() => availabilityLoading = false);
    }
    if (mounted &&
        widget.chooseDatesInitially &&
        !initialDatePickerOpened &&
        availability != null &&
        availability!.isDayAvailable(_firstAvailableOnOrAfter(start))) {
      initialDatePickerOpened = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _pick(true);
      });
    }
  }

  bool get selectedDatesAvailable =>
      availability?.isRangeAvailable(
        start,
        widget.listing.isService ? start : end,
      ) ??
      false;

  DateTime _firstAvailableOnOrAfter(DateTime preferred) {
    final first = DateTime(preferred.year, preferred.month, preferred.day);
    final model = availability;
    if (model == null) return first;
    for (var offset = 0; offset <= 730; offset += 1) {
      final candidate = first.add(Duration(days: offset));
      if (model.isDayAvailable(candidate)) return candidate;
    }
    return first;
  }

  String _dateLabel(DateTime date) {
    final local = date.toLocal();
    return '${local.day}/${local.month}/${local.year}';
  }

  @override
  void dispose() {
    venue.dispose();
    delivery.dispose();
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
    final accepted = await InputValidation.showFormDialog<bool>(
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
              TextFormField(
                controller: details,
                maxLines: 3,
                maxLength: 1000,
                maxLengthEnforcement: InputValidation.lengthEnforcement,
                decoration: (InputDecoration(
                  labelText: reason == 'other'
                      ? 'Details (required)'
                      : 'Details (optional)',
                )).copyWith(counterText: '', errorMaxLines: 3),
                validator: InputRule('Report details',
                        optional: reason != 'other', maxLength: 1000)
                    .validate,
                inputFormatters: InputValidation.formatters(
                    InputRule('Report details',
                        optional: reason != 'other', maxLength: 1000),
                    details),
                autovalidateMode: AutovalidateMode.onUserInteraction,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => InputValidation.popIfValid(
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
            .showSnackBar(SnackBar(content: Text(friendlyError(exception))));
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
            .showSnackBar(SnackBar(content: Text(friendlyError(exception))));
      }
    }
  }

  Future<void> _pick(bool startDate) async {
    final current = startDate ? start : end;
    final today = DateTime.now();
    final firstDate = DateTime(today.year, today.month, today.day);
    final initial = _firstAvailableOnOrAfter(
      current.isBefore(firstDate) ? firstDate : current,
    );
    final selected = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: firstDate,
      lastDate: firstDate.add(const Duration(days: 730)),
      selectableDayPredicate: (day) =>
          availability?.isDayAvailable(day) ?? false,
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
    if (!InputValidation.validate(context)) return;
    if (submitting || checkingIdentity || end.isBefore(start)) return;
    setState(() => checkingIdentity = true);
    final approved = await ensureMarketplaceIdentity(context,
        action: 'submit a booking request');
    if (!mounted) return;
    setState(() => checkingIdentity = false);
    if (!approved) return;
    if (!selectedDatesAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Choose dates that do not overlap unavailable dates.'),
        ),
      );
      return;
    }
    if (!agreementAccepted || reviewedAgreementVersion == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Review and accept the agreement first.')),
      );
      return;
    }
    if (widget.listing.isService &&
        ['flexible', 'renter_location'].contains(widget.listing.venueMode) &&
        (venue.text.trim().length < 2 || serviceLocation == null)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Choose and confirm a service venue pin.')),
      );
      return;
    }
    try {
      final latest = await context
          .read<LiveRentHubController>()
          .getRenterListingAvailability(widget.listing.id);
      if (!mounted) return;
      setState(() => availability = latest);
      if (!latest.isRangeAvailable(
        start,
        widget.listing.isService ? start : end,
      )) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Those dates just became unavailable. Please choose another range.',
            ),
          ),
        );
        return;
      }
    } catch (exception) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyError(exception))),
      );
      return;
    }
    final accepted = await confirmAction(
      context,
      title: 'Continue to checkout?',
      message:
          'Your pending request will be saved. Review the final charges and complete a demo payment on the next page. The Owner must still approve your booking.',
      action: 'Continue',
    );
    if (!accepted || !mounted) return;
    if (!widget.listing.isService &&
        fulfilmentMethod == 'owner_delivery' &&
        deliveryLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Choose and confirm a delivery address pin.')));
      return;
    }
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
      final booking = await context.read<LiveRentHubController>().createBooking(
            listing: widget.listing,
            start: bookingStart,
            end: end,
            agreementVersion: reviewedAgreementVersion!,
            fulfilmentMethod: fulfilmentMethod,
            serviceVenue: widget.listing.venueMode == 'online'
                ? 'Online'
                : venue.text.trim(),
            serviceLocation:
                serviceLocation?.copyWith(label: venue.text.trim()).toJson(),
            deliveryLocation: fulfilmentMethod == 'owner_delivery'
                ? deliveryLocation
                    ?.copyWith(label: delivery.text.trim())
                    .toJson()
                : null,
            damageWaiverSelected: waiver,
            renterNote: note.text,
            agreementAccepted: agreementAccepted,
            idempotencyKey: checkoutIdempotencyKey,
          );
      if (!mounted) return;
      final days = end.difference(start).inDays + 1;
      final estimate = widget.listing.isService
          ? widget.listing.displayPrice * 1.05
          : widget.listing.displayPrice * days +
              widget.listing.securityDeposit +
              (fulfilmentMethod == 'owner_delivery'
                  ? widget.listing.deliveryFee
                  : 0) +
              (waiver ? widget.listing.damageWaiverFee : 0);
      await showLiveCheckout(context, booking.id,
          estimatedTotal: estimate, initialMethod: paymentMethod);
      if (!mounted) return;
      Navigator.pop(context);
      widget.onSubmitted();
    } catch (exception) {
      if (mounted) {
        if (exception is ApiException &&
            (exception.code == 'KYC_REQUIRED' ||
                exception.code == 'MYKAD_REQUIRED' ||
                exception.code?.startsWith('DRIVING_') == true)) {
          final details = exception.details as Map? ?? const {};
          final driving = details['nextAction'] == 'driving_eligibility';
          final proceed = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              icon: const Icon(Icons.verified_user_outlined),
              title: const Text('Verification required'),
              content: Text(exception.message),
              actions: [
                FilledButton(
                  onPressed: () => InputValidation.popIfValid(context, true),
                  child: Text(
                      driving ? 'Review driving eligibility' : 'Verify MyKad'),
                ),
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Not now')),
              ],
            ),
          );
          if (proceed == true && mounted) {
            await Navigator.push<void>(
                context,
                MaterialPageRoute(
                    builder: (_) => LiveVerificationPage(driving: driving)));
          }
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(friendlyError(exception))),
          );
        }
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
            (fulfilmentMethod == 'owner_delivery' ? listing.deliveryFee : 0) +
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
              color: controller.isSaved(listing.id) ? AppColors.error : null,
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
          label: agreementAccepted
              ? 'Continue to checkout'
              : 'Accept Agreement to Continue',
          loading: submitting || checkingIdentity,
          onPressed: submitting ||
                  checkingIdentity ||
                  !agreementAccepted ||
                  availabilityLoading ||
                  !selectedDatesAvailable
              ? null
              : _submit,
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
                    if (listing.locationPrecision == 'approximate') ...[
                      const Text(
                          'Approximate area · exact pickup point shared after approval'),
                      if (listing.latitude != null && listing.longitude != null)
                        TextButton.icon(
                          icon: const Icon(Icons.map_outlined),
                          label: const Text('View approximate area'),
                          onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => LiveLocationView(
                                        api: ListingLocationApi(context
                                            .read<LiveRentHubController>()
                                            .api),
                                        approximate: true,
                                        location:
                                            ListingLocationSelection.fromJson({
                                          'label': listing.location,
                                          'coordinates': {
                                            'latitude': listing.latitude,
                                            'longitude': listing.longitude
                                          }
                                        }),
                                      ))),
                        ),
                    ],
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
            LiveComplementsSection(
                listingId: listing.id,
                onOpen: (item) => Navigator.push<void>(
                    context,
                    MaterialPageRoute(
                        builder: (_) => LiveBookingPage(
                            listing: item, onSubmitted: widget.onSubmitted)))),
            const SizedBox(height: 12),
            if (availabilityLoading)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text('Checking current availability...'),
                      ),
                    ],
                  ),
                ),
              )
            else if (availabilityError != null)
              Card(
                child: ListTile(
                  leading:
                      const Icon(Icons.error_outline, color: AppColors.error),
                  title: const Text('Availability could not be loaded'),
                  subtitle: Text(availabilityError!),
                  trailing: TextButton(
                    onPressed: _loadAvailability,
                    child: const Text('Retry'),
                  ),
                ),
              )
            else if (availability != null)
              Builder(
                builder: (context) {
                  final today = malaysiaCalendarToday();
                  final current = availability!.rangeContaining(today);
                  final upcoming = availability!.unavailableRanges
                      .where((range) => !range.displayEndDay.isBefore(today))
                      .toList()
                    ..sort((a, b) => a.startDay.compareTo(b.startDay));
                  return Card(
                    color: current == null
                        ? AppColors.success.withValues(alpha: 0.06)
                        : AppColors.warning.withValues(alpha: 0.08),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                current == null
                                    ? Icons.event_available_outlined
                                    : Icons.event_busy_outlined,
                                color: current == null
                                    ? AppColors.success
                                    : AppColors.warning,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  current == null
                                      ? 'Available now'
                                      : current.source == 'booking'
                                          ? 'Currently rented until ${_dateLabel(current.displayEndDay)}'
                                          : 'Currently unavailable until ${_dateLabel(current.displayEndDay)}',
                                  style:
                                      Theme.of(context).textTheme.titleMedium,
                                ),
                              ),
                            ],
                          ),
                          if (current != null &&
                              availability!.nextAvailableDate != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              'Next available: ${_dateLabel(availability!.nextAvailableDate!)}',
                            ),
                          ],
                          if (upcoming.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            const Text(
                              'Unavailable dates',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                            for (final range in upcoming.take(3))
                              Text(
                                '${_dateLabel(range.startDay.isBefore(today) ? today : range.startDay)} - ${_dateLabel(range.displayEndDay)}'
                                '${range.source == 'booking' ? ' · Reserved' : ' · Owner blocked'}',
                                style: const TextStyle(
                                  color: AppColors.secondaryText,
                                ),
                              ),
                          ],
                        ],
                      ),
                    ),
                  );
                },
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
                    if (!availabilityLoading && !selectedDatesAvailable)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 12),
                        child: Text(
                          'The selected range overlaps unavailable dates.',
                          style: TextStyle(
                            color: AppColors.error,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    if (listing.isService)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Service time'),
                        subtitle: Text(serviceTime.format(context)),
                        trailing: const Icon(Icons.schedule_outlined),
                        onTap: _pickServiceTime,
                      ),
                    if (listing.isService &&
                        ['flexible', 'renter_location']
                            .contains(listing.venueMode))
                      LiveLocationField(
                          mapBuilder: widget.locationMapBuilder,
                          api: ListingLocationApi(
                              context.read<LiveRentHubController>().api),
                          controller: venue,
                          value: serviceLocation,
                          label: 'Service venue',
                          enabled: !submitting,
                          onChanged: (value) =>
                              setState(() => serviceLocation = value))
                    else if (listing.isService)
                      Text(listing.venueMode == 'online'
                          ? 'This service is online. No physical venue is needed.'
                          : 'The owner’s exact venue is shared after approval.')
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
                    if (!listing.isService &&
                        fulfilmentMethod == 'owner_delivery') ...[
                      Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                              listing.deliveryFee == 0
                                  ? 'Delivery: Free'
                                  : 'Delivery fee: ${formatMoney(listing.deliveryFee)}',
                              style: Theme.of(context).textTheme.titleSmall)),
                      if (context
                              .read<LiveRentHubController>()
                              .profile
                              ?.addresses
                              .isNotEmpty ==
                          true)
                        DropdownButtonFormField<UserAddress>(
                            isExpanded: true,
                            decoration: const InputDecoration(
                                labelText: 'Use a saved address'),
                            items: context
                                .read<LiveRentHubController>()
                                .profile!
                                .addresses
                                .map((address) => DropdownMenuItem(
                                    value: address,
                                    child: Text(address.label,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis)))
                                .toList(),
                            onChanged: (address) {
                              if (address == null) return;
                              setState(() {
                                delivery.text = address.line1;
                                deliveryLocation = address.mapLocation;
                              });
                            }),
                      LiveLocationField(
                          mapBuilder: widget.locationMapBuilder,
                          api: ListingLocationApi(
                              context.read<LiveRentHubController>().api),
                          controller: delivery,
                          value: deliveryLocation,
                          label: 'Delivery address',
                          enabled: !submitting,
                          onChanged: (value) =>
                              setState(() => deliveryLocation = value)),
                    ],
                    if (!listing.isService && listing.damageWaiverAvailable)
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: waiver,
                        title: const Text('Damage waiver'),
                        subtitle: Text(formatMoney(listing.damageWaiverFee)),
                        onChanged: (value) => setState(() => waiver = value),
                      ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: note,
                      maxLength: 1000,
                      maxLengthEnforcement: InputValidation.lengthEnforcement,
                      maxLines: 3,
                      decoration: (const InputDecoration(
                        labelText: 'Note to Owner (optional)',
                      )).copyWith(counterText: '', errorMaxLines: 3),
                      validator: InputRules.noteToOwnerOptional.validate,
                      inputFormatters: InputValidation.formatters(
                          InputRules.noteToOwnerOptional, note),
                      autovalidateMode: AutovalidateMode.onUserInteraction,
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
                    Text(
                      'Estimated total: ${formatMoney(estimate)}',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const Text(
                      'Review the final charges on the next page. No real money will be taken.',
                      style: TextStyle(color: AppColors.secondaryText),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.gavel_outlined),
                    title: const Text('Booking agreement'),
                    subtitle: const Text(
                      'Review the terms before sending this request.',
                    ),
                    trailing: TextButton(
                      onPressed: () async {
                        final terms = await showAgreementTerms(context,
                            listingType:
                                listing.isService ? 'service' : 'physical',
                            listingTitle: listing.title,
                            dateRange: formatDateRange(start, end),
                            total: 'Estimated total: ${formatMoney(estimate)}');
                        if (mounted && terms != null) {
                          setState(() {
                            reviewedAgreementVersion = terms.version;
                            agreementAccepted = false;
                          });
                        }
                      },
                      child: const Text('Review'),
                    ),
                  ),
                  const Divider(height: 1),
                  CheckboxListTile(
                    value: agreementAccepted,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: const Text(
                      'I have reviewed and accept the RentHub booking agreement.',
                    ),
                    subtitle: Text(reviewedAgreementVersion == null
                        ? 'Review the agreement first to enable acceptance.'
                        : 'The reviewed terms will be saved with your request.'),
                    onChanged: submitting || reviewedAgreementVersion == null
                        ? null
                        : (value) => setState(
                              () => agreementAccepted = value ?? false,
                            ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class LiveRenterBookingsPage extends StatefulWidget {
  const LiveRenterBookingsPage(
      {super.key, this.focusBookingId, this.focusRentalId, this.payment});
  final String? focusBookingId, focusRentalId;
  final Transaction? payment;

  @override
  State<LiveRenterBookingsPage> createState() => _LiveRenterBookingsPageState();
}

class _LiveRenterBookingsPageState extends State<LiveRenterBookingsPage> {
  Future<void> _refresh() async {
    try {
      if (widget.focusBookingId != null) {
        await context.read<LiveRentHubController>().refreshFocusedBooking(
            widget.focusBookingId!, widget.focusRentalId);
        return;
      }
      await context.read<LiveRentHubController>().loadRenter();
    } catch (_) {}
  }

  Future<void> _cancel(Booking booking) async {
    final reason = TextEditingController();
    final accepted = await InputValidation.showFormDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel booking?'),
        content: TextFormField(
          controller: reason,
          decoration: (const InputDecoration(labelText: 'Cancellation reason'))
              .copyWith(counterText: '', errorMaxLines: 3),
          validator: InputRules.cancellationReason.validate,
          inputFormatters:
              InputValidation.formatters(InputRules.cancellationReason, reason),
          autovalidateMode: AutovalidateMode.onUserInteraction,
          maxLength: InputRules.cancellationReason.maxLength,
          maxLengthEnforcement: InputValidation.lengthEnforcement,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep Booking'),
          ),
          FilledButton(
            onPressed: () => InputValidation.popIfValid(context, true),
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
              .showSnackBar(SnackBar(content: Text(friendlyError(exception))));
        }
      }
    }
    reason.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<LiveRentHubController>();
    final visibleBookings = controller.bookings
        .where((booking) =>
            widget.focusBookingId == null ||
            booking.id == widget.focusBookingId)
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(
            widget.focusBookingId == null ? 'My Bookings' : 'Booking details'),
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
        child: visibleBookings.isEmpty
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
                itemCount: visibleBookings.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final booking = visibleBookings[index];
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
                          if (widget.payment != null)
                            LivePaymentSummary(payment: widget.payment!),
                          BookingLocationsButton(bookingId: booking.id),
                          Wrap(spacing: 8, children: [
                            TextButton.icon(
                                onPressed: () =>
                                    showBookingAgreement(context, booking.id),
                                icon: const Icon(Icons.description_outlined),
                                label: const Text('View agreement')),
                            if (booking.status == 'pending' &&
                                booking.paymentStatus == 'unpaid' &&
                                (booking.expiresAt == null ||
                                    booking.expiresAt!.isAfter(DateTime.now())))
                              FilledButton.tonal(
                                  onPressed: () =>
                                      showLiveCheckout(context, booking.id),
                                  child: const Text('Continue payment')),
                          ]),
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
            .showSnackBar(SnackBar(content: Text(friendlyError(exception))));
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
    if (rental.listingType == 'physical' &&
        ['active', 'overdue'].contains(rental.status)) {
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
                          'requestedEndDate': calendarDateApiValue(requested),
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
                  final evidence = await pickAndPreviewUpload(context,
                      purpose: 'return_evidence');
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
                      SnackBar(content: Text(friendlyError(exception))),
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

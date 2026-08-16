import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/renthub_categories.dart';
import '../../core/theme/app_theme.dart';
import '../../modules/booking/controllers/booking_controller.dart';
import '../../shared/mock_data/mock_data.dart';
import '../../shared/models/domain_models.dart';
import '../../shared/widgets/account_components.dart';
import '../../shared/widgets/renthub_components.dart';
import '../account/account_pages.dart';
import 'booking/booking_flow.dart';
import 'comparison/controllers/compare_selection_controller.dart';
import 'comparison/pages/compare_items_page.dart';
import 'discovery/controllers/renter_prototype_state.dart';
import 'discovery/pages/wishlist_page.dart';
import 'rentals/pages/active_rental_details_page.dart';
import 'services/pages/service_booking_history_details_page.dart';
import 'services/pages/service_details_page.dart';
import 'services/pages/service_search_results_page.dart';

typedef OpenExplore = void Function(String query);

class RenterShell extends StatefulWidget {
  const RenterShell({
    super.key,
    required this.onSwitchRole,
    required this.canSwitch,
    this.initialIndex = 0,
  });

  final VoidCallback onSwitchRole;
  final bool canSwitch;
  final int initialIndex;

  @override
  State<RenterShell> createState() => _RenterShellState();
}

class _RenterShellState extends State<RenterShell> {
  final exploreKey = GlobalKey<ExplorePageState>();
  final bookingsKey = GlobalKey<BookingsPageState>();
  late int index;
  BookingDraft? latestDraft;

  @override
  void initState() {
    super.initState();
    index = widget.initialIndex.clamp(0, 4);
  }

  void _openExplore(String query) {
    if (query == RentHubCategories.services) {
      Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => ServiceResultsPage(
            onOpenBookings: () => _returnToTab(2),
            onReturnHome: () => _returnToTab(0),
          ),
        ),
      );
      return;
    }
    exploreKey.currentState?.applyQuery(query);
    setState(() => index = 1);
  }

  void _rememberDraft(BookingDraft draft) => latestDraft = draft;

  void _returnToTab(int destination) {
    if (destination == 2) bookingsKey.currentState?.showPending();
    setState(() => index = destination);
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      RenterHome(
        onExplore: _openExplore,
        onOpenBookings: () => _returnToTab(2),
        onReturnHome: () => _returnToTab(0),
        onDraftCreated: _rememberDraft,
      ),
      ExplorePage(
        key: exploreKey,
        onOpenBookings: () => _returnToTab(2),
        onReturnHome: () => _returnToTab(0),
        onDraftCreated: _rememberDraft,
      ),
      BookingsPage(
        key: bookingsKey,
        latestDraft: () => latestDraft,
      ),
      const MessagesPage(),
      ProfilePage(
        role: 'Renter',
        canSwitch: widget.canSwitch,
        onSwitch: widget.onSwitchRole,
      ),
    ];
    return Scaffold(
      body: IndexedStack(index: index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (value) => setState(() => index = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(icon: Icon(Icons.search), label: 'Explore'),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month),
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

class RenterHome extends StatefulWidget {
  const RenterHome({
    super.key,
    required this.onExplore,
    required this.onOpenBookings,
    required this.onReturnHome,
    required this.onDraftCreated,
  });

  final OpenExplore onExplore;
  final VoidCallback onOpenBookings;
  final VoidCallback onReturnHome;
  final ValueChanged<BookingDraft> onDraftCreated;

  @override
  State<RenterHome> createState() => _RenterHomeState();
}

class _RenterHomeState extends State<RenterHome> {
  bool loading = true;

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(milliseconds: 180), () {
      if (mounted) setState(() => loading = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(
        body: SafeArea(
          child: RentHubFeedbackState(
            kind: FeedbackKind.loading,
            title: 'Finding rentals nearby',
            message: 'Loading local marketplace recommendations…',
          ),
        ),
      );
    }

    final physical =
        MockData.listings.where((item) => !item.isService).toList();
    final services = MockData.listings.where((item) => item.isService).toList();
    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          key: const PageStorageKey('renter-home-scroll'),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.location_on_outlined,
                          color: AppColors.primaryDark,
                          size: 20,
                        ),
                        const SizedBox(width: 4),
                        const Expanded(
                          child: Text('Kuala Lumpur',
                              style: TextStyle(fontSize: 12)),
                        ),
                        const RentHubLogo(),
                        const Spacer(),
                        IconButton(
                          tooltip: 'Wishlist',
                          onPressed: () => Navigator.push<void>(
                            context,
                            MaterialPageRoute(
                              builder: (_) => WishlistPage(
                                onOpenListing: (listing) {
                                  if (listing.isService) {
                                    Navigator.push<void>(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => ServiceDetailsPage(
                                          service: listing,
                                          onOpenBookings: widget.onOpenBookings,
                                          onReturnHome: widget.onReturnHome,
                                        ),
                                      ),
                                    );
                                  } else {
                                    _openListing(
                                      context,
                                      listing,
                                      onOpenBookings: widget.onOpenBookings,
                                      onReturnHome: widget.onReturnHome,
                                      onDraftCreated: widget.onDraftCreated,
                                    );
                                  }
                                },
                              ),
                            ),
                          ),
                          icon: const Icon(Icons.favorite_border),
                        ),
                        IconButton(
                          tooltip: 'Notifications',
                          onPressed: () => Navigator.push<void>(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const NotificationsPage(),
                            ),
                          ),
                          icon: const Badge(
                            child: Icon(Icons.notifications_outlined),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'What do you want to rent or book today?',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      key: const Key('home-search-field'),
                      readOnly: true,
                      onTap: () => widget.onExplore(''),
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: 'Search items, vehicles, services…',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: _CategoryStrip(onExplore: widget.onExplore),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
              sliver: SliverToBoxAdapter(
                child: _SectionHeader(
                  title: 'Recommended for You',
                  onSeeAll: () => widget.onExplore(''),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 248,
                child: ListView.separated(
                  key: const Key('home-recommendations'),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  scrollDirection: Axis.horizontal,
                  itemCount: physical.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (context, itemIndex) => SizedBox(
                    width: 188,
                    child: _HomeListingCard(
                      listing: physical[itemIndex],
                      onTap: () => _openListing(
                        context,
                        physical[itemIndex],
                        onOpenBookings: widget.onOpenBookings,
                        onReturnHome: widget.onReturnHome,
                        onDraftCreated: widget.onDraftCreated,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SliverPadding(
              padding: EdgeInsets.fromLTRB(16, 18, 16, 10),
              sliver: SliverToBoxAdapter(
                child: _SectionHeader(title: 'Services for You'),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              sliver: SliverList.separated(
                itemCount: services.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, itemIndex) => _ServiceTeaser(
                  listing: services[itemIndex],
                  onTap: () => Navigator.push<void>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ServiceDetailsPage(
                        service: services[itemIndex],
                        onOpenBookings: widget.onOpenBookings,
                        onReturnHome: widget.onReturnHome,
                      ),
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

class _CategoryStrip extends StatelessWidget {
  const _CategoryStrip({required this.onExplore});

  final OpenExplore onExplore;

  @override
  Widget build(BuildContext context) {
    const categories = [
      (RentHubCategories.clothing, Icons.checkroom_outlined),
      (RentHubCategories.vehicles, Icons.directions_car_outlined),
      (RentHubCategories.services, Icons.design_services_outlined),
      (RentHubCategories.devices, Icons.devices_outlined),
      (RentHubCategories.books, Icons.menu_book_outlined),
      (RentHubCategories.equipment, Icons.handyman_outlined),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 1.25,
        ),
        itemCount: categories.length,
        itemBuilder: (context, itemIndex) => Material(
          color: AppColors.background,
          shape: RoundedRectangleBorder(
            side: const BorderSide(color: AppColors.border),
            borderRadius: BorderRadius.circular(12),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => onExplore(categories[itemIndex].$1),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    categories[itemIndex].$2,
                    color: AppColors.primaryDark,
                    size: 28,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    categories[itemIndex].$1,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 11),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.onSeeAll});

  final String title;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(
            child: Text(title, style: Theme.of(context).textTheme.titleLarge),
          ),
          if (onSeeAll != null)
            TextButton(onPressed: onSeeAll, child: const Text('See All')),
        ],
      );
}

class _HomeListingCard extends StatelessWidget {
  const _HomeListingCard({required this.listing, required this.onTap});

  final Listing listing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: Key('home-listing-${listing.id}'),
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                        child: _ListingPlaceholder(listing: listing)),
                    Positioned(
                      left: 8,
                      top: 8,
                      child: _TinyBadge(
                        icon: listing.verified
                            ? Icons.verified_outlined
                            : Icons.star_outline,
                        label:
                            listing.verified ? 'VERIFIED' : '${listing.rating}',
                        color: listing.verified
                            ? AppColors.success
                            : AppColors.warning,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            listing.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        ValueListenableBuilder<Set<String>>(
                          valueListenable: RenterPrototypeState.wishlist,
                          builder: (context, saved, _) => IconButton(
                            tooltip: saved.contains(listing.id)
                                ? 'Remove from wishlist'
                                : 'Save to wishlist',
                            visualDensity: VisualDensity.compact,
                            onPressed: () {
                              final values = {...saved};
                              if (!values.add(listing.id)) {
                                values.remove(listing.id);
                              }
                              RenterPrototypeState.wishlist.value = values;
                            },
                            icon: Icon(
                              saved.contains(listing.id)
                                  ? Icons.favorite
                                  : Icons.favorite_border,
                              size: 19,
                              color: saved.contains(listing.id)
                                  ? AppColors.error
                                  : null,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      listing.location,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.secondaryText,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${formatMoney(listing.dailyPrice)} /day',
                      style: const TextStyle(
                        color: AppColors.primaryDark,
                        fontWeight: FontWeight.w800,
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

class _ServiceTeaser extends StatelessWidget {
  const _ServiceTeaser({required this.listing, required this.onTap});

  final Listing listing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                SizedBox(
                  width: 92,
                  height: 82,
                  child: _ListingPlaceholder(listing: listing),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        listing.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 3),
                      const Text(
                        'Professional service package from a verified Owner.',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.secondaryText,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        'From ${formatMoney(listing.dailyPrice)}',
                        style: const TextStyle(
                          color: AppColors.primaryDark,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                FilledButton(onPressed: onTap, child: const Text('View')),
              ],
            ),
          ),
        ),
      );
}

class ExplorePage extends StatefulWidget {
  const ExplorePage({
    super.key,
    this.initialQuery,
    required this.onOpenBookings,
    required this.onReturnHome,
    required this.onDraftCreated,
  });

  final String? initialQuery;
  final VoidCallback onOpenBookings;
  final VoidCallback onReturnHome;
  final ValueChanged<BookingDraft> onDraftCreated;

  @override
  State<ExplorePage> createState() => ExplorePageState();
}

class ExplorePageState extends State<ExplorePage> {
  late final TextEditingController search;
  final ScrollController scrollController = ScrollController();
  final comparison = ComparisonSelectionController();
  bool verifiedOnly = false;
  bool availableOnly = true;
  bool selectingForComparison = false;
  String category = 'All';
  String location = 'All locations';
  double maxPrice = 200;

  String get currentQuery => search.text;
  double get currentScrollOffset =>
      scrollController.hasClients ? scrollController.offset : 0;

  @override
  void initState() {
    super.initState();
    search = TextEditingController(text: widget.initialQuery ?? '');
  }

  @override
  void dispose() {
    search.dispose();
    scrollController.dispose();
    comparison.dispose();
    super.dispose();
  }

  void _toggleComparisonMode() {
    setState(() {
      selectingForComparison = !selectingForComparison;
      if (!selectingForComparison) comparison.clear();
    });
  }

  void _toggleComparisonItem(Listing listing) {
    final message = comparison.toggle(listing);
    if (message != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } else {
      setState(() {});
    }
  }

  Future<void> _openComparison() => Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => CompareItemsPage(
            selectedListingIds: comparison.selectedIds.toList(),
            onOpenListing: (listing) => _openListing(
              context,
              listing,
              onOpenBookings: widget.onOpenBookings,
              onReturnHome: widget.onReturnHome,
              onDraftCreated: widget.onDraftCreated,
            ),
          ),
        ),
      );

  void applyQuery(String query) {
    search.text = query;
    search.selection = TextSelection.collapsed(offset: query.length);
    if (scrollController.hasClients) scrollController.jumpTo(0);
    setState(() {});
  }

  List<Listing> get filteredItems => MockData.listings.where((item) {
        if (item.isService) return false;
        final query = search.text.trim().toLowerCase();
        final matchesQuery = query.isEmpty ||
            '${item.title} ${item.category} ${item.location}'
                .toLowerCase()
                .contains(query);
        final matchesCategory = category == 'All' || item.category == category;
        final matchesLocation = location == 'All locations' ||
            item.location.toLowerCase().contains(location.toLowerCase());
        final matchesAvailability = !availableOnly || item.id != 'l-tent';
        return matchesQuery &&
            matchesCategory &&
            matchesLocation &&
            matchesAvailability &&
            item.dailyPrice <= maxPrice &&
            (!verifiedOnly || item.verified);
      }).toList();

  void _reset() {
    setState(() {
      search.clear();
      verifiedOnly = false;
      availableOnly = true;
      category = 'All';
      location = 'All locations';
      maxPrice = 200;
    });
  }

  Future<void> _openFilters() async {
    var draftVerified = verifiedOnly;
    var draftAvailable = availableOnly;
    var draftCategory = category;
    var draftLocation = location;
    var draftPrice = maxPrice;
    final apply = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              20,
              0,
              20,
              20 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Filters', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: draftCategory,
                  decoration: const InputDecoration(labelText: 'Category'),
                  items: const [
                    'All',
                    RentHubCategories.clothing,
                    RentHubCategories.vehicles,
                    RentHubCategories.devices,
                    RentHubCategories.books,
                    RentHubCategories.equipment,
                  ]
                      .map((value) => DropdownMenuItem(
                            value: value,
                            child: Text(value),
                          ))
                      .toList(),
                  onChanged: (value) =>
                      setSheetState(() => draftCategory = value ?? 'All'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: draftLocation,
                  decoration: const InputDecoration(labelText: 'Location'),
                  items: const [
                    'All locations',
                    'Petaling Jaya',
                    'Shah Alam',
                    'Subang Jaya',
                  ]
                      .map((value) => DropdownMenuItem(
                            value: value,
                            child: Text(value),
                          ))
                      .toList(),
                  onChanged: (value) => setSheetState(
                    () => draftLocation = value ?? 'All locations',
                  ),
                ),
                const SizedBox(height: 16),
                Text('Maximum daily price: ${formatMoney(draftPrice)}'),
                Slider(
                  value: draftPrice,
                  min: 40,
                  max: 200,
                  divisions: 16,
                  label: formatMoney(draftPrice),
                  onChanged: (value) => setSheetState(() => draftPrice = value),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Available dates only'),
                  value: draftAvailable,
                  onChanged: (value) =>
                      setSheetState(() => draftAvailable = value),
                ),
                SwitchListTile(
                  key: const Key('verified-owner-filter'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Verified Owners only'),
                  value: draftVerified,
                  onChanged: (value) =>
                      setSheetState(() => draftVerified = value),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => Navigator.pop(sheetContext, true),
                  child: const Text('Show results'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (apply == true) {
      setState(() {
        verifiedOnly = draftVerified;
        availableOnly = draftAvailable;
        category = draftCategory;
        location = draftLocation;
        maxPrice = draftPrice;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = filteredItems;
    return Scaffold(
      appBar: AppBar(
        title: const RentHubLogo(),
        actions: [
          TextButton(onPressed: _reset, child: const Text('RESET')),
        ],
      ),
      bottomNavigationBar: selectingForComparison
          ? SafeArea(
              minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: RentHubActionButton(
                key: const Key('explore-compare-selected'),
                label: 'Compare Selected (${comparison.count})',
                onPressed: comparison.canCompare ? _openComparison : null,
              ),
            )
          : null,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: TextField(
                key: const Key('search-results-field'),
                controller: search,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: 'Search physical items',
                  suffixIcon: IconButton(
                    tooltip: 'Clear search',
                    onPressed: search.text.isEmpty
                        ? null
                        : () {
                            search.clear();
                            setState(() {});
                          },
                    icon: const Icon(Icons.close),
                  ),
                ),
              ),
            ),
            SizedBox(
              height: 48,
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                scrollDirection: Axis.horizontal,
                children: [
                  ActionChip(
                    avatar: const Icon(Icons.tune, size: 18),
                    label: const Text('Filters'),
                    onPressed: _openFilters,
                  ),
                  const SizedBox(width: 8),
                  FilterChip(
                    key: const Key('verified-filter-chip'),
                    label: const Text('Verified Owners'),
                    selected: verifiedOnly,
                    onSelected: (value) => setState(() => verifiedOnly = value),
                  ),
                  const SizedBox(width: 8),
                  FilterChip(
                    label: Text('Up to ${formatMoney(maxPrice)}'),
                    selected: maxPrice < 200,
                    onSelected: (_) => _openFilters(),
                  ),
                  const SizedBox(width: 8),
                  FilterChip(
                    label: Text(location),
                    selected: location != 'All locations',
                    onSelected: (_) => _openFilters(),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      selectingForComparison
                          ? '${comparison.count} of 3 selected'
                          : '${items.length} physical items found',
                      key: const Key('explore-results-count'),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  TextButton(
                    key: const Key('explore-compare-mode'),
                    onPressed: items.isEmpty && !selectingForComparison
                        ? null
                        : _toggleComparisonMode,
                    child: Text(
                      selectingForComparison ? 'Cancel' : 'Compare',
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: items.isEmpty
                  ? RentHubFeedbackState(
                      kind: FeedbackKind.empty,
                      title: 'No items match these filters',
                      message:
                          'Try a wider price range, another location, or clear the filters.',
                      actionLabel: 'Clear filters',
                      onAction: _reset,
                    )
                  : ListView.separated(
                      key: const PageStorageKey('search-results-scroll'),
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, itemIndex) => _SearchResultCard(
                        listing: items[itemIndex],
                        selectionMode: selectingForComparison,
                        selected: comparison.selectedIds
                            .contains(items[itemIndex].id),
                        onSelected: () =>
                            _toggleComparisonItem(items[itemIndex]),
                        onTap: selectingForComparison
                            ? () => _toggleComparisonItem(items[itemIndex])
                            : () => _openListing(
                                  context,
                                  items[itemIndex],
                                  onOpenBookings: widget.onOpenBookings,
                                  onReturnHome: widget.onReturnHome,
                                  onDraftCreated: widget.onDraftCreated,
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

class _SearchResultCard extends StatelessWidget {
  const _SearchResultCard({
    required this.listing,
    required this.onTap,
    required this.selectionMode,
    required this.selected,
    required this.onSelected,
  });

  final Listing listing;
  final VoidCallback onTap;
  final bool selectionMode;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) => Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: Key('search-result-${listing.id}'),
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 16 / 7,
                child: Stack(
                  children: [
                    Positioned.fill(
                        child: _ListingPlaceholder(listing: listing)),
                    if (selectionMode)
                      Positioned(
                        left: 10,
                        top: 10,
                        child: Material(
                          color: Colors.white,
                          shape: const CircleBorder(),
                          child: Checkbox(
                            key: Key('explore-compare-${listing.id}'),
                            value: selected,
                            onChanged: (_) => onSelected(),
                          ),
                        ),
                      ),
                    Positioned(
                      right: 10,
                      top: 10,
                      child: _TinyBadge(
                        icon: Icons.star,
                        label: '${listing.rating}',
                        color: AppColors.warning,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            listing.title,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        if (!selectionMode)
                          ValueListenableBuilder<Set<String>>(
                            valueListenable: RenterPrototypeState.wishlist,
                            builder: (context, saved, _) => IconButton(
                              tooltip: saved.contains(listing.id)
                                  ? 'Remove from wishlist'
                                  : 'Save to wishlist',
                              onPressed: () {
                                final values = {...saved};
                                if (!values.add(listing.id)) {
                                  values.remove(listing.id);
                                }
                                RenterPrototypeState.wishlist.value = values;
                              },
                              icon: Icon(
                                saved.contains(listing.id)
                                    ? Icons.favorite
                                    : Icons.favorite_border,
                                size: 20,
                                color: saved.contains(listing.id)
                                    ? AppColors.error
                                    : null,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${listing.location} · ${listing.condition}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.secondaryText,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 7),
                    if (listing.verified)
                      const Row(
                        children: [
                          Icon(
                            Icons.verified,
                            size: 16,
                            color: AppColors.success,
                          ),
                          SizedBox(width: 4),
                          Text(
                            'VERIFIED OWNER',
                            style: TextStyle(
                              color: AppColors.success,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    const SizedBox(height: 5),
                    Text(
                      '${formatMoney(listing.dailyPrice)} /day',
                      style: const TextStyle(
                        color: AppColors.primaryDark,
                        fontWeight: FontWeight.w800,
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

void _openListing(
  BuildContext context,
  Listing listing, {
  required VoidCallback onOpenBookings,
  required VoidCallback onReturnHome,
  required ValueChanged<BookingDraft> onDraftCreated,
}) {
  Navigator.push<void>(
    context,
    MaterialPageRoute(
      builder: (_) => ListingDetailsPage(
        listing: listing,
        onOpenBookings: onOpenBookings,
        onReturnHome: onReturnHome,
        onDraftCreated: onDraftCreated,
      ),
    ),
  );
}

class ListingDetailsPage extends StatelessWidget {
  const ListingDetailsPage({
    super.key,
    required this.listing,
    required this.onOpenBookings,
    required this.onReturnHome,
    required this.onDraftCreated,
  });

  final Listing listing;
  final VoidCallback onOpenBookings;
  final VoidCallback onReturnHome;
  final ValueChanged<BookingDraft> onDraftCreated;

  void _book(BuildContext context) {
    if (listing.isService) {
      Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => ServiceDetailsPage(
            service: listing,
            onOpenBookings: onOpenBookings,
            onReturnHome: onReturnHome,
          ),
        ),
      );
      return;
    }
    final draft = BookingDraft(listing: listing);
    onDraftCreated(draft);
    Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => BookingDetailsPage(
          draft: draft,
          onOpenBookings: onOpenBookings,
          onReturnHome: onReturnHome,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final policy = BookingPolicies.forListing(listing);
    return Scaffold(
      appBar: AppBar(
        title: const RentHubLogo(compact: true),
        centerTitle: true,
        actions: [
          ValueListenableBuilder<Set<String>>(
            valueListenable: RenterPrototypeState.wishlist,
            builder: (context, saved, _) => IconButton(
              tooltip: saved.contains(listing.id)
                  ? 'Remove from wishlist'
                  : 'Save to wishlist',
              onPressed: () {
                final values = {...saved};
                if (!values.add(listing.id)) values.remove(listing.id);
                RenterPrototypeState.wishlist.value = values;
              },
              icon: Icon(
                saved.contains(listing.id)
                    ? Icons.favorite
                    : Icons.favorite_border,
                color: saved.contains(listing.id) ? AppColors.error : null,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Share listing',
            onPressed: () => showMockSuccess(context, 'Share sheet opened'),
            icon: const Icon(Icons.share_outlined),
          ),
          PopupMenuButton<String>(
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'report', child: Text('Report listing')),
              PopupMenuItem(value: 'block', child: Text('Block Owner')),
            ],
            onSelected: (value) => confirmAction(
              context,
              title: value == 'block' ? 'Block Owner?' : 'Report listing?',
              message: 'This mock action can be reversed from Settings.',
              action: 'Continue',
              destructive: true,
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          color: AppColors.background,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${formatMoney(listing.dailyPrice)} /day',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const Text(
                      'Deposit shown before agreement',
                      style: TextStyle(
                        color: AppColors.secondaryText,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
                key: const Key('book-now-button'),
                onPressed: () => _book(context),
                icon: const Icon(Icons.arrow_forward),
                label: const Text('Book Now'),
              ),
            ],
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Stack(
            children: [
              AspectRatio(
                aspectRatio: 16 / 10,
                child: _ListingPlaceholder(listing: listing, large: true),
              ),
              const Positioned(
                left: 16,
                top: 12,
                child: _TinyBadge(
                  icon: Icons.workspace_premium_outlined,
                  label: 'TOP RATED',
                  color: AppColors.success,
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(listing.title,
                    style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 6),
                Text(
                  '★ ${listing.rating} (128 reviews)',
                  style: const TextStyle(color: AppColors.warning),
                ),
                const SizedBox(height: 4),
                Text(
                  listing.location,
                  style: const TextStyle(color: AppColors.secondaryText),
                ),
                const SizedBox(height: 16),
                Card(
                  child: ListTile(
                    leading: CircleAvatar(child: Text(listing.ownerName[0])),
                    title: Text(listing.ownerName),
                    subtitle:
                        const Text('Verified Owner · Gold tier · Trust 98'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => showMockSuccess(
                      context,
                      'Owner profile preview opened',
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Equipment Details',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 6),
                Text(
                  'Perfect-condition ${listing.title} for professional photo and video shoots. Cleaned, checked, and ready for collection.',
                  style: const TextStyle(color: AppColors.secondaryText),
                ),
                const SizedBox(height: 14),
                const _FeatureGrid(),
                const SizedBox(height: 16),
                Text(
                  'Included Accessories',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                const Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    Chip(label: Text('2 Batteries')),
                    Chip(label: Text('Memory Card')),
                    Chip(label: Text('Carry Case')),
                    Chip(label: Text('USB-C Cable')),
                  ],
                ),
                const SizedBox(height: 16),
                _DetailExpansion(
                  title: 'Availability & Calendar',
                  icon: Icons.calendar_month_outlined,
                  child: Text(
                    'Available for the next 12 days. The range ${formatDateRange(policy.unavailableDates.first.start, policy.unavailableDates.first.end)} is unavailable.',
                  ),
                ),
                const _DetailExpansion(
                  title: 'Rental Policy',
                  icon: Icons.description_outlined,
                  child: Text(
                    'Return the item in the same condition. Agreement acceptance is required before the demo authorization.',
                  ),
                ),
                _DetailExpansion(
                  title: 'Pickup & Return Details',
                  icon: Icons.location_on_outlined,
                  child: Text(
                    'Self pickup: ${policy.pickupLocation}. Owner delivery is also available.',
                  ),
                ),
                _DetailExpansion(
                  title: 'Deposit Information',
                  icon: Icons.account_balance_wallet_outlined,
                  child: Text(
                    '${formatMoney(policy.deposit)} refundable deposit. It is included only in the local demo authorization.',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FeatureGrid extends StatelessWidget {
  const _FeatureGrid();

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          const data = [
            ('Resolution', '12.1 MP'),
            ('Video', '4K 120p 10-bit'),
            ('Mount', 'Sony E-Mount'),
            ('Condition', 'Excellent'),
          ];
          return Wrap(
            spacing: 8,
            runSpacing: 8,
            children: data
                .map(
                  (item) => SizedBox(
                    width: (constraints.maxWidth - 8) / 2,
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.$1.toUpperCase(),
                            style: const TextStyle(
                              color: AppColors.secondaryText,
                              fontSize: 10,
                            ),
                          ),
                          Text(item.$2),
                        ],
                      ),
                    ),
                  ),
                )
                .toList(),
          );
        },
      );
}

class _DetailExpansion extends StatelessWidget {
  const _DetailExpansion({
    required this.title,
    required this.icon,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: ExpansionTile(
          leading: Icon(icon, color: AppColors.primaryDark),
          title: Text(title),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [Align(alignment: Alignment.centerLeft, child: child)],
        ),
      );
}

class BookingsPage extends StatefulWidget {
  const BookingsPage({super.key, required this.latestDraft});

  final BookingDraft? Function() latestDraft;

  @override
  State<BookingsPage> createState() => BookingsPageState();
}

class BookingsPageState extends State<BookingsPage>
    with SingleTickerProviderStateMixin {
  late final TabController tabs;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    tabs = TabController(length: 4, vsync: this);
    Future<void>.delayed(const Duration(milliseconds: 180), () {
      if (mounted) setState(() => loading = false);
    });
  }

  @override
  void dispose() {
    tabs.dispose();
    super.dispose();
  }

  void showPending() {
    tabs.animateTo(0);
    if (mounted) setState(() {});
  }

  List<_BookingRecord> _records(BuildContext context) {
    final controller = context.watch<BookingController?>();
    final latest = controller?.latest;
    final draft = widget.latestDraft();
    final now = dateOnly(DateTime.now());
    final records = <_BookingRecord>[];
    if (latest != null) {
      final listing = MockData.listings.firstWhere(
        (item) => item.id == latest.listingId,
        orElse: () => MockData.listings.first,
      );
      final days = latest.end.difference(latest.start).inDays + 1;
      records.add(
        _BookingRecord(
          id: latest.id,
          listingId: listing.id,
          title: listing.title,
          dates: formatDateRange(latest.start, latest.end),
          status: latest.status,
          amount: draft?.createdBooking?.id == latest.id
              ? draft!.total
              : listing.dailyPrice * days +
                  BookingPolicies.forListing(listing).deposit,
        ),
      );
    }
    records.addAll([
      _BookingRecord(
        id: 'active-myvi',
        listingId: 'l-car',
        title: 'Perodua Myvi 2022',
        dates: formatDateRange(
          now.add(const Duration(days: 1)),
          now.add(const Duration(days: 3)),
        ),
        status: 'active',
        amount: 450,
      ),
      _BookingRecord(
        id: 'completed-camera',
        listingId: 'l-photo',
        title: 'Event Photography Package',
        dates: formatDateRange(
          now.subtract(const Duration(days: 20)),
          now.subtract(const Duration(days: 20)),
        ),
        status: 'completed',
        amount: 650,
      ),
      _BookingRecord(
        id: 'cancelled-tent',
        listingId: 'l-tent',
        title: 'Four-person Camping Tent',
        dates: formatDateRange(
          now.subtract(const Duration(days: 35)),
          now.subtract(const Duration(days: 33)),
        ),
        status: 'cancelled',
        amount: 135,
      ),
    ]);
    return records;
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(
        body: SafeArea(
          child: RentHubFeedbackState(
            kind: FeedbackKind.loading,
            title: 'Loading bookings',
            message: 'Organising your local booking history…',
          ),
        ),
      );
    }
    final records = _records(context);
    const statuses = ['pending', 'active', 'completed', 'cancelled'];
    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RentHubLogo(),
            Text(
              'My Bookings',
              style: TextStyle(fontSize: 16, color: AppColors.text),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Booking notifications',
            onPressed: () => Navigator.push<void>(
              context,
              MaterialPageRoute(builder: (_) => const NotificationsPage()),
            ),
            icon: const Badge(child: Icon(Icons.notifications_outlined)),
          ),
        ],
        bottom: TabBar(
          controller: tabs,
          isScrollable: true,
          tabs: const [
            Tab(text: 'Pending'),
            Tab(text: 'Active'),
            Tab(text: 'Completed'),
            Tab(text: 'Cancelled'),
          ],
        ),
      ),
      body: TabBarView(
        controller: tabs,
        children: statuses.map((status) {
          final matching = records
              .where((record) => record.status.toLowerCase() == status)
              .toList();
          if (matching.isEmpty) {
            return RentHubFeedbackState(
              kind: FeedbackKind.empty,
              title: 'No ${status.toLowerCase()} bookings',
              message: 'Bookings with this status will appear here.',
            );
          }
          return ListView.separated(
            key: PageStorageKey('bookings-$status'),
            padding: const EdgeInsets.all(16),
            itemCount: matching.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, itemIndex) => _BookingCard(
              record: matching[itemIndex],
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _BookingRecord {
  const _BookingRecord({
    required this.id,
    required this.listingId,
    required this.title,
    required this.dates,
    required this.status,
    required this.amount,
  });

  final String id;
  final String listingId;
  final String title;
  final String dates;
  final String status;
  final double amount;
}

class _BookingCard extends StatelessWidget {
  const _BookingCard({required this.record});

  final _BookingRecord record;

  void _openDetails(BuildContext context) {
    final listing = MockData.listings.firstWhere(
      (item) => item.id == record.listingId,
      orElse: () => MockData.listings.first,
    );
    Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => listing.isService
            ? ServiceHistoricalDetailsPage(
                service: listing,
                status: record.status,
                dates: record.dates,
                amount: record.amount,
              )
            : PhysicalRentalDetailsPage(
                listing: listing,
                status: record.status,
                dates: record.dates,
                amount: record.amount,
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 76,
                    height: 64,
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.photo_camera_outlined,
                      color: AppColors.primaryDark,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          record.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          record.dates,
                          style: const TextStyle(
                            color: AppColors.secondaryText,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          formatMoney(record.amount),
                          style: const TextStyle(
                            color: AppColors.primaryDark,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const Divider(height: 22),
              LayoutBuilder(
                builder: (context, constraints) => Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    StatusBadge(
                      record.status == 'pending'
                          ? 'Pending Owner Approval'
                          : record.status,
                    ),
                    OutlinedButton(
                      onPressed: () => _openDetails(context),
                      child: const Text('View Details'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}

class _ListingPlaceholder extends StatelessWidget {
  const _ListingPlaceholder({required this.listing, this.large = false});

  final Listing listing;
  final bool large;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: AppColors.background,
          border: Border.all(color: AppColors.border),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppColors.background, AppColors.primaryLight],
                  ),
                ),
              ),
            ),
            Icon(
              listing.category == 'Vehicles'
                  ? Icons.directions_car
                  : listing.isService
                      ? Icons.camera_outlined
                      : Icons.photo_camera,
              size: large ? 108 : 64,
              color: AppColors.primaryDark,
              semanticLabel: '${listing.title} image placeholder',
            ),
          ],
        ),
      );
}

class _TinyBadge extends StatelessWidget {
  const _TinyBadge({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.background.withValues(alpha: .94),
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: color.withValues(alpha: .45)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 13),
            const SizedBox(width: 3),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 9,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
}

class MessagesPage extends StatelessWidget {
  const MessagesPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Messages')),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: TextField(
                  decoration: InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Search conversations',
                  ),
                ),
              ),
              for (final listing in MockData.listings.take(4))
                ListTile(
                  minVerticalPadding: 12,
                  leading: CircleAvatar(child: Text(listing.ownerName[0])),
                  title: Text(listing.ownerName),
                  subtitle: Text(
                    listing.isService
                        ? 'I reviewed your service requirements.'
                        : 'Yes, the selected date is available.',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: const Text('10:24'),
                  onTap: () => Navigator.push<void>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => InteractiveChatPage(
                        name: listing.ownerName,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
}

class InteractiveChatPage extends StatefulWidget {
  const InteractiveChatPage({super.key, required this.name});
  final String name;

  @override
  State<InteractiveChatPage> createState() => _InteractiveChatPageState();
}

class _InteractiveChatPageState extends State<InteractiveChatPage> {
  final input = TextEditingController();
  final sent = <String>[];

  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  void _send() {
    final value = input.text.trim();
    if (value.isEmpty) return;
    setState(() {
      sent.add(value);
      input.clear();
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.name),
              const Text(
                'Usually replies within 30 min',
                style: TextStyle(fontSize: 11, color: AppColors.secondaryText),
              ),
            ],
          ),
        ),
        body: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Chip(label: Text('Hi! The listing is available.')),
                  ),
                  const Align(
                    alignment: Alignment.centerRight,
                    child: Chip(
                      backgroundColor: AppColors.primaryLight,
                      label: Text('Great, I will make a booking.'),
                    ),
                  ),
                  for (final message in sent)
                    Align(
                      alignment: Alignment.centerRight,
                      child: Chip(
                        backgroundColor: AppColors.primaryLight,
                        label: Text(message),
                      ),
                    ),
                ],
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: TextField(
                  controller: input,
                  onSubmitted: (_) => _send(),
                  decoration: InputDecoration(
                    hintText: 'Write a message',
                    suffixIcon: IconButton(
                      tooltip: 'Send message',
                      onPressed: _send,
                      icon: const Icon(Icons.send),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
}

class ChatPage extends StatelessWidget {
  const ChatPage({super.key, required this.name});

  final String name;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(name)),
        body: Column(
          children: [
            const Expanded(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Chip(
                        label: Text('Hi! The listing is available.'),
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Chip(
                        backgroundColor: AppColors.primaryLight,
                        label: Text('Great, I’ll make a booking.'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SafeArea(
              child: Padding(
                padding: EdgeInsets.all(12),
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Write a message',
                    suffixIcon: Icon(Icons.send),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
}

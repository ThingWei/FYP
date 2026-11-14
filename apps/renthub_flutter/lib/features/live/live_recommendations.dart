import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/location/current_location.dart';
import '../../core/recommendations/recommendation_models.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/models/domain_models.dart';
import '../../shared/widgets/renthub_components.dart';
import 'live_location_picker.dart';
import 'live_renthub_controller.dart';
import 'live_listing_collection.dart';

class RecommendationListingTile extends StatelessWidget {
  const RecommendationListingTile(
      {super.key, required this.listing, required this.onOpen, this.trailing});
  final Listing listing;
  final VoidCallback onOpen;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Card(
      child: InkWell(
          onTap: onOpen,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
              padding: const EdgeInsets.all(12),
              child:
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                ListingThumbnail(listing: listing),
                const SizedBox(width: 12),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(listing.title,
                          style: Theme.of(context).textTheme.titleSmall),
                      Text('${listing.category} · ${listing.subcategory}'),
                      if (listing.promotionActive) const Text('Promoted'),
                      if (listing.verified)
                        Text(listing.isService ? 'Verified' : 'Verified item'),
                      Text(
                          'RM ${listing.displayPrice.toStringAsFixed(2)} / ${listing.priceUnit}',
                          style: const TextStyle(
                              color: AppColors.primaryDark,
                              fontWeight: FontWeight.w700)),
                      Text('Approximate area: ${listing.location}'),
                      if (listing.recommendationAvailability.isNotEmpty)
                        Text(listing.recommendationAvailability),
                      if (listing.recommendationReason.isNotEmpty)
                        Text(listing.recommendationReason,
                            style: const TextStyle(
                                color: AppColors.secondaryText)),
                    ])),
                if (trailing != null) trailing!,
              ]))));
}

class ListingThumbnail extends StatelessWidget {
  const ListingThumbnail({super.key, required this.listing});
  final Listing listing;
  @override
  Widget build(BuildContext context) {
    final api = context.read<LiveRentHubController>().api;
    final fallback = Icon(
        listing.isService
            ? Icons.design_services_outlined
            : Icons.inventory_2_outlined,
        color: AppColors.primary);
    return Container(
        width: 64,
        height: 64,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
            color: AppColors.primaryLight,
            borderRadius: BorderRadius.circular(12)),
        child: listing.images.isEmpty
            ? fallback
            : Image.network(api.publicPhotoUrl(listing.images.first),
                semanticLabel: listing.title,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => fallback));
  }
}

class RecommendationSectionView extends StatelessWidget {
  const RecommendationSectionView(
      {super.key,
      required this.title,
      required this.section,
      required this.onOpen,
      required this.onRetry,
      this.loading = false,
      this.onClear,
      this.refreshFailed = false,
      this.headerActions,
      this.contextLabel,
      this.emptyMessage,
      this.actions,
      this.mode = ListingViewMode.carousel});
  final ListingViewMode mode;
  final bool refreshFailed;
  final Widget? headerActions;
  final String? contextLabel, emptyMessage;
  final String title;
  final RecommendationSection section;
  final ValueChanged<Listing> onOpen;
  final VoidCallback onRetry;
  final bool loading;
  final VoidCallback? onClear;
  final Widget Function(Listing)? actions;
  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SizedBox(height: 16),
        Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              if (headerActions != null) headerActions!,
              if (section.items.isNotEmpty)
                TextButton(
                    onPressed: () => Navigator.push<void>(
                        context,
                        MaterialPageRoute(
                            builder: (_) => ListingCollectionPage(
                                title: title,
                                items: section.items,
                                onOpen: onOpen,
                                actions: actions))),
                    child: const Text('See all')),
              if (onClear != null)
                TextButton(
                    onPressed: onClear, child: const Text('Clear history')),
            ]),
        if (contextLabel != null)
          Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(contextLabel!,
                  style: const TextStyle(color: AppColors.secondaryText))),
        if (loading) const LinearProgressIndicator(),
        if (!loading && section.items.isEmpty)
          Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(emptyMessage ??
                  (section.status == 'location_required'
                      ? 'Choose an area to see what is trending nearby.'
                      : section.status == 'unavailable'
                          ? 'These suggestions are unavailable right now. Your other sections still work.'
                          : title == 'Recently Viewed'
                              ? 'Listings you open will appear here.'
                              : title == 'Trending Near You'
                                  ? 'Not enough recent rental activity in this area yet.'
                                  : title == 'You Might Also Need'
                                      ? 'No suitable complementary items are available yet.'
                                      : 'No suggestions yet. Explore more listings.'))),
        if (!loading && (section.status == 'unavailable' || refreshFailed))
          Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: Text(section.items.isEmpty
                      ? 'Retry'
                      : 'Could not update. Retry'))),
        if (!loading &&
            section.status == 'empty' &&
            title != 'You Might Also Need')
          Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                  onPressed: () =>
                      context.read<LiveRentHubController>().selectRenterTab(1),
                  child: const Text('Explore rentals'))),
        if (section.items.isNotEmpty)
          ListingCollection(
              items: section.items
                  .take(mode == ListingViewMode.grid ? 16 : 6)
                  .toList(),
              onOpen: onOpen,
              actions: actions,
              mode: mode),
      ]);
}

class LiveRecommendationHomeContent extends StatefulWidget {
  const LiveRecommendationHomeContent(
      {super.key,
      required this.onOpen,
      this.actions,
      this.positionClient,
      this.onAreaChanged,
      this.viewMode = ListingViewMode.carousel,
      this.showAreaControls = false});
  final ListingViewMode viewMode;
  final bool showAreaControls;
  final Future<void> Function(Listing) onOpen;
  final Widget Function(Listing)? actions;
  final CurrentLocationClient? positionClient;
  final void Function(ListingLocationSelection?, int)? onAreaChanged;
  @override
  State<LiveRecommendationHomeContent> createState() =>
      _LiveRecommendationHomeContentState();
}

class _LiveRecommendationHomeContentState
    extends State<LiveRecommendationHomeContent> with WidgetsBindingObserver {
  String? _user;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = context.watch<LiveRentHubController>();
    if (_user != controller.profile?.id) {
      controller.prepareRecommendationAccount();
      _user = controller.profile?.id;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(controller.ensureRecommendationFeed());
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final c = context.read<LiveRentHubController>();
    if (c.renterTabIndex == 0) {
      unawaited(c.ensureRecommendationFeed());
    }
  }

  String _trendingTitle(RecommendationSection section) =>
      section.basis == 'highlights' ? 'Explore Rentals' : 'Trending Now';

  @override
  Widget build(BuildContext context) {
    final c = context.watch<LiveRentHubController>();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final entry in {
        'recommended': 'Recommended For You',
        if (c.recommendationCentre != null) 'nearby': 'Near You',
        'trending': 'Trending Now',
        'recentlyViewed': 'Recently Viewed'
      }.entries)
        RecommendationSectionView(
            title: entry.key == 'trending'
                ? _trendingTitle(c.recommendationSections[entry.key] ??
                    const RecommendationSection('empty'))
                : entry.value,
            contextLabel: entry.key == 'nearby'
                ? '${c.recommendationRadius} km · Approximate area'
                : null,
            emptyMessage: entry.key == 'nearby'
                ? 'No nearby rentals match your filters.'
                : null,
            mode: widget.viewMode,
            section: c.recommendationSections[entry.key] ??
                const RecommendationSection('empty'),
            loading: c.recommendationLoadingSections.contains(entry.key),
            refreshFailed: c.recommendationFailures.contains(entry.key),
            onRetry: () => c.refreshRecommendationFeed(section: entry.key),
            actions: widget.actions,
            onOpen: (item) async {
              await widget.onOpen(item);
              if (mounted) await c.ensureRecommendationFeed();
            },
            onClear: entry.key != 'recentlyViewed'
                ? null
                : () async {
                    final accepted = await confirmAction(context,
                        title: 'Clear browsing history?',
                        message:
                            'Remove your recently viewed listings and their browsing signals. Saved listings and rentals stay unchanged.',
                        action: 'Clear history');
                    if (accepted) {
                      try {
                        await c.clearBrowsingHistory();
                      } catch (_) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                              content: Text(
                                  'History could not be cleared. Try again.')));
                        }
                      }
                    }
                  }),
    ]);
  }
}

class LiveComplementsSection extends StatefulWidget {
  const LiveComplementsSection(
      {super.key, required this.listingId, required this.onOpen});
  final String listingId;
  final ValueChanged<Listing> onOpen;
  @override
  State<LiveComplementsSection> createState() => _LiveComplementsSectionState();
}

class _LiveComplementsSectionState extends State<LiveComplementsSection> {
  RecommendationSection section = const RecommendationSection('empty');
  bool loading = true;
  int generation = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  @override
  void didUpdateWidget(covariant LiveComplementsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.listingId != widget.listingId) {
      generation++;
      section = const RecommendationSection('empty');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _load();
      });
    }
  }

  Future<void> _load() async {
    final request = ++generation;
    final c = context.read<LiveRentHubController>(),
        user = context.read<LiveRentHubController>().profile?.id;
    setState(() => loading = true);
    final response = await c.complementaryListings(widget.listingId);
    if (mounted && request == generation && user == c.profile?.id) {
      setState(() {
        section = response;
        loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => RecommendationSectionView(
      title: 'You Might Also Need',
      section: section,
      loading: loading,
      onOpen: widget.onOpen,
      onRetry: _load);
}

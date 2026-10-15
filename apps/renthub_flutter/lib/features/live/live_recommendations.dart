import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:latlong2/latlong.dart';
import '../../core/location/current_location.dart';
import '../../core/recommendations/recommendation_models.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/models/domain_models.dart';
import '../../shared/widgets/renthub_components.dart';
import 'live_location_picker.dart';
import 'live_renthub_controller.dart';

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
            : Image.network(api.absoluteUrl(listing.images.first),
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
      this.actions});
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
              if (section.items.isNotEmpty)
                TextButton(
                    onPressed: () => Navigator.push<void>(
                        context,
                        MaterialPageRoute(
                            builder: (_) => Scaffold(
                                appBar: AppBar(title: Text(title)),
                                body: ListView(
                                    padding: const EdgeInsets.all(16),
                                    children: [
                                      for (final item in section.items)
                                        RecommendationListingTile(
                                            listing: item,
                                            onOpen: () => onOpen(item),
                                            trailing: actions?.call(item)),
                                    ])))),
                    child: const Text('See all')),
              if (onClear != null)
                TextButton(
                    onPressed: onClear, child: const Text('Clear history')),
            ]),
        if (loading) const LinearProgressIndicator(),
        if (!loading && section.items.isEmpty)
          Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(section.status == 'location_required'
                  ? 'Choose an area to see what is trending nearby.'
                  : section.status == 'unavailable'
                      ? 'These suggestions are unavailable right now. Your other sections still work.'
                      : title == 'Recently Viewed'
                          ? 'Listings you open will appear here.'
                          : title == 'Trending Near You'
                              ? 'Not enough recent rental activity in this area yet.'
                              : title == 'You Might Also Need'
                                  ? 'No suitable complementary items are available yet.'
                                  : 'No suggestions yet. Explore more listings.')),
        if (!loading && section.status == 'unavailable')
          Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'))),
        for (final item in section.items.take(6))
          RecommendationListingTile(
              listing: item,
              onOpen: () => onOpen(item),
              trailing: actions?.call(item)),
      ]);
}

class LiveRecommendationHomeContent extends StatefulWidget {
  const LiveRecommendationHomeContent(
      {super.key, required this.onOpen, this.actions, this.positionClient});
  final Future<void> Function(Listing) onOpen;
  final Widget Function(Listing)? actions;
  final CurrentLocationClient? positionClient;
  @override
  State<LiveRecommendationHomeContent> createState() =>
      _LiveRecommendationHomeContentState();
}

class _LiveRecommendationHomeContentState
    extends State<LiveRecommendationHomeContent> with WidgetsBindingObserver {
  String? _user;
  bool locating = false;
  String? locationMessage;
  int locationGeneration = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    locationGeneration++;
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
      locationGeneration++;
      locating = false;
      locationMessage = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(controller.refreshRecommendationFeed());
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final c = context.read<LiveRentHubController>();
    if (c.renterTabIndex == 0 &&
        (c.recommendationDirty ||
            c.recommendationUpdatedAt == null ||
            DateTime.now().difference(c.recommendationUpdatedAt!).inSeconds >
                60)) {
      unawaited(c.refreshRecommendationFeed());
    }
  }

  Future<void> _gps() async {
    final c = context.read<LiveRentHubController>();
    final user = c.profile?.id;
    final generation = ++locationGeneration;
    setState(() {
      locating = true;
      locationMessage = null;
    });
    try {
      final reading =
          await (widget.positionClient ?? AndroidCurrentLocationClient())
              .current()
              .timeout(const Duration(seconds: 15));
      if (!mounted ||
          generation != locationGeneration ||
          user != c.profile?.id) {
        return;
      }
      c.setRecommendationArea(
          ListingLocationSelection(
              label: 'Current location',
              point: LatLng(reading.latitude, reading.longitude),
              source: 'gps',
              accuracyMeters: reading.accuracy),
          c.recommendationRadius);
      setState(() => locationMessage =
          'Reported accuracy: ${reading.accuracy.round()} m.${reading.approximate || reading.accuracy > 50 ? ' This is approximate. Choose an area to adjust your centre.' : ''}');
    } catch (error) {
      if (mounted && generation == locationGeneration) {
        setState(() => locationMessage = error is CurrentLocationFailure
            ? error.message
            : 'Current location is unavailable. Choose an area or try again.');
      }
    } finally {
      if (mounted && generation == locationGeneration) {
        setState(() => locating = false);
      }
    }
  }

  Future<void> _choose() async {
    final c = context.read<LiveRentHubController>();
    final user = c.profile?.id;
    final generation = ++locationGeneration;
    setState(() => locating = false);
    final selected = await Navigator.push<ListingLocationSelection>(
        context,
        MaterialPageRoute(
            builder: (_) => LiveLocationPicker(
                api: ListingLocationApi(c.api),
                initialSelection: c.recommendationCentre,
                title: 'Choose your search area')));
    if (!mounted ||
        generation != locationGeneration ||
        user != c.profile?.id ||
        selected == null) {
      return;
    }
    setState(() => locationMessage = null);
    c.setRecommendationArea(selected, c.recommendationRadius);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<LiveRentHubController>();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Card(
          child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                        c.recommendationCentre?.label ??
                            'Discover rentals around you',
                        style: Theme.of(context).textTheme.titleMedium),
                    Wrap(spacing: 8, children: [
                      TextButton.icon(
                          onPressed: locating ? null : _gps,
                          icon: const Icon(Icons.my_location),
                          label: Text(locating
                              ? 'Finding location…'
                              : 'Use current location')),
                      TextButton.icon(
                          onPressed: _choose,
                          icon: const Icon(Icons.map_outlined),
                          label: const Text('Choose area')),
                      if (c.recommendationCentre != null)
                        TextButton(
                            onPressed: () {
                              locationGeneration++;
                              setState(() {
                                locating = false;
                                locationMessage = null;
                              });
                              c.setRecommendationArea(null, 10);
                            },
                            child: const Text('Clear area')),
                    ]),
                    if (c.recommendationCentre != null)
                      DropdownButtonFormField<int>(
                          initialValue: c.recommendationRadius,
                          decoration:
                              const InputDecoration(labelText: 'Nearby radius'),
                          items: [
                            for (final km in [5, 10, 25, 50])
                              DropdownMenuItem(value: km, child: Text('$km km'))
                          ],
                          onChanged: (v) {
                            if (v != null) {
                              c.setRecommendationArea(
                                  c.recommendationCentre, v);
                            }
                          }),
                    if (locationMessage != null) Text(locationMessage!),
                    const Text(
                        'Nearby uses approximate listing areas. Listings without a usable map pin are not included.'),
                  ]))),
      for (final entry in const {
        'recommended': 'Recommended For You',
        'trending': 'Trending Near You',
        'recentlyViewed': 'Recently Viewed'
      }.entries)
        RecommendationSectionView(
            title: entry.value,
            section: c.recommendationSections[entry.key] ??
                const RecommendationSection('empty'),
            loading: c.recommendationLoadingSections.contains(entry.key),
            onRetry: () => c.refreshRecommendationFeed(section: entry.key),
            actions: widget.actions,
            onOpen: (item) async {
              await widget.onOpen(item);
              if (mounted) await c.refreshRecommendationFeed();
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

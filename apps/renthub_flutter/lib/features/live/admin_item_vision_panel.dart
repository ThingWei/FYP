import 'admin_route_observer.dart';
import 'package:flutter/foundation.dart';
import '../../core/theme/app_theme.dart';
import 'live_listing_image.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/network/user_facing_error.dart';
import '../../shared/models/domain_models.dart';
import 'admin_record_models.dart';
import 'live_listing_photo_viewer.dart';
import 'live_renthub_controller.dart';

class AdminItemVisionPanel extends StatefulWidget {
  const AdminItemVisionPanel(
      {super.key, required this.listingId, required this.photos, this.initial});
  final String listingId;
  final List<String> photos;
  final Map? initial;
  @override
  State<AdminItemVisionPanel> createState() => _AdminItemVisionPanelState();
}

class _AdminItemVisionPanelState extends State<AdminItemVisionPanel>
    with WidgetsBindingObserver, RouteAware {
  late Map review;
  Timer? timer;
  int generation = 0, polls = 0;
  int? account;
  String? viewer;
  int selectedPhoto = 0;
  bool visible = true, routeActive = true;
  ModalRoute<dynamic>? observedRoute;
  bool busy = false;
  Object? error;
  @override
  void initState() {
    super.initState();
    account = context.read<LiveRentHubController?>()?.accountGeneration;
    review = widget.initial ??
        const {'state': 'unavailable', 'reason': 'not_checked'};
    viewer = context.read<LiveRentHubController?>()?.profile?.id;
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) refresh(ensure: review['state'] != 'ready');
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != observedRoute) {
      adminRouteObserver.unsubscribe(this);
      observedRoute = route;
      if (route != null) {
        adminRouteObserver.subscribe(this, route);
        routeActive = route.isCurrent;
      }
    }
  }

  @override
  void didPushNext() {
    routeActive = false;
    timer?.cancel();
  }

  @override
  void didPopNext() {
    routeActive = true;
    if (mounted && visible) refresh();
  }

  @override
  void didPop() {
    routeActive = false;
    timer?.cancel();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    visible = state == AppLifecycleState.resumed;
    if (!visible) {
      timer?.cancel();
      return;
    }
    if (mounted && routeActive) refresh();
  }

  @override
  void didUpdateWidget(covariant AdminItemVisionPanel old) {
    super.didUpdateWidget(old);
    if (old.listingId != widget.listingId ||
        !listEquals(old.photos, widget.photos) ||
        old.initial?['reviewKey'] != widget.initial?['reviewKey']) {
      generation++;
      review = widget.initial ??
          const {'state': 'unavailable', 'reason': 'not_checked'};
      busy = false;
      error = null;
      polls = 0;
      selectedPhoto = 0;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) refresh(ensure: review['state'] != 'ready');
      });
    }
  }

  bool allowed(LiveRentHubController? c) =>
      c != null &&
      c.accountGeneration == account &&
      c.profile?.id == viewer &&
      c.profile?.roles.contains(UserRole.admin) == true;
  bool get pending => ['queued', 'running'].contains(review['state']);
  void schedule() {
    timer?.cancel();
    if (pending && visible && mounted && routeActive) {
      final seconds = ['budget', 'quota'].contains(review['reason'])
          ? 60
          : polls < 24
              ? 5
              : 15;
      timer = Timer(Duration(seconds: seconds), () {
        polls++;
        refresh();
      });
    }
  }

  Future<void> refresh({bool retry = false, bool ensure = false}) async {
    final c = context.read<LiveRentHubController?>();
    if (busy || !allowed(c)) return;
    final request = ++generation;
    final post = retry || ensure;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final response = await c!.api.request(
          post ? 'POST' : 'GET',
          post
              ? '/admin/listings/${Uri.encodeComponent(widget.listingId)}/photo-review'
              : '/admin/records/listings/${Uri.encodeComponent(widget.listingId)}',
          body: post ? {'intent': retry ? 'retry' : 'ensure'} : null);
      final data = post
          ? response
          : response is Map && response['record'] is Map
              ? response['record']['itemVisionReview']
              : null;
      if (data is! Map ||
          !['queued', 'running', 'ready', 'unavailable', 'stale']
              .contains(data['state'])) {
        throw const FormatException('Invalid review');
      }
      if (mounted && allowed(c) && request == generation) {
        setState(() => review = data);
        if (post) polls = 0;
      }
    } catch (e) {
      if (mounted && allowed(c) && request == generation) {
        setState(() => error = e);
      }
    } finally {
      if (mounted && request == generation) {
        setState(() => busy = false);
        schedule();
      }
    }
    if (mounted &&
        request == generation &&
        !post &&
        review['reason'] == 'not_checked' &&
        review['canRequest'] == true) {
      await refresh(ensure: true);
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    adminRouteObserver.unsubscribe(this);
    generation++;
    super.dispose();
  }

  static const labels = <String, String>{
    'consistent': 'Possible match',
    'inconsistent': 'Difference detected',
    'cannot_assess': 'Unable to assess',
    'no_obvious_damage': 'No obvious damage visible',
    'visible_wear': 'Visible wear',
    'visible_damage': 'Visible damage',
    'not_readable': 'Not readable',
    'not_applicable': 'Not applicable',
  };
  String get dailyAllowanceMessage {
    final allowance = review['allowance'];
    if (allowance is! Map || allowance['source'] != 'renthub') {
      return 'RentHub’s daily photo-check allowance has been used.';
    }
    return 'RentHub’s daily allowance is used (${allowance['used']}/${allowance['limit']} attempts). Resets ${adminDate(allowance['resetsAt'])}.';
  }

  String get message => switch (review['reason']) {
        'not_enabled' ||
        'not_configured' =>
          'The photo review service needs setup. Contact your system maintainer.',
        'invalid_photos' ||
        'sensitive_content' =>
          'Review these photos manually.',
        'budget' => dailyAllowanceMessage,
        'quota' ||
        'rate_limit' =>
          'Waiting for the next available photo check.',
        'not_checked' => 'Check the photos to see the assessment.',
        'provider_busy' => 'Photo checks are busy. Try again shortly.',
        'timeout' => 'The check took too long. Try again.',
        _ => 'The photo review service is temporarily unavailable.',
      };
  @override
  Widget build(BuildContext context) {
    final c = context.watch<LiveRentHubController?>();
    final accessible = account == null || c?.accountGeneration == account;
    if (!accessible) return const Text('Review unavailable for this account.');
    final findings = review['observations'] is Map
        ? review['observations'] as Map
        : const {};
    final photoFindings = (findings['photo_findings'] as List? ?? const [])
        .whereType<Map>()
        .toList();
    final setFindings = (findings['set_findings'] as List? ?? const [])
        .whereType<Map>()
        .toList();
    final ready = review['state'] == 'ready' && photoFindings.isNotEmpty;
    final attention = photoFindings.any(
            (photo) => (photo['concerns'] as List? ?? const []).isNotEmpty) ||
        setFindings.any((finding) => finding['kind'] == 'concern') ||
        findings.values.contains('inconsistent') ||
        findings['visible_condition'] == 'visible_damage';
    final waitingForQuota =
        ['budget', 'quota', 'rate_limit'].contains(review['reason']);
    final title = busy && !ready
        ? 'Loading assessment'
        : pending
            ? review['state'] == 'running'
                ? 'Checking photos'
                : 'Waiting to check'
            : ready
                ? attention
                    ? 'Needs attention'
                    : 'Assessment ready'
                : switch (review['reason']) {
                    'not_enabled' || 'not_configured' => 'Setup needed',
                    'budget' => 'Daily allowance used',
                    'quota' || 'rate_limit' => 'Waiting to check',
                    'not_checked' => 'Ready to check',
                    'invalid_photos' ||
                    'sensitive_content' ||
                    'not_assessed' =>
                      'Manual review needed',
                    'timeout' || 'invalid_response' => 'Check incomplete',
                    _ => 'Service unavailable',
                  };
    final tone = ready
        ? attention
            ? AppColors.warning
            : AppColors.primary
        : AppColors.secondaryText;
    final content = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Icon(
                color: tone,
                pending
                    ? Icons.hourglass_top
                    : ready
                        ? Icons.fact_check_outlined
                        : Icons.info_outline),
            const SizedBox(width: 8),
            Expanded(
                child:
                    Text(title, style: Theme.of(context).textTheme.titleMedium))
          ]),
          const SizedBox(height: 12),
          if (pending || busy && !ready) ...[
            const LinearProgressIndicator(),
            const SizedBox(height: 8),
            Text(
                waitingForQuota ? message : 'The assessment will appear here.'),
          ] else if (!ready)
            Text(message),
          if (ready) ...[
            LayoutBuilder(builder: (context, constraints) {
              final width = constraints.maxWidth >= 520
                  ? (constraints.maxWidth - 12) / 2
                  : constraints.maxWidth;
              return Wrap(spacing: 12, runSpacing: 12, children: [
                for (final entry in const {
                  'item_consistency': 'Item type',
                  'photo_consistency': 'Across photos',
                  'visible_condition': 'Visible condition',
                  'visible_branding': 'Branding',
                }.entries)
                  Container(
                      width: width,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.border)),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(entry.value,
                                style: Theme.of(context).textTheme.bodySmall),
                            const SizedBox(height: 4),
                            Text(
                                entry.key == 'photo_consistency' &&
                                        findings[entry.key] == 'consistent'
                                    ? 'Appear consistent'
                                    : labels[findings[entry.key]] ??
                                        'Unable to assess',
                                style: Theme.of(context).textTheme.titleSmall),
                          ])),
              ]);
            }),
            const SizedBox(height: 16),
            Text('By photo', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  for (var index = 0; index < photoFindings.length; index++)
                    Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                            label:
                                Text('Photo ${photoFindings[index]['photo']}'),
                            selected: selectedPhoto == index,
                            onSelected: (_) =>
                                setState(() => selectedPhoto = index))),
                ])),
            const SizedBox(height: 8),
            photoCard(
                context,
                photoFindings[
                    selectedPhoto.clamp(0, photoFindings.length - 1)]),
            if (setFindings.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Across-photo notes',
                  style: Theme.of(context).textTheme.titleSmall),
              for (final finding in setFindings)
                ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                        'Photos ${(finding['photos'] as List).join(', ')}'),
                    subtitle: Text('${finding['observation']}'),
                    leading: Icon(finding['kind'] == 'concern'
                        ? Icons.info_outline
                        : Icons.collections_outlined)),
            ],
            const SizedBox(height: 8),
            const Text('Photos cannot establish authenticity or ownership.'),
            if (review['checkedAt'] != null)
              Text(adminDate(review['checkedAt']),
                  style: Theme.of(context).textTheme.bodySmall),
          ],
          if (error != null)
            Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(friendlyError(error!))),
          if (ready &&
              review['availability'] is Map &&
              review['availability']['ready'] == false)
            const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                    'Showing the saved assessment. New checks are temporarily unavailable.')),
          if (allowed(c))
            Wrap(spacing: 8, children: [
              TextButton.icon(
                  onPressed: busy ? null : () => refresh(),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Refresh')),
              if (!pending && !ready && review['canRequest'] == true)
                OutlinedButton(
                    onPressed: busy ? null : () => refresh(retry: true),
                    child: Text([
                      'timeout',
                      'provider_busy',
                      'provider_unavailable',
                      'invalid_response'
                    ].contains(review['reason'])
                        ? 'Try again'
                        : 'Check photos')),
            ]),
        ]);
    return Material(
        type: MaterialType.transparency,
        child: LayoutBuilder(
            builder: (context, constraints) => constraints.hasBoundedHeight
                ? SingleChildScrollView(child: content)
                : content));
  }

  Widget photoCard(BuildContext context, Map finding) {
    final index = (finding['photo'] as int) - 1;
    final concerns =
        (finding['concerns'] as List? ?? const []).whereType<String>();
    final notes =
        (finding['observations'] as List? ?? const []).whereType<String>();
    return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (index >= 0 && index < widget.photos.length) ...[
              SizedBox(
                  width: 80,
                  height: 80,
                  child: Semantics(
                      button: true,
                      label: 'Enlarge photo ${index + 1}',
                      child: InkWell(
                          onTap: () async {
                            await Navigator.of(context, rootNavigator: true)
                                .push<void>(MaterialPageRoute(
                                    builder: (_) => ListingPhotoViewer(
                                        photos: widget.photos,
                                        title: 'Listing photos',
                                        initialIndex: index)));
                            if (mounted) refresh();
                          },
                          child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: LiveListingImage(
                                  reference: widget.photos[index],
                                  label: 'Photo ${index + 1}',
                                  publicPhoto: true))))),
              const SizedBox(width: 12),
            ],
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text('Photo ${index + 1}',
                      style: Theme.of(context).textTheme.titleSmall),
                  if (finding['status'] == 'cannot_assess')
                    const Text('Unable to assess'),
                  for (final note in notes)
                    Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(note)),
                ])),
          ]),
          if (concerns.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('Review', style: Theme.of(context).textTheme.labelLarge),
            for (final concern in concerns)
              Padding(
                  padding: const EdgeInsets.only(top: 4), child: Text(concern)),
          ],
        ]));
  }
}

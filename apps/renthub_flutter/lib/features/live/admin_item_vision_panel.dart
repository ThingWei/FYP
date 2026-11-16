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

class _AdminItemVisionPanelState extends State<AdminItemVisionPanel> {
  late Map review;
  Timer? timer;
  int generation = 0, polls = 0;
  int? account;
  bool busy = false;
  Object? error;
  @override
  void initState() {
    super.initState();
    account = context.read<LiveRentHubController?>()?.accountGeneration;
    review = widget.initial ??
        const {'state': 'unavailable', 'reason': 'not_checked'};
    schedule();
  }

  @override
  void didUpdateWidget(covariant AdminItemVisionPanel old) {
    super.didUpdateWidget(old);
    if (old.listingId != widget.listingId || old.initial != widget.initial) {
      generation++;
      review = widget.initial ??
          const {'state': 'unavailable', 'reason': 'not_checked'};
      busy = false;
      error = null;
      polls = 0;
      schedule();
    }
  }

  bool allowed(LiveRentHubController? c) =>
      c != null &&
      c.accountGeneration == account &&
      c.profile?.roles.contains(UserRole.admin) == true;
  bool get pending => ['queued', 'running'].contains(review['state']);
  void schedule() {
    timer?.cancel();
    if (pending && polls < 24) {
      timer = Timer(const Duration(seconds: 5), () {
        polls++;
        refresh();
      });
    }
  }

  Future<void> refresh({bool retry = false}) async {
    final c = context.read<LiveRentHubController?>();
    if (busy || !allowed(c)) return;
    final request = ++generation;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final response = await c!.api.request(
          retry ? 'POST' : 'GET',
          retry
              ? '/admin/listings/${Uri.encodeComponent(widget.listingId)}/photo-review'
              : '/admin/records/listings/${Uri.encodeComponent(widget.listingId)}');
      final data = retry
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
        if (retry) polls = 0;
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
  }

  @override
  void dispose() {
    timer?.cancel();
    generation++;
    super.dispose();
  }

  static const labels = <String, String>{
    'consistent': 'Consistent',
    'inconsistent': 'Needs review',
    'cannot_assess': 'Cannot assess',
    'no_obvious_damage': 'No obvious damage visible',
    'visible_wear': 'Visible wear',
    'visible_damage': 'Visible damage',
    'not_readable': 'Not readable',
    'not_applicable': 'Not applicable',
  };
  String get message => switch (review['reason']) {
        'consent_required' =>
          'The Owner has not allowed Google photo processing.',
        'not_enabled' =>
          'Photo review is switched off in the running service. Ask the maintainer to enable it and restart the service.',
        'not_configured' =>
          'Photo review setup needs attention. Ask the maintainer to check the key and selected model.',
        'invalid_photos' ||
        'sensitive_content' =>
          'These photos need manual review.',
        'budget' ||
        'quota' =>
          'Waiting for the next photo check. You can review manually.',
        'not_checked' => 'No extra photo review has been requested.',
        _ => 'Extra photo review is unavailable. You can review manually.',
      };
  @override
  Widget build(BuildContext context) {
    final c = context.watch<LiveRentHubController?>();
    final accessible = account == null || c?.accountGeneration == account;
    if (!accessible) return const Text('Review unavailable for this account.');
    final findings = review['observations'] is Map
        ? review['observations'] as Map
        : const {};
    final ready = review['state'] == 'ready' && findings.isNotEmpty;
    final concerns = findings['concerns'] is List
        ? (findings['concerns'] as List).whereType<Map>().toList()
        : <Map>[];
    final attention = concerns.isNotEmpty ||
        findings.values.contains('inconsistent') ||
        findings['visible_condition'] == 'visible_damage';
    final title = pending
        ? 'Checking photos'
        : ready
            ? attention
                ? 'Needs attention'
                : 'Review ready'
            : review['reason'] == 'not_enabled'
                ? 'Not enabled'
                : review['reason'] == 'not_configured'
                    ? 'Setup needs attention'
                    : 'Unavailable';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Icon(pending
            ? Icons.hourglass_top
            : ready
                ? Icons.fact_check_outlined
                : Icons.info_outline),
        const SizedBox(width: 8),
        Expanded(
            child: Text(title, style: Theme.of(context).textTheme.titleMedium))
      ]),
      const SizedBox(height: 12),
      if (pending)
        const Text('You can continue reviewing the listing.')
      else if (!ready)
        Text(message),
      if (ready) ...[
        for (final entry in const {
          'item_consistency': 'Item type',
          'photo_consistency': 'Across photos',
          'visible_condition': 'Visible condition',
          'visible_branding': 'Branding'
        }.entries)
          Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Wrap(spacing: 8, children: [
                Text('${entry.value}:',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(labels[findings[entry.key]] ?? 'Cannot assess')
              ])),
        for (final finding in concerns) findingTile(context, finding),
        if (findings['observations'] is List &&
            (findings['observations'] as List).isNotEmpty)
          ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('Photo findings'),
              children: [
                for (final finding
                    in (findings['observations'] as List).whereType<Map>())
                  findingTile(context, finding)
              ]),
        const SizedBox(height: 8),
        const Text('Visual observations only. Authenticity is not verified.'),
        if (review['checkedAt'] != null)
          Text(adminDate(review['checkedAt']),
              style: Theme.of(context).textTheme.bodySmall),
      ],
      if (error != null)
        Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(friendlyError(error!))),
      if (allowed(c))
        Wrap(spacing: 8, children: [
          TextButton.icon(
              onPressed: busy ? null : () => refresh(),
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh')),
          if (!pending && !ready && review['canRequest'] == true)
            OutlinedButton(
                onPressed: busy ? null : () => refresh(retry: true),
                child: const Text('Check photos')),
        ]),
    ]);
  }

  Widget findingTile(BuildContext context, Map finding) {
    final index = finding['photo'] is int ? (finding['photo'] as int) - 1 : -1;
    return ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.photo_outlined),
        title: Text('Photo ${index + 1}'),
        subtitle: Text('${finding['observation'] ?? ''}'),
        onTap: index < 0 || index >= widget.photos.length
            ? null
            : () => Navigator.push<void>(
                context,
                MaterialPageRoute(
                    builder: (_) => ListingPhotoViewer(
                        photos: widget.photos,
                        title: 'Listing photos',
                        initialIndex: index))));
  }
}

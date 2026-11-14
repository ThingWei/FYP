import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/network/user_facing_error.dart';
import '../../core/trust/trust_profile.dart';
import 'live_renthub_controller.dart';
import 'live_trust_page.dart';
import 'live_subject_reviews.dart';

class LiveContactProfilePage extends StatefulWidget {
  const LiveContactProfilePage({super.key, this.threadId, this.userId})
      : assert(threadId != null || userId != null);
  final String? threadId, userId;
  @override
  State<LiveContactProfilePage> createState() => _LiveContactProfilePageState();
}

class _LiveContactProfilePageState extends State<LiveContactProfilePage> {
  Map<String, dynamic>? profile;
  Object? error;
  bool loading = true;
  String? account;
  int generation = 0;
  @override
  void didUpdateWidget(covariant LiveContactProfilePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId ||
        oldWidget.threadId != widget.threadId) {
      profile = null;
      load();
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        account = context.read<LiveRentHubController>().profile?.id;
        load();
      }
    });
  }

  Future<void> load() async {
    final c = context.read<LiveRentHubController>();
    final request = ++generation;
    bool current() =>
        mounted && request == generation && c.profile?.id == account;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final row = Map<String, dynamic>.from(await c.api.request(
          'GET',
          widget.userId != null
              ? '/users/${Uri.encodeComponent(widget.userId!)}/profile'
              : '/messages/threads/${widget.threadId}/participant') as Map);
      if (current()) setState(() => profile = row);
    } catch (e) {
      if (current()) setState(() => error = e);
    } finally {
      if (current()) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final allowed = account == null ||
        context.watch<LiveRentHubController>().profile?.id == account;
    final p = profile;
    return Scaffold(
        appBar: AppBar(title: const Text('Profile')),
        body: !allowed
            ? const Center(
                child: Text('Your session changed. Go back to continue.'))
            : loading
                ? const Center(child: CircularProgressIndicator())
                : error != null
                    ? Center(
                        child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(friendlyError(error!)),
                                  TextButton(
                                      onPressed: load,
                                      child: const Text('Retry'))
                                ])))
                    : p == null
                        ? const SizedBox.shrink()
                        : Center(
                            child: ConstrainedBox(
                                constraints:
                                    const BoxConstraints(maxWidth: 700),
                                child: ListView(
                                    padding: const EdgeInsets.all(20),
                                    children: [
                                      Card(
                                          child: Padding(
                                              padding: const EdgeInsets.all(24),
                                              child: Column(children: [
                                                CircleAvatar(
                                                    radius: 40,
                                                    child: ClipOval(
                                                        child: p['avatarUrl']
                                                                    is String &&
                                                                (p['avatarUrl']
                                                                        as String)
                                                                    .isNotEmpty
                                                            ? Image.network(context.read<LiveRentHubController>().api.publicPhotoUrl(p['avatarUrl'] as String),
                                                                width: 80,
                                                                height: 80,
                                                                fit: BoxFit
                                                                    .cover,
                                                                errorBuilder: (_,
                                                                        __,
                                                                        ___) =>
                                                                    const Icon(Icons.person_outline,
                                                                        size:
                                                                            40))
                                                            : const Icon(
                                                                Icons.person_outline,
                                                                size: 40))),
                                                const SizedBox(height: 16),
                                                Text('${p['displayName']}',
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .headlineSmall,
                                                    textAlign:
                                                        TextAlign.center),
                                                const SizedBox(height: 12),
                                                Chip(
                                                    avatar: Icon(p[
                                                                'verified'] ==
                                                            true
                                                        ? Icons.verified_user
                                                        : Icons.person_outline),
                                                    label: Text(p['verified'] ==
                                                            true
                                                        ? 'Identity verified'
                                                        : 'Identity not verified')),
                                                if ('${p['bio'] ?? ''}'
                                                    .isNotEmpty)
                                                  Padding(
                                                      padding:
                                                          const EdgeInsets.only(
                                                              top: 12),
                                                      child:
                                                          Text('${p['bio']}')),
                                                const SizedBox(height: 12),
                                                TrustSummaryButton(
                                                    userId: '${p['id']}',
                                                    summary:
                                                        TrustProfile.fromJson(p[
                                                                'trustProfile'])
                                                            .overall),
                                              ]))),
                                      SubjectReviewsSection(
                                          userId: '${p['id']}',
                                          role: 'overall'),
                                    ]))));
  }
}

Future<void> openMarketplaceProfile(BuildContext context, String userId) =>
    Navigator.push<void>(
        context,
        MaterialPageRoute(
            builder: (_) => LiveContactProfilePage(userId: userId)));

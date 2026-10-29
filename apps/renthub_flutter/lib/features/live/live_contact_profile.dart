import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/network/user_facing_error.dart';
import '../../core/trust/trust_profile.dart';
import 'live_renthub_controller.dart';
import 'live_trust_page.dart';

class LiveContactProfilePage extends StatefulWidget {
  const LiveContactProfilePage({super.key, required this.threadId});
  final String threadId;
  @override
  State<LiveContactProfilePage> createState() => _LiveContactProfilePageState();
}

class _LiveContactProfilePageState extends State<LiveContactProfilePage> {
  Map<String, dynamic>? profile;
  Object? error;
  bool loading = true;
  String? account;
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
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final row = Map<String, dynamic>.from(await c.api.request(
          'GET', '/messages/threads/${widget.threadId}/participant') as Map);
      if (mounted && c.profile?.id == account) setState(() => profile = row);
    } catch (e) {
      if (mounted) setState(() => error = e);
    } finally {
      if (mounted) setState(() => loading = false);
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
                child: Text('Your session changed. Return to Messages.'))
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
                                                const CircleAvatar(
                                                    radius: 36,
                                                    child: Icon(
                                                        Icons.person_outline,
                                                        size: 40)),
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
                                                const SizedBox(height: 12),
                                                TrustSummaryButton(
                                                    userId: '${p['id']}',
                                                    summary:
                                                        TrustProfile.fromJson(p[
                                                                'trustProfile'])
                                                            .overall),
                                              ]))),
                                      const Padding(
                                          padding: EdgeInsets.all(12),
                                          child: Text(
                                              'Review the person’s verification and rental history alongside your conversation before deciding on a booking.')),
                                    ]))));
  }
}

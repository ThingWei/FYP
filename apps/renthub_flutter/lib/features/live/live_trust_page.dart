import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/trust/trust_profile.dart';
import '../../core/network/user_facing_error.dart';
import 'live_renthub_controller.dart';
import 'live_subject_reviews.dart';
import '../../shared/widgets/trust_indicator.dart';

Future<void> openTrustDetails(BuildContext context, String userId,
        {String role = 'overall'}) =>
    Navigator.push<void>(
        context,
        MaterialPageRoute(
            builder: (_) => LiveTrustPage(userId: userId, role: role)));

class TrustSummaryButton extends StatelessWidget {
  const TrustSummaryButton(
      {super.key,
      required this.userId,
      required this.summary,
      this.role = 'overall',
      this.prefix = 'Trust'});
  final String userId, role, prefix;
  final TrustRoleSummary summary;
  @override
  Widget build(BuildContext context) => TextButton.icon(
      onPressed: () => openTrustDetails(context, userId, role: role),
      icon: TrustIndicator(cohort: summary.application, size: 32),
      label: Text('$prefix: ${summary.application.label}',
          overflow: TextOverflow.ellipsis, maxLines: 2));
}

class LiveTrustPage extends StatefulWidget {
  const LiveTrustPage({super.key, required this.userId, this.role = 'overall'});
  final String userId, role;
  @override
  State<LiveTrustPage> createState() => _LiveTrustPageState();
}

class _LiveTrustPageState extends State<LiveTrustPage> {
  TrustProfile? profile;
  Object? error;
  bool loading = true, bound = false;
  String? account;
  int generation = 0;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!bound) {
      account = context.read<LiveRentHubController>().profile?.id;
      bound = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _load();
      });
    }
  }

  Future<void> _load() async {
    final controller = context.read<LiveRentHubController>(),
        request = ++generation;
    if (account == null || controller.profile?.id != account) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = await controller.loadTrustProfile(widget.userId);
      if (mounted &&
          request == generation &&
          controller.profile?.id == account) {
        setState(() => profile = result);
      }
    } catch (failure) {
      if (mounted && request == generation) setState(() => error = failure);
    } finally {
      if (mounted && request == generation) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final allowed = account != null &&
        context.watch<LiveRentHubController>().profile?.id == account;
    return Scaffold(
        appBar: AppBar(title: const Text('Trust score'), actions: [
          IconButton(
              tooltip: 'Refresh trust score',
              onPressed: allowed && !loading ? _load : null,
              icon: const Icon(Icons.refresh))
        ]),
        body: !allowed
            ? const Center(
                child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                        'Your session changed. Return to the app and sign in again.')))
            : Center(
                child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 800),
                    child:
                        ListView(padding: const EdgeInsets.all(20), children: [
                      if (loading) const LinearProgressIndicator(),
                      if (error != null)
                        Card(
                            child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(children: [
                                  Text(friendlyError(error!)),
                                  TextButton(
                                      onPressed: _load,
                                      child: const Text('Try again'))
                                ]))),
                      if (profile != null) ...[
                        if (widget.role == 'overall')
                          Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                    child: TrustActivityCard(
                                        title: 'Owner trust score',
                                        cohort: profile!.owner.application)),
                                Expanded(
                                    child: TrustActivityCard(
                                        title: 'Renter trust score',
                                        cohort: profile!.renter.application)),
                              ])
                        else
                          TrustActivityCard(
                              title: widget.role == 'owner'
                                  ? 'Owner trust score'
                                  : 'Renter trust score',
                              cohort:
                                  profile!.forRole(widget.role).application),
                      ],
                      const SizedBox(height: 16),
                      SubjectReviewsSection(
                          userId: widget.userId, role: widget.role),
                    ]))));
  }
}

class TrustActivityCard extends StatelessWidget {
  const TrustActivityCard(
      {super.key,
      required this.title,
      required this.cohort,
      this.demo = false});
  final String title;
  final TrustCohort cohort;
  final bool demo;
  @override
  Widget build(BuildContext context) => Card(
      child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            Text(title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            Center(child: TrustIndicator(cohort: cohort)),
            if (cohort.status == 'unavailable')
              const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text('Score unavailable')),
          ])));
}

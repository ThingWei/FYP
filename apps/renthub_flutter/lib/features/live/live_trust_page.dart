import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/trust/trust_profile.dart';
import '../../core/network/user_facing_error.dart';
import 'live_renthub_controller.dart';

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
      icon: const Icon(Icons.verified_user_outlined, size: 20),
      label: Text('$prefix: ${summary.marketplace.label}',
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
    final role = profile?.forRole(widget.role) ?? const TrustRoleSummary();
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
            : loading && profile == null
                ? const Center(child: CircularProgressIndicator())
                : Center(
                    child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 800),
                        child: ListView(
                            padding: const EdgeInsets.all(20),
                            children: [
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
                                TrustActivityCard(
                                    title: widget.role == 'owner'
                                        ? 'Owner rental history'
                                        : widget.role == 'renter'
                                            ? 'Renter rental history'
                                            : 'Rental history',
                                    cohort: role.marketplace),
                                const SizedBox(height: 16),
                                const Text('How it works',
                                    style:
                                        TextStyle(fontWeight: FontWeight.w700)),
                                const SizedBox(height: 8),
                                const Text(
                                    'The score uses completed rentals from the last 12 months, published reviews and recorded handover, return or service times. Only disputes with an explicit administrator finding of responsibility affect the score.'),
                                const SizedBox(height: 8),
                                const Text(
                                    'A score needs at least 3 completed rentals with 2 different people. New scores grow gradually as more history becomes available. Identity verification is shown separately.'),
                                if (role.demo.completedRentals > 0) ...[
                                  const SizedBox(height: 24),
                                  TrustActivityCard(
                                      title: 'Demo activity',
                                      cohort: role.demo,
                                      demo: true)
                                ],
                              ],
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
          padding: const EdgeInsets.all(20),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(demo ? Icons.science_outlined : Icons.verified_user_outlined,
                  color: AppColors.primary),
              const SizedBox(width: 12),
              Expanded(
                  child: Text(title,
                      style: Theme.of(context).textTheme.titleLarge))
            ]),
            const SizedBox(height: 16),
            Text(
                demo && cohort.established
                    ? 'Demo score ${cohort.label}'
                    : cohort.label,
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(demo
                ? 'Based on simulated payments or labelled demonstration rentals. This is not genuine marketplace history.'
                : 'Based on recorded, completed rentals with payment evidence.'),
            const SizedBox(height: 20),
            Wrap(spacing: 24, runSpacing: 16, children: [
              _TrustFact('Completed rentals', '${cohort.completedRentals}'),
              _TrustFact('Different people', '${cohort.distinctPartners}'),
              _TrustFact('Published reviews', '${cohort.reviewCount}'),
              if (cohort.averageRating != null)
                _TrustFact('Average review', '${cohort.averageRating} / 5'),
              if (cohort.measuredTimeliness > 0)
                _TrustFact('Recorded on time',
                    '${cohort.timelyRentals} of ${cohort.measuredTimeliness}'),
              _TrustFact('Confirmed issues', '${cohort.confirmedIssues}'),
            ]),
            if (!cohort.established && cohort.status != 'unavailable') ...[
              const SizedBox(height: 16),
              const Text(
                  'Keep completing rentals with different people to build a history. Unproven reports do not reduce your score.')
            ],
          ])));
}

class _TrustFact extends StatelessWidget {
  const _TrustFact(this.label, this.value);
  final String label, value;
  @override
  Widget build(BuildContext context) => SizedBox(
      width: 160,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(value, style: Theme.of(context).textTheme.titleLarge),
        Text(label, style: const TextStyle(color: AppColors.secondaryText))
      ]));
}

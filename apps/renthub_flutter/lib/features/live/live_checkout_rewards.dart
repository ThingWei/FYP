import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/network/user_facing_error.dart';
import '../../shared/models/domain_models.dart';
import '../renter/booking/booking_flow.dart' show formatMoney;
import 'live_loyalty_page.dart';
import 'live_renthub_controller.dart';

class CheckoutRewardsSection extends StatefulWidget {
  const CheckoutRewardsSection(
      {super.key,
      required this.booking,
      required this.enabled,
      required this.onApply});
  final Booking booking;
  final bool enabled;
  final Future<void> Function(String rewardId) onApply;
  @override
  State<CheckoutRewardsSection> createState() => _CheckoutRewardsSectionState();
}

class _CheckoutRewardsSectionState extends State<CheckoutRewardsSection> {
  List<Map<String, dynamic>> rewards = [];
  bool loading = true, busy = false, enabled = true;
  String? error, account;
  int generation = 0;
  @override
  void initState() {
    super.initState();
    account = context.read<LiveRentHubController>().profile?.id;
    load();
  }

  bool current(int request) =>
      mounted &&
      request == generation &&
      context.read<LiveRentHubController>().profile?.id == account;
  Future<void> load() async {
    final request = ++generation;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final data = await context
          .read<LiveRentHubController>()
          .api
          .request('GET', '/rewards/checkout/${widget.booking.id}');
      if (data is! Map || data['items'] is! List) {
        throw const FormatException('Invalid rewards');
      }
      if (current(request)) {
        setState(() {
          rewards = (data['items'] as List)
              .map((r) => Map<String, dynamic>.from(r as Map))
              .where((r) =>
                  r['id'] is String &&
                  r['amount'] is num &&
                  (r['amount'] as num).isFinite &&
                  (r['amount'] as num) > 0)
              .toList();
          enabled = data['enabled'] != false;
        });
      }
    } catch (e) {
      if (current(request)) setState(() => error = friendlyError(e));
    } finally {
      if (current(request)) setState(() => loading = false);
    }
  }

  Future<void> apply(String id) async {
    if (busy || !widget.enabled || !enabled) return;
    final request = ++generation;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.onApply(id);
      if (!current(request)) return;
      await load();
    } catch (e) {
      if (current(request)) {
        setState(() => error = friendlyError(e));
      }
    } finally {
      if (mounted &&
          context.read<LiveRentHubController>().profile?.id == account) {
        setState(() => busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = widget.booking.charges?.rewardDiscount ?? 0;
    final applied = widget.booking.charges != null && selected > 0;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        const Icon(Icons.redeem_outlined),
        const SizedBox(width: 12),
        Expanded(
            child: Text('Loyalty reward',
                style: Theme.of(context).textTheme.titleMedium)),
        if (loading || busy)
          const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2))
      ]),
      const SizedBox(height: 12),
      if (error != null)
        Row(children: [
          Expanded(child: Text(error!)),
          TextButton(onPressed: busy ? null : load, child: const Text('Retry'))
        ]),
      if (!enabled) const Text('Rewards are temporarily paused.'),
      if (!loading && enabled)
        DropdownButtonFormField<String>(
            key: ValueKey(
                '${widget.booking.id}:${widget.booking.charges?.rewardDiscount}:${rewards.map((r) => r['id']).join(',')}'),
            isExpanded: true,
            initialValue: null,
            decoration: InputDecoration(
                labelText: applied
                    ? '${formatMoney(selected)} applied'
                    : 'Choose a reward'),
            items: [
              const DropdownMenuItem(value: '', child: Text('No reward')),
              for (final r in rewards)
                DropdownMenuItem(
                    value: r['id'] as String,
                    child: Text(
                        '${formatMoney((r['amount'] as num).toDouble())} · ${r['code'] ?? 'Reward'}',
                        overflow: TextOverflow.ellipsis))
            ],
            onChanged: !widget.enabled || busy
                ? null
                : (id) {
                    if (id != null) apply(id);
                  }),
      if (!loading && rewards.isEmpty && !applied && error == null)
        const Text('No rewards available.'),
      Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
              onPressed: !widget.enabled || busy
                  ? null
                  : () async {
                      await Navigator.push<void>(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const LiveLoyaltyPage()));
                      if (mounted) await load();
                    },
              child: const Text('View points & rewards'))),
    ]);
  }
}

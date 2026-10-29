import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/network/user_facing_error.dart';
import 'admin_record_models.dart';
import 'live_renthub_controller.dart';

class AdminSystemStatus extends StatefulWidget {
  const AdminSystemStatus({super.key});
  @override
  State<AdminSystemStatus> createState() => _AdminSystemStatusState();
}

class _AdminSystemStatusState extends State<AdminSystemStatus> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<LiveRentHubController>().refreshAdminHealth();
    });
  }

  Future<void> _run() async {
    final accepted = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
                title: const Text('Run scheduled tasks?'),
                content: const Text(
                    'This checks due tasks and may expire unpaid booking requests or update rental statuses under the existing rules. It does not collect a real payment.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Run tasks'))
                ]));
    if (accepted != true || !mounted) return;
    final controller = context.read<LiveRentHubController>();
    try {
      await controller.runLifecycleAutomation();
      await controller.loadAdminOverview();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Scheduled tasks have finished.')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyError(error))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<LiveRentHubController>(),
        health = context.watch<LiveRentHubController>().technologyHealth;
    final components =
        health['components'] is Map ? health['components'] as Map : const {};
    final counts = health['operationalCounts'] is Map
        ? health['operationalCounts'] as Map
        : const {};
    final statuses = ['database', 'storage', 'ai', 'blockchain', 'lifecycle']
        .map((key) => components[key] is Map ? components[key]['status'] : null)
        .toList();
    final status = statuses.every((v) => v == 'up' || v == 'healthy')
        ? 'All checked services are available'
        : statuses.any((v) => ['down', 'degraded', 'failed'].contains(v))
            ? 'Some services need attention'
            : statuses.any((v) => v == 'disabled')
                ? 'Some optional services are switched off'
                : 'Status has not been checked';
    const services = {
      'database': ('Data storage', Icons.storage_outlined),
      'storage': ('Photos and documents', Icons.photo_library_outlined),
      'ai': ('AI assistance', Icons.auto_awesome_outlined),
      'blockchain': ('Rental records', Icons.verified_outlined),
      'lifecycle': ('Scheduled tasks', Icons.schedule_outlined)
    };
    return Card(
        child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                      spacing: 16,
                      runSpacing: 12,
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('System status',
                                  style:
                                      Theme.of(context).textTheme.titleLarge),
                              Text(status),
                              Text(
                                  'Last checked: ${adminDate(health['checkedAt'])}',
                                  style: const TextStyle(
                                      color: AppColors.secondaryText))
                            ]),
                        OutlinedButton.icon(
                            onPressed: c.adminHealthLoading
                                ? null
                                : c.refreshAdminHealth,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Refresh status')),
                      ]),
                  if (c.adminHealthLoading)
                    const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: LinearProgressIndicator()),
                  if (c.adminHealthError != null)
                    const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                            'Could not refresh status. The last available check is shown. Try again.')),
                  const SizedBox(height: 16),
                  LayoutBuilder(builder: (context, size) {
                    final columns = (size.maxWidth / 260).floor().clamp(1, 4),
                        width = (size.maxWidth - (columns - 1) * 12) / columns;
                    return Wrap(spacing: 12, runSpacing: 12, children: [
                      for (final service in services.entries)
                        SizedBox(
                            width: width,
                            child: Builder(builder: (context) {
                              final detail = components[service.key] is Map
                                  ? components[service.key] as Map
                                  : const {};
                              final state = '${detail['status'] ?? 'unknown'}';
                              final label = switch (state) {
                                'up' || 'healthy' => 'Available',
                                'configured' => 'Configured',
                                'disabled' => 'Switched off',
                                'development' => 'Demonstration',
                                'down' ||
                                'degraded' ||
                                'failed' =>
                                  'Needs attention',
                                _ => 'Not checked'
                              };
                              final color = label == 'Available'
                                  ? AppColors.success
                                  : label == 'Needs attention'
                                      ? AppColors.warning
                                      : AppColors.secondaryText;
                              final note = label == 'Switched off'
                                  ? 'This feature is currently turned off.'
                                  : label == 'Needs attention'
                                      ? 'This feature may be limited. Contact the system maintainer if it continues.'
                                      : label == 'Not checked'
                                          ? 'A current check is not available.'
                                          : service.key == 'authentication'
                                              ? 'Sign-in is configured. This check does not sign in a user.'
                                              : service.key == 'blockchain'
                                                  ? 'Supporting rental records use a demonstration network.'
                                                  : service.key == 'ai'
                                                      ? 'Automated assistance supports human review.'
                                                      : service.key ==
                                                              'lifecycle'
                                                          ? 'Due tasks run using the existing booking and rental rules.'
                                                          : 'The latest service check is shown.';
                              return Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                      border:
                                          Border.all(color: AppColors.border),
                                      borderRadius: BorderRadius.circular(12)),
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Icon(service.value.$2,
                                            color: AppColors.primary),
                                        const SizedBox(height: 8),
                                        Text(service.value.$1,
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleMedium),
                                        const SizedBox(height: 6),
                                        Row(children: [
                                          Icon(
                                              label == 'Available'
                                                  ? Icons.check_circle_outline
                                                  : label == 'Needs attention'
                                                      ? Icons.info_outline
                                                      : Icons.circle_outlined,
                                              size: 18,
                                              color: color),
                                          const SizedBox(width: 6),
                                          Expanded(
                                              child: Text(label,
                                                  style: TextStyle(
                                                      color: color,
                                                      fontWeight:
                                                          FontWeight.w600)))
                                        ]),
                                        const SizedBox(height: 8),
                                        Text(note)
                                      ]));
                            }))
                    ]);
                  }),
                  const SizedBox(height: 16),
                  Wrap(spacing: 16, runSpacing: 8, children: [
                    for (final entry in const {
                      'expiredBookings': 'Expired requests',
                      'overdueRentals': 'Overdue rentals',
                      'pendingUnpaidBookings': 'Requests awaiting payment'
                    }.entries)
                      Text(
                          '${entry.value}: ${counts[entry.key] is num ? counts[entry.key] : 'Not available'}')
                  ]),
                  const Divider(height: 32),
                  Wrap(
                      spacing: 16,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        const Text('Run due tasks manually only when needed.'),
                        TextButton.icon(
                            onPressed: c.loading ? null : _run,
                            icon: const Icon(Icons.play_arrow),
                            label: const Text('Run scheduled tasks')),
                      ]),
                ])));
  }
}

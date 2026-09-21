import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../modules/user/controllers/auth_controller.dart';
import '../../modules/user/views/login_screen.dart';
import '../../shared/models/domain_models.dart';
import '../../shared/widgets/account_components.dart';
import '../../shared/widgets/renthub_components.dart';
import '../renter/booking/booking_flow.dart' show formatMoney;
import 'live_renthub_controller.dart';

class LiveAdminApp extends StatelessWidget {
  const LiveAdminApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'RentHub Admin',
        theme: AppTheme.light,
        home: Consumer<AuthController>(
          builder: (context, auth, _) => auth.authenticated
              ? const LiveAdminShell()
              : const LoginScreen(
                  administrator: true,
                  initialEmail: 'admin@renthub.my',
                ),
        ),
      );
}

class LiveAdminShell extends StatefulWidget {
  const LiveAdminShell({super.key});

  @override
  State<LiveAdminShell> createState() => _LiveAdminShellState();
}

class _LiveAdminShellState extends State<LiveAdminShell> {
  int selected = 0;

  static const destinations = [
    ('Dashboard', Icons.dashboard_outlined),
    ('Verification', Icons.verified_user_outlined),
    ('Users', Icons.people_outline),
    ('Listings', Icons.inventory_2_outlined),
    ('Bookings & Transactions', Icons.receipt_long_outlined),
    ('Disputes & Claims', Icons.gavel_outlined),
    ('Reports', Icons.report_outlined),
    ('Reviews', Icons.rate_review_outlined),
    ('Platform Settings', Icons.settings_outlined),
    ('Audit Logs', Icons.history),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      await context.read<LiveRentHubController>().loadAdmin();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<LiveRentHubController>();
    return LayoutBuilder(
      builder: (context, constraints) {
        final persistent = constraints.maxWidth >= 1024;
        final navigation = _AdminNavigation(
          selected: selected,
          onSelected: (value) {
            setState(() => selected = value);
            if (!persistent) Navigator.pop(context);
          },
        );
        return Scaffold(
          drawer:
              persistent ? null : Drawer(child: SafeArea(child: navigation)),
          appBar: AppBar(
            automaticallyImplyLeading: !persistent,
            title: Text(destinations[selected].$1),
            actions: [
              IconButton(
                tooltip: 'Refresh live data',
                onPressed: controller.loading ? null : _load,
                icon: const Icon(Icons.refresh),
              ),
              IconButton(
                tooltip: 'Log out',
                onPressed: () => context.read<AuthController>().logout(),
                icon: const Icon(Icons.logout),
              ),
              const SizedBox(width: 12),
            ],
          ),
          body: Row(
            children: [
              if (persistent)
                SizedBox(
                  width: constraints.maxWidth >= 1280 ? 260 : 224,
                  child: navigation,
                ),
              Expanded(
                child: controller.loading && controller.profile == null
                    ? const Center(child: CircularProgressIndicator())
                    : controller.error != null && controller.profile == null
                        ? RentHubFeedbackState(
                            kind: FeedbackKind.error,
                            title: 'Admin API unavailable',
                            message: controller.error!,
                            actionLabel: 'Try Again',
                            onAction: _load,
                          )
                        : _page(selected),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _page(int index) => switch (index) {
        0 => const _AdminDashboard(),
        1 => const _AdminVerification(),
        2 => const _AdminUsers(),
        3 => const _AdminListings(),
        4 => const _AdminBookingsTransactions(),
        5 => const _AdminDisputesClaims(),
        6 => const _AdminMessageReports(),
        7 => const _AdminReviews(),
        8 => const _AdminPlatformSettings(),
        9 => const _AdminAuditLogs(),
        _ => _DeferredAdminModule(title: destinations[index].$1),
      };
}

class _AdminNavigation extends StatelessWidget {
  const _AdminNavigation({required this.selected, required this.onSelected});

  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: AppColors.background,
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            const Padding(
              padding: EdgeInsets.all(12),
              child: RentHubLogo(),
            ),
            for (var index = 0;
                index < _LiveAdminShellState.destinations.length;
                index++)
              ListTile(
                selected: selected == index,
                selectedTileColor: AppColors.primaryLight,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                leading: Icon(
                  _LiveAdminShellState.destinations[index].$2,
                ),
                title: Text(_LiveAdminShellState.destinations[index].$1),
                onTap: () => onSelected(index),
              ),
          ],
        ),
      );
}

class _AdminDashboard extends StatelessWidget {
  const _AdminDashboard();

  @override
  Widget build(BuildContext context) {
    final data = context.watch<LiveRentHubController>();
    final pendingListings = data.adminListings
        .where((item) => item.status == 'pending_review')
        .length;
    final openReports =
        data.messageReports.where((item) => item['status'] == 'open').length;
    final flaggedReviews =
        data.adminReviews.where((review) => review.flagged).length;
    return RefreshIndicator(
      onRefresh: data.loadAdmin,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text('Live platform overview',
              style: Theme.of(context).textTheme.headlineSmall),
          const Text(
            'These counts are loaded from MongoDB.',
            style: TextStyle(color: AppColors.secondaryText),
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              _AdminMetric(
                  'Users', '${data.users.length}', Icons.people_outline),
              _AdminMetric(
                'Pending listings',
                '$pendingListings',
                Icons.inventory_2_outlined,
              ),
              _AdminMetric(
                'Bookings',
                '${data.bookings.length}',
                Icons.receipt_long_outlined,
              ),
              _AdminMetric(
                'Open message reports',
                '$openReports',
                Icons.report_outlined,
              ),
              _AdminMetric(
                'Flagged reviews',
                '$flaggedReviews',
                Icons.rate_review_outlined,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AdminMetric extends StatelessWidget {
  const _AdminMetric(this.label, this.value, this.icon);

  final String label, value;
  final IconData icon;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 220,
        height: 120,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: AppColors.primary),
                const Spacer(),
                Text(value, style: Theme.of(context).textTheme.headlineSmall),
                Text(label),
              ],
            ),
          ),
        ),
      );
}

class _AdminVerification extends StatelessWidget {
  const _AdminVerification();

  Future<void> _review(
    BuildContext context,
    Map<String, dynamic> user,
    String status,
  ) async {
    final reason = TextEditingController();
    var tier = 'basic';
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
            status == 'approved'
                ? 'Approve identity?'
                : status == 'rejected'
                    ? 'Reject identity?'
                    : 'Request resubmission?',
          ),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(user['displayName'] as String),
                const SizedBox(height: 12),
                if (status == 'approved')
                  DropdownButtonFormField<String>(
                    initialValue: tier,
                    decoration:
                        const InputDecoration(labelText: 'Verification tier'),
                    items: const [
                      DropdownMenuItem(value: 'basic', child: Text('Basic')),
                      DropdownMenuItem(
                        value: 'enhanced',
                        child: Text('Enhanced'),
                      ),
                    ],
                    onChanged: (value) =>
                        setDialogState(() => tier = value ?? 'basic'),
                  )
                else
                  TextField(
                    controller: reason,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Required reason',
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Confirm'),
            ),
          ],
        ),
      ),
    );
    if (accepted != true || !context.mounted) {
      reason.dispose();
      return;
    }
    if (status != 'approved' && reason.text.trim().length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a review reason.')),
      );
      reason.dispose();
      return;
    }
    try {
      await context.read<LiveRentHubController>().reviewIdentityVerification(
            user['_id'].toString(),
            status,
            tier: tier,
            reason: reason.text,
          );
    } catch (exception) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(exception.toString())));
      }
    }
    reason.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final users = context.watch<LiveRentHubController>().users;
    final pending = users.where((user) {
      final verification = user['verification'] as Map<String, dynamic>?;
      return verification?['status'] == 'pending';
    }).toList();
    if (pending.isEmpty) {
      return const RentHubFeedbackState(
        kind: FeedbackKind.empty,
        title: 'Verification queue is clear',
        message: 'New identity submissions will appear here.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(24),
      itemCount: pending.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final user = pending[index];
        final verification =
            user['verification'] as Map<String, dynamic>? ?? const {};
        final references =
            (verification['documentRefs'] as List?)?.cast<String>() ?? const [];
        final ocr =
            verification['ocrResult'] as Map<String, dynamic>? ?? const {};
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const CircleAvatar(
                      child: Icon(Icons.person_search_outlined),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user['displayName'] as String,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          Text(
                            '${verification['documentType'] ?? 'Document'} | ${references.length} placeholder image(s)',
                          ),
                        ],
                      ),
                    ),
                    const StatusBadge('pending'),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'OCR: ${ocr['status'] ?? 'pending'} | Name match: ${ocr['nameMatch'] ?? 'pending'}',
                ),
                const SizedBox(height: 4),
                for (final reference in references)
                  Text(reference, style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton(
                      onPressed: () =>
                          _review(context, user, 'resubmission_required'),
                      child: const Text('Request Resubmission'),
                    ),
                    OutlinedButton(
                      onPressed: () => _review(context, user, 'rejected'),
                      child: const Text('Reject'),
                    ),
                    FilledButton(
                      onPressed: () => _review(context, user, 'approved'),
                      child: const Text('Approve'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _AdminUsers extends StatelessWidget {
  const _AdminUsers();

  Future<void> _restrict(
    BuildContext context,
    Map<String, dynamic> user,
  ) async {
    final reason = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Suspend ${user['displayName']}?'),
        content: TextField(
          controller: reason,
          decoration: const InputDecoration(labelText: 'Required reason'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Suspend'),
          ),
        ],
      ),
    );
    if (accepted == true && reason.text.trim().length >= 3 && context.mounted) {
      try {
        await context.read<LiveRentHubController>().changeAccountStatus(
              user['_id'] as String,
              'suspended',
              reason.text.trim(),
            );
      } catch (exception) {
        if (context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(exception.toString())));
        }
      }
    }
    reason.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = context.watch<LiveRentHubController>();
    return ListView.separated(
      padding: const EdgeInsets.all(24),
      itemCount: data.users.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final user = data.users[index];
        final status = user['accountStatus'] as String? ?? 'active';
        return Card(
          child: ListTile(
            leading: CircleAvatar(
              child: Text((user['displayName'] as String).substring(0, 1)),
            ),
            title: Text(user['displayName'] as String),
            subtitle: Text(
              '${(user['roles'] as List).join(', ')} · ${user['email']}',
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                StatusBadge(status),
                const SizedBox(width: 8),
                if (status == 'active' &&
                    !(user['roles'] as List).contains('admin'))
                  OutlinedButton(
                    onPressed: () => _restrict(context, user),
                    child: const Text('Suspend'),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _AdminListings extends StatelessWidget {
  const _AdminListings();

  Future<void> _moderate(
    BuildContext context,
    Listing listing,
    String status,
  ) async {
    final reason = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${status == 'active' ? 'Approve' : 'Reject'} listing?'),
        content: status == 'rejected'
            ? TextField(
                controller: reason,
                decoration:
                    const InputDecoration(labelText: 'Rejection reason'),
              )
            : Text(listing.title),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Back'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(status == 'active' ? 'Approve' : 'Reject'),
          ),
        ],
      ),
    );
    if (accepted == true && context.mounted) {
      if (status == 'rejected' && reason.text.trim().length < 3) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('A rejection reason is required.')),
        );
      } else {
        try {
          await context.read<LiveRentHubController>().moderateListing(
                listing.id,
                status,
                reason: reason.text,
              );
        } catch (exception) {
          if (context.mounted) {
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text(exception.toString())));
          }
        }
      }
    }
    reason.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = context.watch<LiveRentHubController>();
    return ListView.separated(
      padding: const EdgeInsets.all(24),
      itemCount: data.adminListings.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final listing = data.adminListings[index];
        return Card(
          child: ListTile(
            title: Text(listing.title),
            subtitle: Text(
              '${listing.ownerName} · ${formatMoney(listing.dailyPrice)} · ${listing.listingTypeLabel}',
            ),
            trailing: listing.status == 'pending_review'
                ? Wrap(
                    spacing: 8,
                    children: [
                      OutlinedButton(
                        onPressed: () =>
                            _moderate(context, listing, 'rejected'),
                        child: const Text('Reject'),
                      ),
                      FilledButton(
                        onPressed: () => _moderate(context, listing, 'active'),
                        child: const Text('Approve'),
                      ),
                    ],
                  )
                : StatusBadge(listing.status.replaceAll('_', ' ')),
          ),
        );
      },
    );
  }
}

extension on Listing {
  String get listingTypeLabel => isService ? 'Service' : 'Physical item';
}

class _AdminBookingsTransactions extends StatelessWidget {
  const _AdminBookingsTransactions();

  Future<void> _refund(BuildContext context, Transaction transaction) async {
    final amount =
        TextEditingController(text: transaction.amount.toStringAsFixed(2));
    final reason = TextEditingController(text: 'Administrator-approved refund');
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Issue simulated refund?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: amount,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Amount (RM)'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reason,
              decoration: const InputDecoration(labelText: 'Reason'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Refund'),
          ),
        ],
      ),
    );
    final parsed = double.tryParse(amount.text);
    if (accepted == true && parsed != null && parsed > 0 && context.mounted) {
      try {
        await context.read<LiveRentHubController>().refundTransaction(
              transaction.id,
              parsed,
              reason.text,
            );
      } catch (exception) {
        if (context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(exception.toString())));
        }
      }
    }
    amount.dispose();
    reason.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = context.watch<LiveRentHubController>();
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('Bookings', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        for (final booking in data.bookings)
          Card(
            child: ListTile(
              title: Text(booking.listingTitle),
              subtitle: Text(
                '${booking.id} · ${formatMoney(booking.total)} · Payment ${booking.paymentStatus}',
              ),
              trailing: StatusBadge(booking.status),
            ),
          ),
        const SizedBox(height: 24),
        Text('Transactions', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        for (final transaction in data.transactions)
          Card(
            child: ListTile(
              title: Text(transaction.type.replaceAll('_', ' ')),
              subtitle: Text('${transaction.id} · ${transaction.bookingId}'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(formatMoney(transaction.amount)),
                  if (transaction.type == 'capture' &&
                      transaction.status == 'succeeded') ...[
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: () => _refund(context, transaction),
                      child: const Text('Refund'),
                    ),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _AdminDisputesClaims extends StatelessWidget {
  const _AdminDisputesClaims();

  void _showError(BuildContext context, Object exception) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(exception.toString())));
  }

  Future<void> _viewCase(BuildContext context, Dispute dispute) async {
    try {
      final record = await context
          .read<LiveRentHubController>()
          .loadDisputeCase(dispute.id);
      if (!context.mounted) return;
      final caseContext =
          record['caseContext'] as Map<String, dynamic>? ?? const {};
      final agreement =
          caseContext['agreement'] as Map<String, dynamic>? ?? const {};
      final inspection =
          caseContext['inspection'] as Map<String, dynamic>? ?? const {};
      final messages = caseContext['conversation'] as List? ?? const [];
      final pricing = agreement['pricing'] as Map<String, dynamic>? ?? const {};
      final handover =
          inspection['handover'] as Map<String, dynamic>? ?? const {};
      final returned =
          inspection['returnSubmission'] as Map<String, dynamic>? ?? const {};
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Case file ${dispute.id}'),
          content: SizedBox(
            width: 680,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Agreement',
                      style: Theme.of(context).textTheme.titleMedium),
                  Text(dispute.listingTitle),
                  Text(
                    '${dispute.listingType == 'physical' ? agreement['fulfilmentMethod'] : agreement['serviceVenue']} • ${formatMoney((pricing['total'] as num?)?.toDouble() ?? 0)}',
                  ),
                  const Divider(height: 28),
                  Text('Evidence & inspection',
                      style: Theme.of(context).textTheme.titleMedium),
                  Text('Dispute attachments: ${dispute.evidence.length}'),
                  if (dispute.listingType == 'physical') ...[
                    Text(
                        'Handover condition: ${handover['condition'] ?? 'Not recorded'}'),
                    Text(
                        'Return condition: ${returned['condition'] ?? 'Not recorded'}'),
                    Text(
                      'Inspection attachments: ${(handover['evidence'] as List?)?.length ?? 0} handover, ${(returned['evidence'] as List?)?.length ?? 0} return',
                    ),
                  ] else
                    Text(
                      'Service delivery: ${inspection['serviceDeliveredAt'] ?? 'Not recorded'}',
                    ),
                  const Divider(height: 28),
                  Text('Conversation history',
                      style: Theme.of(context).textTheme.titleMedium),
                  if (messages.isEmpty)
                    const Text('No booking conversation messages.')
                  else
                    for (final raw in messages)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        leading: const Icon(Icons.chat_bubble_outline),
                        title: Text(
                          (raw as Map<String, dynamic>)['senderId'] as String,
                        ),
                        subtitle: Text(raw['text'] as String),
                      ),
                  if (dispute.responses.isNotEmpty) ...[
                    const Divider(height: 28),
                    Text('Case responses',
                        style: Theme.of(context).textTheme.titleMedium),
                    for (final item in dispute.responses)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: Text(item.role),
                        subtitle: Text(item.text),
                        trailing: Text('${item.evidence.length} files'),
                      ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Done'),
            ),
          ],
        ),
      );
    } catch (exception) {
      if (context.mounted) _showError(context, exception);
    }
  }

  Future<void> _updateStatus(
    BuildContext context,
    Dispute dispute,
    String status,
  ) async {
    final note = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          status == 'escalated'
              ? 'Escalate dispute?'
              : 'Request more evidence?',
        ),
        content: TextField(
          controller: note,
          minLines: 3,
          maxLines: 5,
          decoration: const InputDecoration(labelText: 'Required note'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (accepted == true && note.text.trim().length >= 5 && context.mounted) {
      try {
        await context
            .read<LiveRentHubController>()
            .updateDisputeStatus(dispute, status, note.text);
      } catch (exception) {
        if (context.mounted) _showError(context, exception);
      }
    } else if (accepted == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('A note of at least 5 characters is required.')),
      );
    }
    note.dispose();
  }

  Future<void> _resolve(BuildContext context, Dispute dispute) async {
    var outcome = 'release_to_renter';
    final renterAmount = TextEditingController();
    final ownerAmount = TextEditingController();
    final notes = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Record dispute decision'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: outcome,
                    decoration: const InputDecoration(labelText: 'Outcome'),
                    items: const [
                      DropdownMenuItem(
                        value: 'release_to_renter',
                        child: Text('Release to renter'),
                      ),
                      DropdownMenuItem(value: 'split', child: Text('Split')),
                      DropdownMenuItem(
                        value: 'release_to_owner',
                        child: Text('Release to Owner'),
                      ),
                      DropdownMenuItem(
                        value: 'dismissed',
                        child: Text('Dismiss dispute'),
                      ),
                    ],
                    onChanged: (value) => setState(() => outcome = value!),
                  ),
                  if (outcome == 'split') ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: renterAmount,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                          labelText: 'Renter amount (RM)'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: ownerAmount,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration:
                          const InputDecoration(labelText: 'Owner amount (RM)'),
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextField(
                    controller: notes,
                    minLines: 3,
                    maxLines: 5,
                    decoration:
                        const InputDecoration(labelText: 'Decision notes'),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Amounts are simulated allocations only. This action does not move real money.',
                    style: TextStyle(color: AppColors.secondaryText),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Record Decision'),
            ),
          ],
        ),
      ),
    );
    final renter = double.tryParse(renterAmount.text);
    final owner = double.tryParse(ownerAmount.text);
    final splitValid = outcome != 'split' ||
        (renter != null && renter > 0 && owner != null && owner > 0);
    if (accepted == true &&
        notes.text.trim().length >= 10 &&
        splitValid &&
        context.mounted) {
      try {
        await context.read<LiveRentHubController>().resolveDispute(
              dispute: dispute,
              outcome: outcome,
              notes: notes.text,
              renterAmount: outcome == 'split' ? renter : null,
              ownerAmount: outcome == 'split' ? owner : null,
            );
      } catch (exception) {
        if (context.mounted) _showError(context, exception);
      }
    } else if (accepted == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter decision notes and valid split amounts.'),
        ),
      );
    }
    renterAmount.dispose();
    ownerAmount.dispose();
    notes.dispose();
  }

  Future<void> _decideClaim(
    BuildContext context,
    InsuranceClaim claim,
    String status,
  ) async {
    final reason = TextEditingController();
    final amount = TextEditingController(
      text:
          status == 'approved' ? claim.amountRequested.toStringAsFixed(2) : '',
    );
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${status == 'approved' ? 'Approve' : 'Reject'} claim?'),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (status == 'approved')
                TextField(
                  controller: amount,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration:
                      const InputDecoration(labelText: 'Approved amount (RM)'),
                ),
              if (status == 'approved') const SizedBox(height: 12),
              TextField(
                controller: reason,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(labelText: 'Decision reason'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    final parsed = double.tryParse(amount.text);
    if (accepted == true &&
        reason.text.trim().length >= 5 &&
        (status == 'rejected' || parsed != null) &&
        context.mounted) {
      try {
        await context.read<LiveRentHubController>().decideClaim(
              claim: claim,
              status: status,
              reason: reason.text,
              approvedAmount: status == 'approved' ? parsed : null,
            );
      } catch (exception) {
        if (context.mounted) _showError(context, exception);
      }
    }
    reason.dispose();
    amount.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = context.watch<LiveRentHubController>();
    return RefreshIndicator(
      onRefresh: data.loadAdmin,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text('Dispute queue', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          if (data.adminDisputes.isEmpty)
            const Card(
              child: ListTile(
                title: Text('No disputes'),
                subtitle: Text('Participant disputes will appear here.'),
              ),
            ),
          for (final dispute in data.adminDisputes)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            dispute.reason,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        StatusBadge(dispute.status.replaceAll('_', ' ')),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text('${dispute.listingTitle} • ${dispute.id}'),
                    Text(
                      '${dispute.raisedByName} vs ${dispute.respondentName}',
                      style: const TextStyle(color: AppColors.secondaryText),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton(
                          onPressed: () => _viewCase(context, dispute),
                          child: const Text('View Case File'),
                        ),
                        if (!dispute.closed) ...[
                          OutlinedButton(
                            onPressed: () => _updateStatus(
                              context,
                              dispute,
                              'more_evidence_required',
                            ),
                            child: const Text('Request Evidence'),
                          ),
                          OutlinedButton(
                            onPressed: () => _updateStatus(
                              context,
                              dispute,
                              'escalated',
                            ),
                            child: const Text('Escalate'),
                          ),
                          FilledButton(
                            onPressed: () => _resolve(context, dispute),
                            child: const Text('Resolve'),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 28),
          Text('Damage-waiver claims',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          if (data.adminClaims.isEmpty)
            const Card(
              child: ListTile(
                title: Text('No claims'),
                subtitle: Text('Physical-item claims will appear here.'),
              ),
            ),
          for (final claim in data.adminClaims)
            Card(
              child: ListTile(
                title: Text(claim.listingTitle),
                subtitle: Text(
                  '${claim.id} • Requested ${formatMoney(claim.amountRequested)}\n${claim.description}',
                ),
                isThreeLine: true,
                trailing: claim.status == 'pending'
                    ? Wrap(
                        spacing: 8,
                        children: [
                          OutlinedButton(
                            onPressed: () =>
                                _decideClaim(context, claim, 'rejected'),
                            child: const Text('Reject'),
                          ),
                          FilledButton(
                            onPressed: () =>
                                _decideClaim(context, claim, 'approved'),
                            child: const Text('Approve'),
                          ),
                        ],
                      )
                    : StatusBadge(claim.status),
              ),
            ),
        ],
      ),
    );
  }
}

class _AdminMessageReports extends StatelessWidget {
  const _AdminMessageReports();

  Future<void> _resolve(
    BuildContext context,
    Map<String, dynamic> report,
    String status,
  ) async {
    try {
      await context.read<LiveRentHubController>().resolveMessageReport(
            (report['publicId'] ?? report['id']) as String,
            status,
            status == 'resolved'
                ? 'Reviewed and action recorded by the administrator.'
                : 'Report reviewed and dismissed by the administrator.',
          );
    } catch (exception) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(exception.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final reports = context.watch<LiveRentHubController>().messageReports;
    if (reports.isEmpty) {
      return const RentHubFeedbackState(
        kind: FeedbackKind.empty,
        title: 'No message reports',
        message: 'Reported conversation content will appear here.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(24),
      itemCount: reports.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final report = reports[index];
        final status = report['status'] as String;
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text('Reason: ${report['reason']}'),
                    ),
                    StatusBadge(status),
                  ],
                ),
                const SizedBox(height: 8),
                Text('“${report['messageText']}”'),
                Text(
                  report['details'] as String? ?? '',
                  style: const TextStyle(color: AppColors.secondaryText),
                ),
                if (status == 'open') ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: [
                      OutlinedButton(
                        onPressed: () => _resolve(context, report, 'dismissed'),
                        child: const Text('Dismiss'),
                      ),
                      FilledButton(
                        onPressed: () => _resolve(context, report, 'resolved'),
                        child: const Text('Resolve'),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _AdminReviews extends StatelessWidget {
  const _AdminReviews();

  Future<void> _moderate(
    BuildContext context,
    Review review,
    String status,
  ) async {
    final reason = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(status == 'hidden' ? 'Hide review?' : 'Restore review?'),
        content: status == 'hidden'
            ? TextField(
                controller: reason,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Moderation reason',
                ),
              )
            : Text(review.text),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(status == 'hidden' ? 'Hide' : 'Restore'),
          ),
        ],
      ),
    );
    if (accepted != true || !context.mounted) {
      reason.dispose();
      return;
    }
    if (status == 'hidden' && reason.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('A moderation reason is required.')),
      );
      reason.dispose();
      return;
    }
    try {
      await context.read<LiveRentHubController>().moderateReview(
            review.id,
            status,
            reason: reason.text,
          );
    } catch (exception) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(exception.toString())));
      }
    }
    reason.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reviews = context.watch<LiveRentHubController>().adminReviews;
    if (reviews.isEmpty) {
      return const RentHubFeedbackState(
        kind: FeedbackKind.empty,
        title: 'No reviews yet',
        message: 'Completed-order reviews and flags will appear here.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(24),
      itemCount: reviews.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final review = reviews[index];
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${review.authorName} reviewed ${review.subjectName}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    if (review.flagged) ...[
                      const StatusBadge('Flagged'),
                      const SizedBox(width: 8),
                    ],
                    StatusBadge(review.status),
                  ],
                ),
                const SizedBox(height: 6),
                Text('${review.rating}/5 • ${review.listingTitle}'),
                Text(review.text),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: review.status == 'hidden'
                      ? OutlinedButton(
                          onPressed: () =>
                              _moderate(context, review, 'published'),
                          child: const Text('Restore Review'),
                        )
                      : FilledButton.tonal(
                          onPressed: () => _moderate(context, review, 'hidden'),
                          child: const Text('Hide Review'),
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _AdminPlatformSettings extends StatefulWidget {
  const _AdminPlatformSettings();

  @override
  State<_AdminPlatformSettings> createState() => _AdminPlatformSettingsState();
}

class _AdminPlatformSettingsState extends State<_AdminPlatformSettings> {
  final formKey = GlobalKey<FormState>();
  final physicalPoints = TextEditingController();
  final servicePoints = TextEditingController();
  final referralPoints = TextEditingController();
  final friendReward = TextEditingController();
  final redemptionOptions = TextEditingController();
  bool enabled = true;
  bool initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final config = context.watch<LiveRentHubController>().loyaltyConfig;
    if (initialized || config.isEmpty) return;
    initialized = true;
    enabled = config['enabled'] as bool? ?? true;
    physicalPoints.text = '${config['physicalCompletionPoints'] ?? 120}';
    servicePoints.text = '${config['serviceCompletionPoints'] ?? 100}';
    referralPoints.text = '${config['referralRewardPoints'] ?? 250}';
    friendReward.text = '${config['refereeDiscountAmount'] ?? 5}';
    redemptionOptions.text =
        (config['redemptionOptions'] as List? ?? const []).map((raw) {
      final option = raw as Map<String, dynamic>;
      return '${option['points']}:${option['discountAmount']}';
    }).join(', ');
  }

  @override
  void dispose() {
    physicalPoints.dispose();
    servicePoints.dispose();
    referralPoints.dispose();
    friendReward.dispose();
    redemptionOptions.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>>? _parseOptions() {
    final options = <Map<String, dynamic>>[];
    for (final token in redemptionOptions.text.split(',')) {
      final parts = token.trim().split(':');
      if (parts.length != 2) return null;
      final points = int.tryParse(parts[0].trim());
      final amount = double.tryParse(parts[1].trim());
      if (points == null || points < 1 || amount == null || amount <= 0) {
        return null;
      }
      options.add({'points': points, 'discountAmount': amount});
    }
    if (options.isEmpty ||
        options.map((item) => item['points']).toSet().length !=
            options.length) {
      return null;
    }
    return options;
  }

  Future<void> _save() async {
    if (!formKey.currentState!.validate()) return;
    final options = _parseOptions();
    if (options == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Use unique reward pairs such as 500:5, 1000:10.'),
        ),
      );
      return;
    }
    try {
      await context.read<LiveRentHubController>().updateLoyaltyConfig({
        'enabled': enabled,
        'physicalCompletionPoints': int.parse(physicalPoints.text),
        'serviceCompletionPoints': int.parse(servicePoints.text),
        'referralRewardPoints': int.parse(referralPoints.text),
        'refereeDiscountAmount': double.parse(friendReward.text),
        'redemptionOptions': options,
      });
      if (mounted) showMockSuccess(context, 'Loyalty rules saved and audited');
    } catch (exception) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(exception.toString())));
      }
    }
  }

  String? _wholeNumber(String? value) {
    final parsed = int.tryParse(value ?? '');
    return parsed == null || parsed < 0 ? 'Enter zero or more' : null;
  }

  @override
  Widget build(BuildContext context) {
    final data = context.watch<LiveRentHubController>();
    if (data.loyaltyConfig.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('Loyalty & referral rules',
            style: Theme.of(context).textTheme.headlineSmall),
        const Text(
          'Changes apply to future completions, referrals and redemptions and are written to the administrator audit log.',
          style: TextStyle(color: AppColors.secondaryText),
        ),
        const SizedBox(height: 16),
        Form(
          key: formKey,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Loyalty programme enabled'),
                    subtitle: const Text(
                      'Pausing prevents future automatic awards and redemptions.',
                    ),
                    value: enabled,
                    onChanged: (value) => setState(() => enabled = value),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 16,
                    runSpacing: 12,
                    children: [
                      _RuleField(
                        controller: physicalPoints,
                        label: 'Physical completion points',
                        validator: _wholeNumber,
                      ),
                      _RuleField(
                        controller: servicePoints,
                        label: 'Service completion points',
                        validator: _wholeNumber,
                      ),
                      _RuleField(
                        controller: referralPoints,
                        label: 'Referrer reward points',
                        validator: _wholeNumber,
                      ),
                      _RuleField(
                        controller: friendReward,
                        label: 'Friend reward (RM)',
                        validator: (value) {
                          final amount = double.tryParse(value ?? '');
                          return amount == null || amount < 0
                              ? 'Enter zero or more'
                              : null;
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: redemptionOptions,
                    decoration: const InputDecoration(
                      labelText: 'Reward options (points:RM)',
                      helperText: 'Example: 500:5, 1000:10',
                    ),
                    validator: (value) => (value?.trim().isEmpty ?? true)
                        ? 'At least one reward is required'
                        : null,
                  ),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(
                      onPressed: data.loading ? null : _save,
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('Save Rules'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text('Referral activity',
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        if (data.adminReferrals.isEmpty)
          const Card(
            child: ListTile(title: Text('No referral applications yet')),
          ),
        for (final referral in data.adminReferrals)
          Card(
            child: ListTile(
              leading: const Icon(Icons.people_outline),
              title:
                  Text('${referral['referrerId']} → ${referral['refereeId']}'),
              subtitle: Text(referral['referralCode'] as String),
              trailing: StatusBadge(referral['status'] as String),
            ),
          ),
        const SizedBox(height: 24),
        Text('Recent points ledger',
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        for (final entry in data.adminRewardLedger.take(20))
          Card(
            child: ListTile(
              title: Text(entry['description'] as String),
              subtitle: Text('${entry['userId']} • ${entry['type']}'),
              trailing: Text(
                '${(entry['points'] as num) > 0 ? '+' : ''}${entry['points']}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
      ],
    );
  }
}

class _RuleField extends StatelessWidget {
  const _RuleField({
    required this.controller,
    required this.label,
    required this.validator,
  });

  final TextEditingController controller;
  final String label;
  final String? Function(String?) validator;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 260,
        child: TextFormField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: label),
          validator: validator,
        ),
      );
}

class _AdminAuditLogs extends StatelessWidget {
  const _AdminAuditLogs();

  @override
  Widget build(BuildContext context) {
    final logs = context.watch<LiveRentHubController>().auditLogs;
    if (logs.isEmpty) {
      return const RentHubFeedbackState(
        kind: FeedbackKind.empty,
        title: 'No audit entries yet',
        message: 'Administrator dispute and claim decisions will appear here.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(24),
      itemCount: logs.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final log = logs[index];
        final metadata = log['metadata'] as Map<String, dynamic>? ?? const {};
        return Card(
          child: ListTile(
            leading: const Icon(Icons.history, color: AppColors.primary),
            title: Text((log['action'] as String).replaceAll('.', ' • ')),
            subtitle: Text(
              '${log['actorId']} → ${log['targetType']} ${log['targetId']}\n${metadata.entries.map((entry) => '${entry.key}: ${entry.value}').join(' • ')}',
            ),
            isThreeLine: true,
            trailing: Text(
              (log['createdAt'] as String? ?? '').replaceFirst('T', '\n'),
              textAlign: TextAlign.right,
              style: const TextStyle(color: AppColors.secondaryText),
            ),
          ),
        );
      },
    );
  }
}

class _DeferredAdminModule extends StatelessWidget {
  const _DeferredAdminModule({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) => RentHubFeedbackState(
        kind: FeedbackKind.empty,
        title: '$title remains in prototype mode',
        message:
            'This module has no Phase 1–5 backend contract yet. Its existing UI remains available in mock mode.',
      );
}

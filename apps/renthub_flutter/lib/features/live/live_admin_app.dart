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
        2 => const _AdminUsers(),
        3 => const _AdminListings(),
        4 => const _AdminBookingsTransactions(),
        6 => const _AdminMessageReports(),
        7 => const _AdminReviews(),
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

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/renthub_categories.dart';
import '../../core/theme/app_theme.dart';
import '../../modules/user/controllers/auth_controller.dart';
import '../../modules/user/repositories/auth_repository.dart';
import '../../modules/user/views/login_screen.dart';
import '../../shared/models/domain_models.dart';
import '../../shared/widgets/account_components.dart';
import '../../shared/widgets/renthub_components.dart';

class AdminApp extends StatelessWidget {
  const AdminApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'RentHub Admin',
        theme: AppTheme.light,
        home: const AdminLogin(),
      );
}

class AdminLogin extends StatelessWidget {
  const AdminLogin({super.key});
  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
        create: (_) =>
            AuthController(MockAuthRepository())..selectRole(UserRole.admin),
        child: Builder(
          builder: (context) => LoginScreen(
            administrator: true,
            initialEmail: 'admin@renthub.my',
            onAuthenticated: () => Navigator.pushReplacement<void, void>(
              context,
              MaterialPageRoute(builder: (_) => const AdminShell()),
            ),
          ),
        ),
      );
}

class AdminShell extends StatefulWidget {
  const AdminShell({super.key});
  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _Destination {
  const _Destination(this.label, this.icon);
  final String label;
  final IconData icon;
}

class _AdminShellState extends State<AdminShell> {
  int selected = 0;
  static const destinations = <_Destination>[
    _Destination('Dashboard', Icons.dashboard_outlined),
    _Destination('Users & KYC', Icons.people_outline),
    _Destination('Listings', Icons.inventory_2_outlined),
    _Destination('Bookings', Icons.calendar_month_outlined),
    _Destination('Disputes', Icons.gavel_outlined),
    _Destination('Transactions', Icons.receipt_long_outlined),
    _Destination('Reports & Analytics', Icons.bar_chart_outlined),
    _Destination('Categories', Icons.category_outlined),
    _Destination('Audit History', Icons.history),
    _Destination('Notifications', Icons.notifications_outlined),
    _Destination('Profile & Settings', Icons.settings_outlined),
  ];

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final persistent = constraints.maxWidth >= 1024;
          final nav = _AdminNavigation(
            destinations: destinations,
            selected: selected,
            onSelected: (value) {
              setState(() => selected = value);
              if (!persistent) Navigator.pop(context);
            },
          );
          return Scaffold(
            drawer: persistent ? null : Drawer(child: SafeArea(child: nav)),
            appBar: AppBar(
              automaticallyImplyLeading: !persistent,
              title: Text(destinations[selected].label),
              actions: [
                IconButton(
                  tooltip: 'Admin notifications',
                  onPressed: () => setState(() => selected = 9),
                  icon: const Badge(child: Icon(Icons.notifications_outlined)),
                ),
                IconButton(
                  tooltip: 'Admin profile',
                  onPressed: () => setState(() => selected = 10),
                  icon: const CircleAvatar(radius: 16, child: Text('NI')),
                ),
                const SizedBox(width: 12),
              ],
            ),
            body: Row(
              children: [
                if (persistent)
                  SizedBox(
                    width: constraints.maxWidth >= 1280 ? 260 : 224,
                    child: nav,
                  ),
                Expanded(
                  child: AdminPage(
                    index: selected,
                    onNavigate: (value) => setState(() => selected = value),
                  ),
                ),
              ],
            ),
          );
        },
      );
}

class _AdminNavigation extends StatelessWidget {
  const _AdminNavigation({
    required this.destinations,
    required this.selected,
    required this.onSelected,
  });
  final List<_Destination> destinations;
  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: AppColors.background,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(8, 8, 8, 20),
              child: RentHubLogo(),
            ),
            for (var i = 0; i < destinations.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Material(
                  color: Colors.transparent,
                  child: ListTile(
                    selected: selected == i,
                    selectedTileColor: AppColors.primaryLight,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    leading: Icon(destinations[i].icon),
                    title: Text(destinations[i].label),
                    onTap: () => onSelected(i),
                  ),
                ),
              ),
          ],
        ),
      );
}

class AdminPage extends StatelessWidget {
  const AdminPage({
    super.key,
    required this.index,
    required this.onNavigate,
  });
  final int index;
  final ValueChanged<int> onNavigate;

  @override
  Widget build(BuildContext context) => switch (index) {
        0 => _Dashboard(onNavigate: onNavigate),
        7 => const _CategoryManagementPage(),
        9 => const _AdminNotificationsPage(),
        10 => const _AdminProfileSettingsPage(),
        _ => _AdminRecordsPage(section: index),
      };
}

class _Dashboard extends StatelessWidget {
  const _Dashboard({required this.onNavigate});
  final ValueChanged<int> onNavigate;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text('Platform overview',
              style: Theme.of(context).textTheme.headlineSmall),
          const Text(
            'Prototype metrics and work requiring administrative action.',
            style: TextStyle(color: AppColors.secondaryText),
          ),
          const SizedBox(height: 20),
          const Wrap(spacing: 16, runSpacing: 16, children: [
            _Metric('Gross bookings', 'RM 184,250', '+12.4%'),
            _Metric('Active users', '12,480', '+6.2%'),
            _Metric('Open disputes', '18', '4 urgent'),
            _Metric('Pending KYC', '42', 'Review today'),
          ]),
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Action required',
                      style: Theme.of(context).textTheme.titleLarge),
                  _ActionTile(
                    title: '42 identity documents',
                    subtitle: 'Oldest waiting 3 hours',
                    status: 'Pending',
                    onTap: () => onNavigate(1),
                  ),
                  _ActionTile(
                    title: '16 listing moderation tasks',
                    subtitle: 'Including 4 reported listings',
                    status: 'Review',
                    onTap: () => onNavigate(2),
                  ),
                  _ActionTile(
                    title: '4 urgent disputes',
                    subtitle: 'Evidence response due today',
                    status: 'Urgent',
                    onTap: () => onNavigate(4),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
}

class _AdminRecordsPage extends StatefulWidget {
  const _AdminRecordsPage({required this.section});
  final int section;
  @override
  State<_AdminRecordsPage> createState() => _AdminRecordsPageState();
}

class _AdminRecordsPageState extends State<_AdminRecordsPage> {
  String query = '';

  String get title => switch (widget.section) {
        1 => 'Users & KYC',
        2 => 'Listing Moderation',
        3 => 'Booking Monitoring',
        4 => 'Disputes & Evidence',
        5 => 'Transactions',
        6 => 'Reports & Analytics',
        8 => 'Audit History',
        _ => 'Records',
      };

  List<_AdminRecord> get records => switch (widget.section) {
        1 => const [
            _AdminRecord('Aina Rahman', 'Verified renter • Trust 96', 'Active'),
            _AdminRecord('Marcus Chen', 'KYC resubmission required', 'Pending'),
            _AdminRecord(
                'Sarah Jenkins', 'Verified Owner • Trust 98', 'Active'),
          ],
        2 => const [
            _AdminRecord(
                'Sony A7III Camera', 'Devices • Daniel Tan', 'Pending'),
            _AdminRecord(
                'Reported Myvi Listing', 'Vehicles • 3 reports', 'Reported'),
            _AdminRecord('Event Photography', 'Services • Mei Lin', 'Approved'),
          ],
        3 => const [
            _AdminRecord('Booking RH-2048', 'Camera • 18–20 Aug', 'Pending'),
            _AdminRecord(
                'Booking RH-2039', 'Myvi • handover complete', 'Active'),
            _AdminRecord('Service RH-2032', 'Photography package', 'Completed'),
          ],
        4 => const [
            _AdminRecord('Dispute DSP-018', 'Late vehicle return', 'Urgent'),
            _AdminRecord('Claim CLM-007', 'Damaged camera lens', 'Open'),
            _AdminRecord('Dispute DSP-011', 'Service deliverables', 'Review'),
          ],
        5 => const [
            _AdminRecord('TXN-8201', 'RM 570.00 • simulated', 'Pending'),
            _AdminRecord('TXN-8194', 'RM 472.50 • service', 'Successful'),
            _AdminRecord('TXN-8172', 'RM 300.00 deposit', 'Refunded'),
          ],
        6 => const [
            _AdminRecord(
                'Marketplace report', 'Monthly GMV and conversion', 'Ready'),
            _AdminRecord(
                'Trust & safety', 'Reports, disputes and KYC', 'Ready'),
            _AdminRecord(
                'Category demand', 'Six-category performance', 'Ready'),
          ],
        8 => const [
            _AdminRecord('AUD-1009', 'KYC approved by Admin Farah', 'Recorded'),
            _AdminRecord(
                'AUD-1008', 'Listing suspended with reason', 'Recorded'),
            _AdminRecord('AUD-1007', 'Dispute resolution updated', 'Recorded'),
          ],
        _ => const [],
      };

  @override
  Widget build(BuildContext context) {
    final visible = records
        .where((record) => '${record.name} ${record.detail} ${record.status}'
            .toLowerCase()
            .contains(query.toLowerCase()))
        .toList();
    return LayoutBuilder(
      builder: (context, constraints) => ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Row(children: [
            Expanded(
              child: TextField(
                onChanged: (value) => setState(() => query = value),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: 'Search $title',
                ),
              ),
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: () => showMockSuccess(context, 'Filters applied'),
              icon: const Icon(Icons.tune),
              label: const Text('Filters'),
            ),
          ]),
          const SizedBox(height: 20),
          if (constraints.maxWidth >= 760)
            Card(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('Record')),
                    DataColumn(label: Text('Details')),
                    DataColumn(label: Text('Status')),
                    DataColumn(label: Text('Action')),
                  ],
                  rows: visible
                      .map((record) => DataRow(cells: [
                            DataCell(Text(record.name)),
                            DataCell(Text(record.detail)),
                            DataCell(StatusBadge(record.status)),
                            DataCell(TextButton(
                              onPressed: () => _open(record),
                              child: Text(widget.section == 8
                                  ? 'View Event'
                                  : 'Review'),
                            )),
                          ]))
                      .toList(),
                ),
              ),
            )
          else
            for (final record in visible) ...[
              Card(
                child: ListTile(
                  contentPadding: const EdgeInsets.all(16),
                  title: Text(record.name),
                  subtitle: Text(record.detail),
                  trailing: StatusBadge(record.status),
                  onTap: () => _open(record),
                ),
              ),
              const SizedBox(height: 10),
            ],
        ],
      ),
    );
  }

  void _open(_AdminRecord record) => Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => _AdminRecordDetailPage(
            section: widget.section,
            record: record,
          ),
        ),
      );
}

class _AdminRecordDetailPage extends StatefulWidget {
  const _AdminRecordDetailPage({
    required this.section,
    required this.record,
  });
  final int section;
  final _AdminRecord record;
  @override
  State<_AdminRecordDetailPage> createState() => _AdminRecordDetailPageState();
}

class _AdminRecordDetailPageState extends State<_AdminRecordDetailPage> {
  late String status = widget.record.status;

  Future<void> _action(String next, {bool destructive = false}) async {
    final reason = TextEditingController();
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text('$next ${widget.record.name}?'),
            content: TextField(
              controller: reason,
              minLines: 2,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Required reason / audit note',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                style: destructive
                    ? FilledButton.styleFrom(backgroundColor: AppColors.error)
                    : null,
                onPressed: () => Navigator.pop(
                  dialogContext,
                  reason.text.trim().length >= 5,
                ),
                child: Text(next),
              ),
            ],
          ),
        ) ??
        false;
    reason.dispose();
    if (!confirmed || !mounted) return;
    setState(() => status = next);
    showMockSuccess(context, '$next completed and added to Audit History');
  }

  @override
  Widget build(BuildContext context) {
    final readOnly = widget.section == 3 || widget.section == 8;
    return Scaffold(
      appBar: AppBar(title: Text(widget.record.name)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(children: [
                      Expanded(
                        child: Text(widget.record.name,
                            style: Theme.of(context).textTheme.titleLarge),
                      ),
                      StatusBadge(status),
                    ]),
                    const SizedBox(height: 12),
                    Text(widget.record.detail),
                    const Divider(height: 28),
                    const Text('Evidence and history',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    const Text(
                      'Identity/listing snapshot • participant history • evidence placeholders • related messages • append-only action log',
                      style: TextStyle(color: AppColors.secondaryText),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (readOnly)
              const Card(
                child: ListTile(
                  leading: Icon(Icons.lock_outline),
                  title: Text('Read-only monitoring record'),
                  subtitle: Text('No state-changing action is available here.'),
                ),
              )
            else if (widget.section == 1) ...[
              RentHubActionButton(
                label:
                    status == 'Suspended' ? 'Reactivate User' : 'Approve KYC',
                onPressed: () =>
                    _action(status == 'Suspended' ? 'Reactivated' : 'Approved'),
              ),
              const SizedBox(height: 8),
              RentHubActionButton(
                label: status == 'Suspended'
                    ? 'Request KYC Resubmission'
                    : 'Suspend User',
                style: RentHubButtonStyle.destructive,
                onPressed: () => _action(
                  status == 'Suspended' ? 'Resubmission Required' : 'Suspended',
                  destructive: true,
                ),
              ),
            ] else if (widget.section == 2) ...[
              RentHubActionButton(
                  label: 'Approve Listing',
                  onPressed: () => _action('Approved')),
              const SizedBox(height: 8),
              RentHubActionButton(
                label: 'Remove Reported Listing',
                style: RentHubButtonStyle.destructive,
                onPressed: () => _action('Removed', destructive: true),
              ),
            ] else if (widget.section == 4) ...[
              RentHubActionButton(
                  label: 'Resolve Dispute',
                  onPressed: () => _action('Resolved')),
              const SizedBox(height: 8),
              RentHubActionButton(
                label: 'Request More Evidence',
                style: RentHubButtonStyle.secondary,
                onPressed: () => _action('Evidence Requested'),
              ),
            ] else if (widget.section == 5)
              RentHubActionButton(
                label: 'Issue Prototype Refund',
                style: RentHubButtonStyle.destructive,
                onPressed: () => _action('Refunded', destructive: true),
              )
            else if (widget.section == 6)
              RentHubActionButton(
                label: 'Export Mock Report',
                onPressed: () => showMockSuccess(
                  context,
                  'Mock report prepared for download',
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CategoryManagementPage extends StatelessWidget {
  const _CategoryManagementPage();
  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Row(children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Category Management',
                      style: Theme.of(context).textTheme.headlineSmall),
                  const Text(
                    'Canonical taxonomy. Required categories are protected.',
                    style: TextStyle(color: AppColors.secondaryText),
                  ),
                ],
              ),
            ),
            FilledButton.icon(
              onPressed: () => showMockSuccess(
                context,
                'All six categories are valid and in canonical order',
              ),
              icon: const Icon(Icons.fact_check_outlined),
              label: const Text('Validate'),
            ),
          ]),
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  for (var i = 0; i < RentHubCategories.values.length; i++)
                    ListTile(
                      leading: CircleAvatar(child: Text('${i + 1}')),
                      title: Text(RentHubCategories.values[i]),
                      subtitle: const Text('Required • Active'),
                      trailing: const Tooltip(
                        message:
                            'Required categories cannot be renamed or deleted',
                        child: Icon(Icons.lock_outline),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      );
}

class _AdminNotificationsPage extends StatefulWidget {
  const _AdminNotificationsPage();
  @override
  State<_AdminNotificationsPage> createState() =>
      _AdminNotificationsPageState();
}

class _AdminNotificationsPageState extends State<_AdminNotificationsPage> {
  final items = <String>[
    '42 KYC submissions require review',
    'Urgent dispute DSP-018 received new evidence',
    'Reported listing threshold reached',
  ];

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Row(children: [
            Expanded(
              child: Text('Admin Notifications',
                  style: Theme.of(context).textTheme.headlineSmall),
            ),
            TextButton(
              onPressed: items.isEmpty ? null : () => setState(items.clear),
              child: const Text('Clear All'),
            ),
          ]),
          const SizedBox(height: 12),
          if (items.isEmpty)
            const RentHubFeedbackState(
              kind: FeedbackKind.empty,
              title: 'No administrative alerts',
              message: 'New platform activity will appear here.',
            )
          else
            for (final item in items) ...[
              Card(
                child: ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: AppColors.primaryLight,
                    child: Icon(Icons.notifications_outlined),
                  ),
                  title: Text(item),
                  subtitle: const Text('Today • Local prototype state'),
                  trailing: IconButton(
                    tooltip: 'Remove notification',
                    onPressed: () => setState(() => items.remove(item)),
                    icon: const Icon(Icons.close),
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
        ],
      );
}

class _AdminProfileSettingsPage extends StatefulWidget {
  const _AdminProfileSettingsPage();
  @override
  State<_AdminProfileSettingsPage> createState() =>
      _AdminProfileSettingsPageState();
}

class _AdminProfileSettingsPageState extends State<_AdminProfileSettingsPage> {
  bool kycAlerts = true;
  bool disputeAlerts = true;
  bool weeklySummary = false;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Wrap(spacing: 16, runSpacing: 16, children: [
            SizedBox(
              width: 300,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(children: [
                    const CircleAvatar(radius: 38, child: Text('NI')),
                    const SizedBox(height: 12),
                    Text('Nur Izzati',
                        style: Theme.of(context).textTheme.titleLarge),
                    const Text('Admin • Kuala Lumpur'),
                    const SizedBox(height: 16),
                    RentHubActionButton(
                      label: 'Sign Out',
                      style: RentHubButtonStyle.destructive,
                      onPressed: () async {
                        if (await confirmAction(
                              context,
                              title: 'Sign out of Admin?',
                              message:
                                  'You will return to the shared RentHub login.',
                              action: 'Sign Out',
                              destructive: true,
                            ) &&
                            context.mounted) {
                          Navigator.pushAndRemoveUntil<void>(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const AdminLogin(),
                            ),
                            (_) => false,
                          );
                        }
                      },
                    ),
                  ]),
                ),
              ),
            ),
            SizedBox(
              width: 520,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('Notification Preferences',
                          style: Theme.of(context).textTheme.titleLarge),
                      SwitchListTile(
                        title: const Text('New KYC registrations'),
                        value: kycAlerts,
                        onChanged: (value) => setState(() => kycAlerts = value),
                      ),
                      SwitchListTile(
                        title: const Text('High-value dispute alerts'),
                        value: disputeAlerts,
                        onChanged: (value) =>
                            setState(() => disputeAlerts = value),
                      ),
                      SwitchListTile(
                        title: const Text('Weekly summary reports'),
                        value: weeklySummary,
                        onChanged: (value) =>
                            setState(() => weeklySummary = value),
                      ),
                      const Divider(height: 28),
                      Text('Security & Password',
                          style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 12),
                      const TextField(
                        obscureText: true,
                        decoration:
                            InputDecoration(labelText: 'Current password'),
                      ),
                      const SizedBox(height: 12),
                      RentHubActionButton(
                        label: 'Update Password',
                        onPressed: () => showMockSuccess(
                          context,
                          'Admin password updated for this prototype session',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ]),
        ],
      );
}

class _AdminRecord {
  const _AdminRecord(this.name, this.detail, this.status);
  final String name;
  final String detail;
  final String status;
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.title,
    required this.subtitle,
    required this.status,
    required this.onTap,
  });
  final String title;
  final String subtitle;
  final String status;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: StatusBadge(status),
        onTap: onTap,
      );
}

class _Metric extends StatelessWidget {
  const _Metric(this.label, this.value, this.note);
  final String label;
  final String value;
  final String note;
  @override
  Widget build(BuildContext context) => SizedBox(
        width: 230,
        height: 164,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(color: AppColors.secondaryText)),
                const Spacer(),
                Text(value, style: Theme.of(context).textTheme.headlineSmall),
                Text(note,
                    style: const TextStyle(
                        color: AppColors.success, fontSize: 12)),
              ],
            ),
          ),
        ),
      );
}

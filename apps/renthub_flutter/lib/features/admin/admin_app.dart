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
    _Destination('Verification', Icons.verified_user_outlined),
    _Destination('Users', Icons.people_outline),
    _Destination('Listings', Icons.inventory_2_outlined),
    _Destination('Bookings & Transactions', Icons.receipt_long_outlined),
    _Destination('Disputes & Claims', Icons.gavel_outlined),
    _Destination('Reports', Icons.bar_chart_outlined),
    _Destination('Reviews', Icons.rate_review_outlined),
    _Destination('Platform Settings', Icons.settings_outlined),
    _Destination('Audit Logs', Icons.history),
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
                  onPressed: () => Navigator.push<void>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const _AdminNotificationsRoute(),
                    ),
                  ),
                  icon: const Badge(child: Icon(Icons.notifications_outlined)),
                ),
                IconButton(
                  tooltip: 'Admin profile',
                  onPressed: () => Navigator.push<void>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const _AdminProfileRoute(),
                    ),
                  ),
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
                    key: ValueKey('admin-nav-$i'),
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
        8 => const _PlatformSettingsPage(),
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
                    onTap: () => onNavigate(3),
                  ),
                  _ActionTile(
                    title: '4 urgent disputes',
                    subtitle: 'Evidence response due today',
                    status: 'Urgent',
                    onTap: () => onNavigate(5),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              _AdminShortcutCard(
                icon: Icons.health_and_safety_outlined,
                title: 'Platform Health',
                subtitle: 'All prototype services operational',
                onTap: () => Navigator.push<void>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const _PlatformHealthPage(),
                  ),
                ),
              ),
              _AdminShortcutCard(
                icon: Icons.policy_outlined,
                title: 'Fraud & Risk',
                subtitle: '7 indicators require review',
                onTap: () => Navigator.push<void>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const _FraudRiskPage(),
                  ),
                ),
              ),
            ],
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
        1 => 'Identity Verification',
        2 => 'User Directory',
        3 => 'Listing Moderation',
        4 => 'Bookings & Transactions',
        5 => 'Disputes & Claims',
        6 => 'Reports',
        7 => 'Review Moderation',
        9 => 'Audit Logs',
        _ => 'Records',
      };

  List<_AdminRecord> get records => switch (widget.section) {
        1 => const [
            _AdminRecord('KYC-2041 • Marcus Chen', 'MyKad • OCR confidence 81%',
                'Pending'),
            _AdminRecord('KYC-2038 • Siti Nabila',
                'Passport • image requires review', 'Resubmission'),
            _AdminRecord('KYC-2036 • Alex Tan', 'MyKad • OCR confidence 97%',
                'Approved'),
          ],
        2 => const [
            _AdminRecord('Alex Tan', 'Verified renter • Trust 92', 'Active'),
            _AdminRecord('Marcus Chen', 'KYC resubmission required', 'Active'),
            _AdminRecord('Sarah J.', 'Verified Owner • Gold Tier', 'Active'),
          ],
        3 => const [
            _AdminRecord('Sony Alpha a7S III Mirrorless Camera',
                'Devices • Sarah J.', 'Pending'),
            _AdminRecord(
                'Reported Myvi Listing', 'Vehicles • 3 reports', 'Reported'),
            _AdminRecord(
                'Event Photography', 'Services • Aina Rahman', 'Approved'),
          ],
        4 => const [
            _AdminRecord('Booking RH-BKG-2026-09142',
                'RM 570.00 • Camera • 20–22 Sep 2026', 'Pending'),
            _AdminRecord(
                'Transaction TXN-8194', 'RM 472.50 • Service', 'Successful'),
            _AdminRecord(
                'Transaction TXN-8172', 'RM 300.00 deposit', 'Refunded'),
          ],
        5 => const [
            _AdminRecord('Dispute DSP-018', 'Late vehicle return', 'Urgent'),
            _AdminRecord('Claim CLM-007', 'Damaged camera lens', 'Open'),
            _AdminRecord('Dispute DSP-011', 'Service deliverables', 'Review'),
          ],
        6 => const [
            _AdminRecord(
                'Marketplace report', 'Monthly GMV and conversion', 'Ready'),
            _AdminRecord(
                'Trust & safety', 'Reports, disputes and KYC', 'Ready'),
            _AdminRecord(
                'Category demand', 'Six-category performance', 'Ready'),
          ],
        7 => const [
            _AdminRecord('REV-0321 • Camera rental',
                '5 stars • Clear and respectful', 'Published'),
            _AdminRecord('REV-0319 • Vehicle rental',
                '1 star • Reported by Owner', 'Flagged'),
            _AdminRecord('REV-0312 • Event photography',
                '4 stars • Service completed', 'Published'),
          ],
        9 => const [
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
          Text(title, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 16),
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
                              key: ValueKey('admin-review-${record.name}'),
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
    showMockSuccess(context, '$next completed and added to Audit Logs');
  }

  @override
  Widget build(BuildContext context) {
    final readOnly = widget.section == 9 ||
        (widget.section == 4 && widget.record.name.startsWith('Booking'));
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
            if (widget.section == 1) ...[
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('Document and OCR Review',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                      SizedBox(height: 12),
                      _AdminEvidenceRow('Document type', 'MyKad'),
                      _AdminEvidenceRow('Name extracted', 'Marcus Chen'),
                      _AdminEvidenceRow('MyKad number', 'Masked for prototype'),
                      _AdminEvidenceRow(
                          'OCR confidence', '81% • Manual review'),
                      _AdminEvidenceRow(
                          'Forgery indicator', 'No decisive indicator'),
                      SizedBox(height: 8),
                      Text(
                        'Front and back document image placeholders. No real identity document is displayed.',
                        style: TextStyle(color: AppColors.secondaryText),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
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
                label: 'Approve KYC',
                onPressed: () => _action('Approved'),
              ),
              const SizedBox(height: 8),
              RentHubActionButton(
                label: 'Request Resubmission',
                style: RentHubButtonStyle.secondary,
                onPressed: () => _action('Resubmission Required'),
              ),
              const SizedBox(height: 8),
              RentHubActionButton(
                label: 'Reject KYC',
                style: RentHubButtonStyle.destructive,
                onPressed: () => _action('Rejected', destructive: true),
              ),
            ] else if (widget.section == 2) ...[
              RentHubActionButton(
                label:
                    status == 'Suspended' ? 'Reactivate User' : 'Suspend User',
                onPressed: () => _action(
                  status == 'Suspended' ? 'Reactivated' : 'Suspended',
                  destructive: status != 'Suspended',
                ),
              ),
              const SizedBox(height: 8),
              RentHubActionButton(
                label: 'Ban Account',
                style: RentHubButtonStyle.destructive,
                onPressed: () => _action('Banned', destructive: true),
              ),
            ] else if (widget.section == 3) ...[
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
                label: 'Issue Prototype Refund',
                style: RentHubButtonStyle.destructive,
                onPressed: () => _action('Refunded', destructive: true),
              ),
            ] else if (widget.section == 5) ...[
              RentHubActionButton(
                  label: 'Resolve Dispute',
                  onPressed: () => _action('Resolved')),
              const SizedBox(height: 8),
              RentHubActionButton(
                label: 'Request More Evidence',
                style: RentHubButtonStyle.secondary,
                onPressed: () => _action('Evidence Requested'),
              ),
            ] else if (widget.section == 6)
              RentHubActionButton(
                label: 'Export Mock Report',
                onPressed: () => showMockSuccess(
                  context,
                  'Mock report prepared for download',
                ),
              )
            else if (widget.section == 7) ...[
              RentHubActionButton(
                label: status == 'Hidden' ? 'Restore Review' : 'Keep Published',
                onPressed: () => _action(
                  status == 'Hidden' ? 'Published' : 'Published',
                ),
              ),
              const SizedBox(height: 8),
              RentHubActionButton(
                label: 'Hide Review',
                style: RentHubButtonStyle.destructive,
                onPressed: () => _action('Hidden', destructive: true),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PlatformSettingsPage extends StatefulWidget {
  const _PlatformSettingsPage();

  @override
  State<_PlatformSettingsPage> createState() => _PlatformSettingsPageState();
}

class _PlatformSettingsPageState extends State<_PlatformSettingsPage> {
  final formKey = GlobalKey<FormState>();
  final platformFee = TextEditingController(text: '5.0');
  final referralPoints = TextEditingController(text: '250');
  bool maintenanceMode = false;
  bool highValueKyc = true;

  @override
  void dispose() {
    platformFee.dispose();
    referralPoints.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Form(
        key: formKey,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text('Platform Settings',
                style: Theme.of(context).textTheme.headlineSmall),
            const Text(
              'Prototype rules update only the local administrator interface.',
              style: TextStyle(color: AppColors.secondaryText),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                SizedBox(
                  width: 440,
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text('Marketplace Rules',
                              style: Theme.of(context).textTheme.titleLarge),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: platformFee,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Prototype platform fee (%)',
                            ),
                            validator: (value) {
                              final number = double.tryParse(value ?? '');
                              return number == null || number < 0 || number > 20
                                  ? 'Enter a value from 0 to 20'
                                  : null;
                            },
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: referralPoints,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Successful referral points',
                            ),
                            validator: (value) =>
                                (int.tryParse(value ?? '') ?? 0) < 1
                                    ? 'Enter at least 1 point'
                                    : null,
                          ),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title:
                                const Text('Require KYC for high-value items'),
                            value: highValueKyc,
                            onChanged: (value) =>
                                setState(() => highValueKyc = value),
                          ),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Maintenance mode'),
                            subtitle: const Text(
                              'Displays a prototype maintenance notice only.',
                            ),
                            value: maintenanceMode,
                            onChanged: (value) =>
                                setState(() => maintenanceMode = value),
                          ),
                          const SizedBox(height: 12),
                          RentHubActionButton(
                            label: 'Save Platform Settings',
                            onPressed: () {
                              if (formKey.currentState!.validate()) {
                                showMockSuccess(
                                  context,
                                  'Platform settings saved and audit entry added',
                                );
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  width: 360,
                  child: Card(
                    child: Column(
                      children: [
                        ListTile(
                          leading: const Icon(Icons.category_outlined),
                          title: const Text('Listing Categories'),
                          subtitle: const Text('6 protected categories'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.push<void>(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const _CategoryManagementRoute(),
                            ),
                          ),
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: const Icon(Icons.health_and_safety_outlined),
                          title: const Text('Platform Health'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.push<void>(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const _PlatformHealthPage(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
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

class _CategoryManagementRoute extends StatelessWidget {
  const _CategoryManagementRoute();

  @override
  Widget build(BuildContext context) => const Scaffold(
        appBar: _AdminRouteAppBar(title: 'Listing Categories'),
        body: SafeArea(child: _CategoryManagementPage()),
      );
}

class _PlatformHealthPage extends StatelessWidget {
  const _PlatformHealthPage();

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Platform Health')),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const Card(
                color: AppColors.blueSurface,
                child: ListTile(
                  leading: Icon(Icons.check_circle, color: AppColors.success),
                  title: Text('All prototype components operational'),
                  subtitle: Text(
                    'This status is simulated and does not monitor production services.',
                  ),
                ),
              ),
              const SizedBox(height: 12),
              for (final component in const [
                ('Flutter application', 'Available', '42 ms'),
                ('Mock API adapter', 'Available', '68 ms'),
                ('Mock AI adapter', 'Available', '124 ms'),
                ('Local message channel', 'Available', '35 ms'),
              ])
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.dns_outlined),
                    title: Text(component.$1),
                    subtitle: Text('Prototype response: ${component.$3}'),
                    trailing: StatusBadge(component.$2),
                  ),
                ),
            ],
          ),
        ),
      );
}

class _FraudRiskPage extends StatefulWidget {
  const _FraudRiskPage();

  @override
  State<_FraudRiskPage> createState() => _FraudRiskPageState();
}

class _FraudRiskPageState extends State<_FraudRiskPage> {
  final statuses = ['Review', 'Review', 'Monitored'];

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Fraud & Risk Indicators')),
        body: SafeArea(
          child: ListView.builder(
            padding: const EdgeInsets.all(24),
            itemCount: statuses.length,
            itemBuilder: (context, index) {
              final records = const [
                ('RISK-021', 'Repeated identity-document image'),
                ('RISK-019', 'Unusual high-value booking activity'),
                ('RISK-014', 'Multiple listing reports'),
              ];
              return Card(
                child: ListTile(
                  contentPadding: const EdgeInsets.all(16),
                  leading: const Icon(Icons.policy_outlined,
                      color: AppColors.warning),
                  title: Text(records[index].$1),
                  subtitle: Text(records[index].$2),
                  trailing: StatusBadge(statuses[index]),
                  onTap: () async {
                    final accepted = await confirmAction(
                      context,
                      title: 'Flag this risk indicator?',
                      message:
                          'The related account will be marked for manual review and an audit event will be added.',
                      action: 'Flag for Review',
                    );
                    if (accepted && mounted) {
                      setState(() => statuses[index] = 'Flagged');
                    }
                  },
                ),
              );
            },
          ),
        ),
      );
}

class _AdminNotificationsRoute extends StatelessWidget {
  const _AdminNotificationsRoute();

  @override
  Widget build(BuildContext context) => const Scaffold(
        appBar: _AdminRouteAppBar(title: 'Admin Notifications'),
        body: SafeArea(child: _AdminNotificationsPage()),
      );
}

class _AdminProfileRoute extends StatelessWidget {
  const _AdminProfileRoute();

  @override
  Widget build(BuildContext context) => const Scaffold(
        appBar: _AdminRouteAppBar(title: 'Admin Profile'),
        body: SafeArea(child: _AdminProfileSettingsPage()),
      );
}

class _AdminRouteAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _AdminRouteAppBar({required this.title});

  final String title;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) => AppBar(title: Text(title));
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

class _AdminEvidenceRow extends StatelessWidget {
  const _AdminEvidenceRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 150,
              child: Text(
                label,
                style: const TextStyle(color: AppColors.secondaryText),
              ),
            ),
            Expanded(child: Text(value)),
          ],
        ),
      );
}

class _AdminShortcutCard extends StatelessWidget {
  const _AdminShortcutCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 330,
        child: Card(
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: AppColors.primaryLight,
                    child: Icon(icon, color: AppColors.primaryDark),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title,
                            style: Theme.of(context).textTheme.titleMedium),
                        Text(
                          subtitle,
                          style:
                              const TextStyle(color: AppColors.secondaryText),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right),
                ],
              ),
            ),
          ),
        ),
      );
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
        height: 172,
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

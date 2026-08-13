import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/renthub_components.dart';

class AdminApp extends StatelessWidget {
  const AdminApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'RentHub Admin',
      theme: AppTheme.light,
      home: const AdminLogin());
}

class AdminLogin extends StatefulWidget {
  const AdminLogin({super.key});
  @override
  State<AdminLogin> createState() => _AdminLoginState();
}

class _AdminLoginState extends State<AdminLogin> {
  final key = GlobalKey<FormState>();
  @override
  Widget build(BuildContext context) => Scaffold(
      body: Center(
          child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Card(
                  child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Form(
                          key: key,
                          child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const RentHubLogo(),
                                const SizedBox(height: 32),
                                Text('Administrator portal',
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineSmall
                                        ?.copyWith(
                                            fontWeight: FontWeight.w800)),
                                const SizedBox(height: 20),
                                TextFormField(
                                    initialValue: 'admin@renthub.my',
                                    decoration: const InputDecoration(
                                        labelText: 'Work email'),
                                    validator: (v) => v?.contains('@') == true
                                        ? null
                                        : 'Enter a valid email'),
                                const SizedBox(height: 12),
                                TextFormField(
                                    initialValue: 'password',
                                    obscureText: true,
                                    decoration: const InputDecoration(
                                        labelText: 'Password'),
                                    validator: (v) => (v?.length ?? 0) >= 6
                                        ? null
                                        : 'At least 6 characters'),
                                const SizedBox(height: 20),
                                FilledButton(
                                    onPressed: () {
                                      if (key.currentState!.validate()) {
                                        Navigator.pushReplacement(
                                            context,
                                            MaterialPageRoute(
                                                builder: (_) =>
                                                    const AdminShell()));
                                      }
                                    },
                                    child: const Text('Sign in securely')),
                                const SizedBox(height: 8),
                                const Text(
                                    'Prototype credentials are pre-filled. No external authentication is used.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                        color: AppColors.secondaryText,
                                        fontSize: 12))
                              ])))))));
}

class AdminShell extends StatefulWidget {
  const AdminShell({super.key});
  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  int selected = 0;
  static const labels = [
    'Dashboard',
    'Verification',
    'Users',
    'Listings',
    'Bookings & Transactions',
    'Disputes & Claims',
    'Reports',
    'Reviews',
    'Platform Settings',
    'Audit Logs'
  ];
  static const icons = [
    Icons.dashboard_outlined,
    Icons.verified_user_outlined,
    Icons.people_outline,
    Icons.inventory_2_outlined,
    Icons.receipt_long_outlined,
    Icons.gavel_outlined,
    Icons.flag_outlined,
    Icons.reviews_outlined,
    Icons.settings_outlined,
    Icons.history
  ];
  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        final wide = c.maxWidth >= 900;
        final nav = ListView(children: [
          const Padding(padding: EdgeInsets.all(20), child: RentHubLogo()),
          for (int i = 0; i < labels.length; i)
            ListTile(
                selected: selected == i,
                selectedTileColor: AppColors.primaryLight,
                leading: Icon(icons[i]),
                title: Text(labels[i]),
                onTap: () {
                  setState(() => selected = i);
                  if (!wide) Navigator.pop(context);
                })
        ]);
        return Scaffold(
            drawer: wide ? null : Drawer(child: SafeArea(child: nav)),
            appBar: AppBar(
                automaticallyImplyLeading: !wide,
                title: Text(labels[selected]),
                actions: [
                  IconButton(
                      onPressed: () =>
                          showMockSuccess(context, 'No new alerts'),
                      icon: const Badge(
                          child: Icon(Icons.notifications_outlined))),
                  const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: CircleAvatar(child: Text('AF')))
                ]),
            body: Row(children: [
              if (wide)
                SizedBox(
                    width: c.maxWidth > 1100 ? 270 : 220,
                    child: ColoredBox(
                        color: Colors.white, child: SafeArea(child: nav))),
              Expanded(child: AdminPage(index: selected))
            ]));
      });
}

class AdminPage extends StatefulWidget {
  const AdminPage({super.key, required this.index});
  final int index;
  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  String state = 'Pending';
  @override
  Widget build(BuildContext context) {
    if (widget.index == 0) return const _Dashboard();
    final names = [
      'Verification case',
      'User account',
      'Sony Alpha A7 III Camera',
      'Booking RH-2048',
      'Dispute DSP-018',
      'Listing report',
      'Review by Aina',
      'Marketplace configuration',
      'Audit event'
    ];
    return ListView(padding: const EdgeInsets.all(24), children: [
      Row(children: [
        Expanded(
            child: TextField(
                decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText:
                        'Search ${names[widget.index - 1].toLowerCase()}s'))),
        const SizedBox(width: 12),
        OutlinedButton.icon(
            onPressed: () => showMockSuccess(context, 'Filters opened'),
            icon: const Icon(Icons.tune),
            label: const Text('Filters'))
      ]),
      const SizedBox(height: 20),
      Card(
          child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                  columns: const [
                    DataColumn(label: Text('Record')),
                    DataColumn(label: Text('Details')),
                    DataColumn(label: Text('Status')),
                    DataColumn(label: Text('Actions'))
                  ],
                  rows: List.generate(
                      6,
                      (i) => DataRow(cells: [
                            DataCell(
                                Text('${names[widget.index - 1]} #${100 + i}')),
                            DataCell(Text(i.isEven
                                ? 'Kuala Lumpur • 13 Aug 2026'
                                : 'Petaling Jaya • 12 Aug 2026')),
                            DataCell(StatusBadge(i == 0
                                ? state
                                : i.isEven
                                    ? 'Approved'
                                    : 'Open')),
                            DataCell(widget.index == 9
                                ? const Text('Read only')
                                : Row(children: [
                                    TextButton(
                                        onPressed: () => showMockSuccess(
                                            context, 'Details opened'),
                                        child: const Text('Review')),
                                    if (widget.index < 8)
                                      PopupMenuButton(
                                          itemBuilder: (_) => const [
                                                PopupMenuItem(
                                                    value: 'approve',
                                                    child: Text('Approve')),
                                                PopupMenuItem(
                                                    value: 'reject',
                                                    child: Text(
                                                        'Reject / suspend'))
                                              ],
                                          onSelected: (v) async {
                                            if (await confirmAction(context,
                                                title:
                                                    'Confirm administrative action?',
                                                message:
                                                    'A reason and audit-log entry will be required.',
                                                action: v == 'approve'
                                                    ? 'Approve'
                                                    : 'Continue',
                                                destructive: v == 'reject')) {
                                              setState(() => state =
                                                  v == 'approve'
                                                      ? 'Approved'
                                                      : 'Rejected');
                                            }
                                          })
                                  ]))
                          ])))))
    ]);
  }
}

class _Dashboard extends StatelessWidget {
  const _Dashboard();
  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Wrap(spacing: 16, runSpacing: 16, children: [
            _AdminMetric('Gross bookings', 'RM 184,250', '+12.4%'),
            _AdminMetric('Active users', '12,480', '+6.2%'),
            _AdminMetric('Open disputes', '18', '4 urgent'),
            _AdminMetric('Pending verification', '42', 'Review today'),
          ]),
          const SizedBox(height: 24),
          Card(
              child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Pending work',
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800)),
                      const ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text('Identity documents'),
                          trailing: StatusBadge('42 Pending')),
                      const ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text('Listing moderation'),
                          trailing: StatusBadge('16 Pending')),
                      const ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text('Claims'),
                          trailing: StatusBadge('5 Open')),
                    ],
                  ))),
        ],
      );
}

class _AdminMetric extends StatelessWidget {
  const _AdminMetric(this.label, this.value, this.note);
  final String label, value, note;
  @override
  Widget build(BuildContext context) => SizedBox(
      width: 230,
      height: 130,
      child: Card(
          child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: const TextStyle(color: AppColors.secondaryText)),
                    const Spacer(),
                    Text(value,
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w800)),
                    Text(note,
                        style: const TextStyle(
                            color: AppColors.success, fontSize: 12))
                  ]))));
}

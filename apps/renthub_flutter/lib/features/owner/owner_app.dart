import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/mock_data/mock_data.dart';
import '../../shared/widgets/renthub_components.dart';
import '../renter/renter_app.dart' show MessagesPage, ProfilePage;

class OwnerShell extends StatefulWidget {
  const OwnerShell(
      {super.key, required this.onSwitchRole, required this.canSwitch});
  final VoidCallback onSwitchRole;
  final bool canSwitch;
  @override
  State<OwnerShell> createState() => _OwnerShellState();
}

class _OwnerShellState extends State<OwnerShell> {
  int index = 0;
  @override
  Widget build(BuildContext context) {
    final pages = [
      const OwnerDashboard(),
      const OwnerListings(),
      const OwnerRequests(),
      const MessagesPage(),
      ProfilePage(
          role: 'Owner',
          canSwitch: widget.canSwitch,
          onSwitch: widget.onSwitchRole)
    ];
    return Scaffold(
        body: IndexedStack(index: index, children: pages),
        bottomNavigationBar: NavigationBar(
            selectedIndex: index,
            onDestinationSelected: (v) => setState(() => index = v),
            destinations: const [
              NavigationDestination(
                  icon: Icon(Icons.dashboard_outlined), label: 'Dashboard'),
              NavigationDestination(
                  icon: Icon(Icons.inventory_2_outlined), label: 'Listings'),
              NavigationDestination(
                  icon: Icon(Icons.assignment_outlined), label: 'Requests'),
              NavigationDestination(
                  icon: Icon(Icons.chat_bubble_outline), label: 'Messages'),
              NavigationDestination(
                  icon: Icon(Icons.person_outline), label: 'Profile')
            ]));
  }
}

class OwnerDashboard extends StatelessWidget {
  const OwnerDashboard({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const RentHubLogo(), actions: [
        IconButton(
            onPressed: () => showMockSuccess(context, 'Notifications opened'),
            icon: const Badge(child: Icon(Icons.notifications_outlined)))
      ]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text('Good afternoon, Nur',
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.w800)),
        const Text('Here’s what needs your attention.',
            style: TextStyle(color: AppColors.secondaryText)),
        const SizedBox(height: 20),
        GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.35,
            children: const [
              _Metric('Active listings', '6', Icons.inventory_2_outlined),
              _Metric('Pending requests', '3', Icons.schedule),
              _Metric('This month', 'RM 2,840', Icons.payments_outlined),
              _Metric('Trust score', '4.7 / 5', Icons.star_outline)
            ]),
        const SizedBox(height: 24),
        Text('Action needed',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Card(
            child: Column(children: [
          ListTile(
              leading: const CircleAvatar(
                  backgroundColor: AppColors.primaryLight,
                  child: Icon(Icons.calendar_month)),
              title: const Text('3 booking requests'),
              subtitle: const Text('Oldest request expires in 5 hours'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => showMockSuccess(context, 'Requests opened')),
          const Divider(height: 1),
          ListTile(
              leading: const CircleAvatar(
                  backgroundColor: AppColors.primaryLight,
                  child: Icon(Icons.assignment_return_outlined)),
              title: const Text('Camera return due today'),
              subtitle: const Text('Confirm returned condition'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => showMockSuccess(context, 'Return inspection opened'))
        ])),
        const SizedBox(height: 24),
        Text('Recent earnings',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w800)),
        const Card(
            child: ListTile(
                title: Text('Sony Alpha A7 III Camera'),
                subtitle: Text('Successful • 12 Aug 2026'),
                trailing: Text('+ RM 228.00',
                    style: TextStyle(
                        color: AppColors.success,
                        fontWeight: FontWeight.bold))))
      ]));
}

class _Metric extends StatelessWidget {
  const _Metric(this.label, this.value, this.icon);
  final String label, value;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Card(
      child: Padding(
          padding: const EdgeInsets.all(14),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, color: AppColors.primary),
            const Spacer(),
            Text(value,
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800)),
            Text(label,
                style: const TextStyle(
                    color: AppColors.secondaryText, fontSize: 12))
          ])));
}

class OwnerListings extends StatelessWidget {
  const OwnerListings({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('My listings')),
      floatingActionButton: FloatingActionButton.extended(
          onPressed: () => showModalBottomSheet(
              context: context,
              showDragHandle: true,
              builder: (_) => Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('Create listing',
                            style: Theme.of(context).textTheme.titleLarge),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                            onPressed: () {
                              Navigator.pop(context);
                              Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) =>
                                          const ListingForm(isService: false)));
                            },
                            icon: const Icon(Icons.inventory_2_outlined),
                            label: const Text('Physical item')),
                        OutlinedButton.icon(
                            onPressed: () {
                              Navigator.pop(context);
                              Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) =>
                                          const ListingForm(isService: true)));
                            },
                            icon: const Icon(Icons.design_services_outlined),
                            label: const Text('Service'))
                      ]))),
          icon: const Icon(Icons.add),
          label: const Text('New listing')),
      body: ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: MockData.listings.length,
          itemBuilder: (context, i) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Card(
                  child: ListTile(
                      contentPadding: const EdgeInsets.all(12),
                      leading: CircleAvatar(
                          backgroundColor: AppColors.primaryLight,
                          child: Icon(MockData.listings[i].isService
                              ? Icons.design_services
                              : Icons.inventory_2)),
                      title: Text(MockData.listings[i].title),
                      subtitle: Text(
                          'RM ${MockData.listings[i].dailyPrice.toStringAsFixed(2)}'),
                      trailing: StatusBadge(i == 3
                          ? 'Draft'
                          : i == 4
                              ? 'Pending review'
                              : 'Active'),
                      onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => ListingForm(
                                  isService:
                                      MockData.listings[i].isService))))))));
}

class ListingForm extends StatefulWidget {
  const ListingForm({super.key, required this.isService});
  final bool isService;
  @override
  State<ListingForm> createState() => _ListingFormState();
}

class _ListingFormState extends State<ListingForm> {
  final key = GlobalKey<FormState>();
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(
          title: Text(
              widget.isService ? 'Service listing' : 'Physical-item listing')),
      body: Form(
          key: key,
          child: ListView(padding: const EdgeInsets.all(16), children: [
            Container(
                height: 150,
                decoration: BoxDecoration(
                    color: AppColors.primaryLight,
                    borderRadius: BorderRadius.circular(16)),
                child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add_photo_alternate_outlined,
                          size: 42, color: AppColors.primary),
                      Text('Add image placeholders')
                    ])),
            const SizedBox(height: 16),
            TextFormField(
                decoration: const InputDecoration(labelText: 'Title'),
                validator: (v) =>
                    v == null || v.isEmpty ? 'Title is required' : null),
            const SizedBox(height: 12),
            TextFormField(
                decoration: InputDecoration(
                    labelText: widget.isService
                        ? 'Package price (RM)'
                        : 'Daily price (RM)',
                    helperText:
                        'Suggested price: RM ${widget.isService ? '350–700' : '80–140'}')),
            const SizedBox(height: 12),
            TextFormField(
                decoration: const InputDecoration(labelText: 'Location')),
            const SizedBox(height: 12),
            if (widget.isService) ...[
              TextFormField(
                  decoration:
                      const InputDecoration(labelText: 'Package details'),
                  maxLines: 3),
              const SizedBox(height: 12),
              TextFormField(
                  decoration: const InputDecoration(labelText: 'Duration'))
            ] else ...[
              DropdownButtonFormField(
                  initialValue: 'Excellent',
                  decoration: const InputDecoration(labelText: 'Condition'),
                  items: ['New', 'Excellent', 'Good', 'Fair']
                      .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                      .toList(),
                  onChanged: (_) {}),
              const SizedBox(height: 12),
              TextFormField(
                  decoration: const InputDecoration(
                      labelText: 'Security deposit (RM)')),
              const SizedBox(height: 12),
              const ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.verified_user_outlined),
                  title: Text('Item verification'),
                  subtitle: Text('Mock verification: eligible'))
            ],
            const SizedBox(height: 12),
            const ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.calendar_month_outlined),
                title: Text('Manage availability'),
                trailing: Icon(Icons.chevron_right)),
            SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Promotional discount'),
                value: false,
                onChanged: (_) =>
                    showMockSuccess(context, 'Discount settings opened')),
            const SizedBox(height: 20),
            FilledButton(
                onPressed: () {
                  if (key.currentState!.validate()) {
                    showMockSuccess(context, 'Listing saved for review');
                    Navigator.pop(context);
                  }
                },
                child: const Text('Save listing'))
          ])));
}

class OwnerRequests extends StatefulWidget {
  const OwnerRequests({super.key});
  @override
  State<OwnerRequests> createState() => _OwnerRequestsState();
}

class _OwnerRequestsState extends State<OwnerRequests> {
  final states = ['Pending', 'Pending', 'Approved'];
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Booking requests')),
      body: ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: 3,
          itemBuilder: (context, i) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Card(
                  child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Expanded(
                                  child: Text(MockData.listings[i].title,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold))),
                              StatusBadge(states[i])
                            ]),
                            const SizedBox(height: 8),
                            const Text('Aina Rahman • Verified • Trust 4.8'),
                            const Text('18–20 Aug 2026'),
                            if (states[i] == 'Pending') ...[
                              const SizedBox(height: 12),
                              Row(children: [
                                Expanded(
                                    child: OutlinedButton(
                                        onPressed: () async {
                                          if (await confirmAction(context,
                                              title: 'Reject request?',
                                              message:
                                                  'A reason will be recorded for the renter.',
                                              action: 'Reject',
                                              destructive: true)) {
                                            setState(
                                                () => states[i] = 'Rejected');
                                          }
                                        },
                                        child: const Text('Reject'))),
                                const SizedBox(width: 8),
                                Expanded(
                                    child: FilledButton(
                                        onPressed: () async {
                                          if (await confirmAction(context,
                                              title: 'Approve request?',
                                              message:
                                                  'The renter will be notified immediately.',
                                              action: 'Approve')) {
                                            setState(
                                                () => states[i] = 'Approved');
                                          }
                                        },
                                        child: const Text('Approve')))
                              ])
                            ]
                          ]))))));
}

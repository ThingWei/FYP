import 'package:flutter/material.dart';
import '../../core/constants/renthub_categories.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/mock_data/mock_data.dart';
import '../../shared/models/domain_models.dart';
import '../../shared/widgets/account_components.dart';
import '../../shared/widgets/renthub_components.dart';
import '../account/account_pages.dart';
import '../renter/renter_app.dart' show MessagesPage;
import '../renter/rentals/pages/rate_review_page.dart';

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
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const NotificationsPage())),
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
              onTap: () => Navigator.push<void>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const OwnerRequests(standalone: true),
                    ),
                  )),
          const Divider(height: 1),
          ListTile(
              leading: const CircleAvatar(
                  backgroundColor: AppColors.primaryLight,
                  child: Icon(Icons.assignment_return_outlined)),
              title: const Text('Camera return due today'),
              subtitle: const Text('Confirm returned condition'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push<void>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const OwnerActiveRentalsPage(),
                    ),
                  ))
        ])),
        const SizedBox(height: 24),
        Text('Recent earnings',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w800)),
        Card(
            child: ListTile(
                title: Text('Sony Alpha A7 III Camera'),
                subtitle: const Text('Successful • 12 Aug 2026'),
                trailing: const Text('+ RM 228.00',
                    style: TextStyle(
                        color: AppColors.success, fontWeight: FontWeight.bold)),
                onTap: () => Navigator.push<void>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const OwnerEarningsPage(),
                      ),
                    )))
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
  late String category =
      widget.isService ? RentHubCategories.services : RentHubCategories.devices;
  bool promotion = false;
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
            DropdownButtonFormField<String>(
                initialValue: category,
                decoration: const InputDecoration(labelText: 'Category'),
                items: (widget.isService
                        ? const [RentHubCategories.services]
                        : RentHubCategories.values
                            .where(
                                (value) => value != RentHubCategories.services)
                            .toList())
                    .map((value) =>
                        DropdownMenuItem(value: value, child: Text(value)))
                    .toList(),
                onChanged: (value) =>
                    setState(() => category = value ?? category)),
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
              ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.verified_user_outlined),
                  title: const Text('Item verification'),
                  subtitle: const Text('Mock verification: eligible'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push<void>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const OwnerItemVerificationPage(),
                        ),
                      ))
            ],
            const SizedBox(height: 12),
            ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.calendar_month_outlined),
                title: const Text('Manage availability'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push<void>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const OwnerAvailabilityPage(),
                      ),
                    )),
            SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Promotional discount'),
                value: promotion,
                onChanged: (value) => setState(() => promotion = value)),
            const SizedBox(height: 20),
            OutlinedButton(
                onPressed: () => Navigator.push<void>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ListingPreviewPage(
                          isService: widget.isService,
                          category: category,
                        ),
                      ),
                    ),
                child: const Text('Preview Listing')),
            const SizedBox(height: 8),
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
  const OwnerRequests({super.key, this.standalone = false});
  final bool standalone;
  @override
  State<OwnerRequests> createState() => _OwnerRequestsState();
}

class _OwnerRequestsState extends State<OwnerRequests> {
  final states = ['Pending', 'Pending', 'Approved'];

  Future<void> _review(int index) async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => OwnerRequestDetailsPage(
          listing: MockData.listings[index],
          initialStatus: states[index],
        ),
      ),
    );
    if (result != null && mounted) setState(() => states[index] = result);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(
          title: Text(
              widget.standalone ? 'All Booking Requests' : 'Booking requests'),
          actions: [
            IconButton(
              tooltip: 'Active rentals',
              onPressed: () => Navigator.push<void>(
                context,
                MaterialPageRoute(
                  builder: (_) => const OwnerActiveRentalsPage(),
                ),
              ),
              icon: const Icon(Icons.inventory_2_outlined),
            ),
          ]),
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
                            const SizedBox(height: 8),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton(
                                onPressed: () => _review(i),
                                child: const Text('View Request Details'),
                              ),
                            ),
                            if (states[i] == 'Pending') ...[
                              const SizedBox(height: 12),
                              Row(children: [
                                Expanded(
                                    child: OutlinedButton(
                                        onPressed: () => _review(i),
                                        child: const Text('Reject'))),
                                const SizedBox(width: 8),
                                Expanded(
                                    child: FilledButton(
                                        onPressed: () => _review(i),
                                        child: const Text('Approve')))
                              ])
                            ]
                          ]))))));
}

class ListingPreviewPage extends StatelessWidget {
  const ListingPreviewPage({
    super.key,
    required this.isService,
    required this.category,
  });
  final bool isService;
  final String category;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Review & Publish')),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        height: 160,
                        decoration: BoxDecoration(
                          color: AppColors.primaryLight,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          isService
                              ? Icons.design_services_outlined
                              : Icons.inventory_2_outlined,
                          size: 64,
                          color: AppColors.primaryDark,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        isService
                            ? 'Professional Service Package'
                            : 'Verified Rental Listing',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      Text(category,
                          style:
                              const TextStyle(color: AppColors.secondaryText)),
                      const SizedBox(height: 12),
                      const StatusBadge('Ready for review'),
                      const Divider(height: 28),
                      const Text(
                        'Photos, pricing, availability, location, terms and verification are complete.',
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              RentHubActionButton(
                label: 'Publish for Moderation',
                onPressed: () async {
                  if (await confirmAction(
                        context,
                        title: 'Submit listing for review?',
                        message:
                            'The listing will remain Pending Review until moderation is complete.',
                        action: 'Submit',
                      ) &&
                      context.mounted) {
                    showMockSuccess(context, 'Listing submitted for review');
                    Navigator.pop(context);
                  }
                },
              ),
            ],
          ),
        ),
      );
}

class OwnerItemVerificationPage extends StatefulWidget {
  const OwnerItemVerificationPage({super.key});
  @override
  State<OwnerItemVerificationPage> createState() =>
      _OwnerItemVerificationPageState();
}

class _OwnerItemVerificationPageState extends State<OwnerItemVerificationPage> {
  bool photosAdded = false;

  @override
  Widget build(BuildContext context) => _OwnerFlowPage(
        title: 'Photos & Item Verification',
        heading: 'Verify the physical item',
        status: photosAdded ? 'Eligible' : 'Evidence required',
        children: [
          const Text(
            'Add front, back, serial-number and accessory placeholders. Files remain local to this prototype.',
            style: TextStyle(color: AppColors.secondaryText),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () => setState(() => photosAdded = true),
            icon: const Icon(Icons.add_a_photo_outlined),
            label: const Text('Add Verification Photos'),
          ),
          const SizedBox(height: 12),
          RentHubActionButton(
            label: 'Run Mock Verification',
            onPressed: photosAdded
                ? () => showMockSuccess(
                      context,
                      'Mock verification passed with 96% confidence',
                    )
                : null,
          ),
        ],
      );
}

class OwnerAvailabilityPage extends StatefulWidget {
  const OwnerAvailabilityPage({super.key});
  @override
  State<OwnerAvailabilityPage> createState() => _OwnerAvailabilityPageState();
}

class _OwnerAvailabilityPageState extends State<OwnerAvailabilityPage> {
  bool instant = false;
  bool delivery = true;

  @override
  Widget build(BuildContext context) => _OwnerFlowPage(
        title: 'Smart Pricing & Availability',
        heading: 'RM 85.00 / day',
        status: 'Suggested RM 80–140',
        children: [
          const TextField(
            decoration: InputDecoration(
              labelText: 'Daily price (RM)',
              helperText: 'Smart-price estimate from similar local listings',
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () =>
                showMockSuccess(context, 'Unavailable dates selected'),
            icon: const Icon(Icons.event_busy_outlined),
            label: const Text('Block Dates'),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Allow instant requests'),
            value: instant,
            onChanged: (value) => setState(() => instant = value),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Offer Owner delivery'),
            value: delivery,
            onChanged: (value) => setState(() => delivery = value),
          ),
          RentHubActionButton(
            label: 'Save Availability',
            onPressed: () {
              showMockSuccess(context, 'Pricing and availability saved');
              Navigator.pop(context);
            },
          ),
        ],
      );
}

class OwnerRequestDetailsPage extends StatefulWidget {
  const OwnerRequestDetailsPage({
    super.key,
    required this.listing,
    required this.initialStatus,
  });
  final Listing listing;
  final String initialStatus;

  @override
  State<OwnerRequestDetailsPage> createState() =>
      _OwnerRequestDetailsPageState();
}

class _OwnerRequestDetailsPageState extends State<OwnerRequestDetailsPage> {
  late String status = widget.initialStatus;

  Future<void> _approve() async {
    if (await confirmAction(
          context,
          title: 'Approve booking request?',
          message:
              'The renter will be notified. This moves the request to Approved, not Paid.',
          action: 'Approve',
        ) &&
        mounted) {
      Navigator.pop(context, 'Approved');
    }
  }

  Future<void> _reject() async {
    final reason = TextEditingController();
    final accepted = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Reject booking request?'),
            content: TextField(
              controller: reason,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Reason required',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Back'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: AppColors.error),
                onPressed: () => Navigator.pop(
                  dialogContext,
                  reason.text.trim().length >= 5,
                ),
                child: const Text('Reject'),
              ),
            ],
          ),
        ) ??
        false;
    reason.dispose();
    if (accepted && mounted) Navigator.pop(context, 'Rejected');
  }

  @override
  Widget build(BuildContext context) => _OwnerFlowPage(
        title: 'Booking Request Details',
        heading: widget.listing.title,
        status: status,
        children: [
          const _OwnerDetailRow('Renter', 'Aina Rahman • Verified • Trust 98'),
          const _OwnerDetailRow('Dates', '18–20 Aug 2026 • 3 days'),
          _OwnerDetailRow('Request total',
              'RM ${(widget.listing.dailyPrice * 3 + 300).toStringAsFixed(2)}'),
          _OwnerDetailRow(
            widget.listing.isService ? 'Requirements' : 'Fulfilment',
            widget.listing.isService
                ? 'Corporate event • 50 guests'
                : 'Self pickup • Petaling Jaya',
          ),
          const SizedBox(height: 16),
          if (status == 'Pending') ...[
            Row(children: [
              Expanded(
                child: RentHubActionButton(
                  label: 'Reject',
                  style: RentHubButtonStyle.destructive,
                  onPressed: _reject,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: RentHubActionButton(
                  label: 'Approve',
                  onPressed: _approve,
                ),
              ),
            ]),
          ],
        ],
      );
}

class OwnerActiveRentalsPage extends StatelessWidget {
  const OwnerActiveRentalsPage({super.key, this.embedded = false});
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final content = ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        for (final entry in const [
          ('Sony Alpha A7 III Camera', 'Return due in 2 days', 'Active'),
          ('Makita Cordless Drill Set', 'Pickup today, 2:00 PM', 'Handover'),
          ('Perodua Myvi 2022', 'Overdue by 4 hours', 'Late'),
        ]) ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(children: [
                    const CircleAvatar(
                      backgroundColor: AppColors.primaryLight,
                      child: Icon(Icons.inventory_2_outlined),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(entry.$1,
                              style: Theme.of(context).textTheme.titleMedium),
                          Text(entry.$2,
                              style: const TextStyle(
                                  color: AppColors.secondaryText)),
                        ],
                      ),
                    ),
                    StatusBadge(entry.$3),
                  ]),
                  const SizedBox(height: 12),
                  RentHubActionButton(
                    label: 'Manage Rental',
                    style: entry.$3 == 'Late'
                        ? RentHubButtonStyle.destructive
                        : RentHubButtonStyle.primary,
                    onPressed: () => Navigator.push<void>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => OwnerRentalDetailsPage(
                          title: entry.$1,
                          status: entry.$3,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
    if (embedded) return content;
    return Scaffold(
      appBar: AppBar(title: const Text('Active Rentals')),
      body: SafeArea(child: content),
    );
  }
}

class OwnerRentalDetailsPage extends StatelessWidget {
  const OwnerRentalDetailsPage({
    super.key,
    required this.title,
    required this.status,
  });
  final String title;
  final String status;

  @override
  Widget build(BuildContext context) => _OwnerFlowPage(
        title: 'Active Rental Details',
        heading: title,
        status: status,
        children: [
          const _OwnerDetailRow('Renter', 'Aina Rahman • Verified'),
          const _OwnerDetailRow('Return due', '24 Aug 2026 • 6:00 PM'),
          const _OwnerDetailRow('Deposit', 'RM 300.00 protected'),
          const SizedBox(height: 16),
          RentHubActionButton(
            label: 'Confirm Item Handover',
            onPressed: () async {
              if (await confirmAction(
                    context,
                    title: 'Confirm handover?',
                    message:
                        'Record the item condition and handover code before confirming.',
                    action: 'Mark Handed Over',
                  ) &&
                  context.mounted) {
                showMockSuccess(context, 'Handover recorded');
              }
            },
          ),
          const SizedBox(height: 8),
          RentHubActionButton(
            label: 'Review Extension Request',
            style: RentHubButtonStyle.secondary,
            onPressed: () => Navigator.push<void>(
              context,
              MaterialPageRoute(
                builder: (_) => OwnerExtensionReviewPage(title: title),
              ),
            ),
          ),
          const SizedBox(height: 8),
          RentHubActionButton(
            label: 'Verify Return',
            style: RentHubButtonStyle.outline,
            onPressed: () => Navigator.push<void>(
              context,
              MaterialPageRoute(
                builder: (_) => OwnerReturnVerificationPage(title: title),
              ),
            ),
          ),
          const SizedBox(height: 8),
          RentHubActionButton(
            label: 'Late / Damaged Item',
            style: RentHubButtonStyle.destructive,
            onPressed: () => Navigator.push<void>(
              context,
              MaterialPageRoute(
                builder: (_) => OwnerIssuePage(title: title),
              ),
            ),
          ),
        ],
      );
}

class OwnerExtensionReviewPage extends StatelessWidget {
  const OwnerExtensionReviewPage({super.key, required this.title});
  final String title;
  @override
  Widget build(BuildContext context) => _OwnerFlowPage(
        title: 'Extension Review',
        heading: title,
        status: 'Pending decision',
        children: [
          const _OwnerDetailRow('Requested', '2 additional days'),
          const _OwnerDetailRow('Additional amount', 'RM 170.00'),
          Row(children: [
            Expanded(
              child: RentHubActionButton(
                label: 'Reject',
                style: RentHubButtonStyle.destructive,
                onPressed: () => showMockSuccess(
                  context,
                  'Extension rejected with Owner reason',
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: RentHubActionButton(
                label: 'Approve',
                onPressed: () => showMockSuccess(context, 'Extension approved'),
              ),
            ),
          ]),
        ],
      );
}

class OwnerReturnVerificationPage extends StatefulWidget {
  const OwnerReturnVerificationPage({super.key, required this.title});
  final String title;
  @override
  State<OwnerReturnVerificationPage> createState() =>
      _OwnerReturnVerificationPageState();
}

class _OwnerReturnVerificationPageState
    extends State<OwnerReturnVerificationPage> {
  String condition = 'Matches handover condition';
  @override
  Widget build(BuildContext context) => _OwnerFlowPage(
        title: 'Return Verification',
        heading: widget.title,
        status: 'Evidence submitted',
        children: [
          const Text('Renter return photos: 3 local placeholders'),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: condition,
            decoration: const InputDecoration(labelText: 'Returned condition'),
            items: const [
              'Matches handover condition',
              'Minor wear',
              'Damaged',
              'Accessories missing',
            ]
                .map((value) =>
                    DropdownMenuItem(value: value, child: Text(value)))
                .toList(),
            onChanged: (value) =>
                setState(() => condition = value ?? condition),
          ),
          const SizedBox(height: 16),
          RentHubActionButton(
            label: condition == 'Matches handover condition'
                ? 'Confirm Return & Release Deposit'
                : 'Continue to Damage Handling',
            onPressed: () {
              if (condition == 'Matches handover condition') {
                showMockSuccess(context, 'Return verified; deposit released');
              } else {
                Navigator.push<void>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => OwnerIssuePage(title: widget.title),
                  ),
                );
              }
            },
          ),
        ],
      );
}

class OwnerIssuePage extends StatelessWidget {
  const OwnerIssuePage({super.key, required this.title});
  final String title;
  @override
  Widget build(BuildContext context) => _OwnerFlowPage(
        title: 'Late or Damaged Item',
        heading: title,
        status: 'Action required',
        children: [
          const TextField(
            minLines: 3,
            maxLines: 5,
            decoration: InputDecoration(
              labelText: 'Describe the issue',
              hintText: 'Damage, missing parts, late return and estimated cost',
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: null,
            icon: Icon(Icons.add_a_photo_outlined),
            label: Text('Evidence placeholders attached'),
          ),
          const SizedBox(height: 12),
          RentHubActionButton(
            label: 'Start Insurance Claim',
            onPressed: () => Navigator.push<void>(
              context,
              MaterialPageRoute(
                builder: (_) => OwnerInsuranceClaimPage(title: title),
              ),
            ),
          ),
          const SizedBox(height: 8),
          RentHubActionButton(
            label: 'Open Dispute Resolution',
            style: RentHubButtonStyle.destructive,
            onPressed: () => Navigator.push<void>(
              context,
              MaterialPageRoute(
                builder: (_) => OwnerDisputeResolutionPage(title: title),
              ),
            ),
          ),
        ],
      );
}

class OwnerInsuranceClaimPage extends StatefulWidget {
  const OwnerInsuranceClaimPage({super.key, required this.title});
  final String title;
  @override
  State<OwnerInsuranceClaimPage> createState() =>
      _OwnerInsuranceClaimPageState();
}

class _OwnerInsuranceClaimPageState extends State<OwnerInsuranceClaimPage> {
  final formKey = GlobalKey<FormState>();
  @override
  Widget build(BuildContext context) => _OwnerFlowPage(
        title: 'Insurance Claim',
        heading: widget.title,
        status: 'Draft',
        children: [
          Form(
            key: formKey,
            child: Column(children: [
              TextFormField(
                decoration:
                    const InputDecoration(labelText: 'Claim amount (RM)'),
                keyboardType: TextInputType.number,
                validator: (value) => (double.tryParse(value ?? '') ?? 0) > 0
                    ? null
                    : 'Enter a valid amount',
              ),
              const SizedBox(height: 12),
              TextFormField(
                minLines: 3,
                maxLines: 5,
                decoration:
                    const InputDecoration(labelText: 'Incident details'),
                validator: (value) => (value?.trim().length ?? 0) >= 10
                    ? null
                    : 'Add at least 10 characters',
              ),
            ]),
          ),
          const SizedBox(height: 16),
          RentHubActionButton(
            label: 'Submit Mock Claim',
            onPressed: () {
              if (!formKey.currentState!.validate()) return;
              showMockSuccess(context, 'Insurance claim submitted for review');
              Navigator.pop(context);
            },
          ),
        ],
      );
}

class OwnerDisputeResolutionPage extends StatelessWidget {
  const OwnerDisputeResolutionPage({super.key, required this.title});
  final String title;
  @override
  Widget build(BuildContext context) => _OwnerFlowPage(
        title: 'Dispute Resolution',
        heading: title,
        status: 'Open',
        children: [
          const Text(
            'Review renter evidence, add an Owner response, and propose a resolution for administrator review.',
            style: TextStyle(color: AppColors.secondaryText),
          ),
          const SizedBox(height: 12),
          const TextField(
            minLines: 4,
            maxLines: 6,
            decoration: InputDecoration(labelText: 'Owner response'),
          ),
          const SizedBox(height: 12),
          RentHubActionButton(
            label: 'Submit Response & Evidence',
            onPressed: () =>
                showMockSuccess(context, 'Dispute response submitted'),
          ),
        ],
      );
}

class OwnerEarningsPage extends StatelessWidget {
  const OwnerEarningsPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Earnings & History')),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                color: AppColors.primaryDark,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Available prototype balance',
                          style: TextStyle(color: Colors.white70)),
                      Text('RM 3,240.00',
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(color: Colors.white)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              for (final entry in const [
                ('Sony Alpha A7 III Camera', '+ RM 228.00', 'Successful'),
                ('Perodua Myvi 2022', '+ RM 420.00', 'Pending'),
                ('Photography Package', '+ RM 617.50', 'Successful'),
              ])
                Card(
                  child: ListTile(
                    title: Text(entry.$1),
                    subtitle: Text(entry.$3),
                    trailing: Text(entry.$2,
                        style: const TextStyle(
                            color: AppColors.success,
                            fontWeight: FontWeight.w700)),
                  ),
                ),
              const SizedBox(height: 12),
              RentHubActionButton(
                label: 'Owner Reviews',
                style: RentHubButtonStyle.secondary,
                onPressed: () => Navigator.push<void>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const OwnerReviewsPage(),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
}

class OwnerReviewsPage extends StatelessWidget {
  const OwnerReviewsPage({super.key});
  @override
  Widget build(BuildContext context) => _OwnerFlowPage(
        title: 'Reviews',
        heading: 'Owner rating 4.9',
        status: '128 reviews',
        children: [
          const Text('★★★★★ Professional and responsive Owner.'),
          const Divider(height: 28),
          const Text('★★★★★ Item matched the description and was clean.'),
          const SizedBox(height: 16),
          RentHubActionButton(
            label: 'Review Renter',
            onPressed: () => Navigator.push<void>(
              context,
              MaterialPageRoute(
                builder: (_) => const ReviewSubmissionPage(
                  subject: 'Completed camera rental',
                  ownerName: 'Aina Rahman',
                ),
              ),
            ),
          ),
        ],
      );
}

class _OwnerFlowPage extends StatelessWidget {
  const _OwnerFlowPage({
    required this.title,
    required this.heading,
    required this.status,
    required this.children,
  });
  final String title;
  final String heading;
  final String status;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(children: [
                    const CircleAvatar(
                      backgroundColor: AppColors.primaryLight,
                      child: Icon(Icons.storefront_outlined),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(heading,
                          style: Theme.of(context).textTheme.titleMedium),
                    ),
                    StatusBadge(status),
                  ]),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: children,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
}

class _OwnerDetailRow extends StatelessWidget {
  const _OwnerDetailRow(this.label, this.value);
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 112,
              child: Text(label,
                  style: const TextStyle(color: AppColors.secondaryText)),
            ),
            Expanded(
              child: Text(value,
                  textAlign: TextAlign.end,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      );
}

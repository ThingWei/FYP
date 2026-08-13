import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/mock_data/mock_data.dart';
import '../../shared/models/domain_models.dart';
import '../../shared/widgets/renthub_components.dart';

class RenterShell extends StatefulWidget {
  const RenterShell(
      {super.key, required this.onSwitchRole, required this.canSwitch});
  final VoidCallback onSwitchRole;
  final bool canSwitch;
  @override
  State<RenterShell> createState() => _RenterShellState();
}

class _RenterShellState extends State<RenterShell> {
  int index = 0;
  @override
  Widget build(BuildContext context) {
    final pages = [
      const RenterHome(),
      const ExplorePage(),
      const BookingsPage(),
      const MessagesPage(),
      ProfilePage(
          role: 'Renter',
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
                  icon: Icon(Icons.home_outlined),
                  selectedIcon: Icon(Icons.home),
                  label: 'Home'),
              NavigationDestination(icon: Icon(Icons.search), label: 'Explore'),
              NavigationDestination(
                  icon: Icon(Icons.calendar_month_outlined), label: 'Bookings'),
              NavigationDestination(
                  icon: Icon(Icons.chat_bubble_outline), label: 'Messages'),
              NavigationDestination(
                  icon: Icon(Icons.person_outline), label: 'Profile')
            ]));
  }
}

class RenterHome extends StatelessWidget {
  const RenterHome({super.key});
  @override
  Widget build(BuildContext context) => SafeArea(
          child: CustomScrollView(slivers: [
        SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            sliver: SliverToBoxAdapter(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Row(children: [
                    const RentHubLogo(),
                    const Spacer(),
                    IconButton(
                        tooltip: 'Wishlist',
                        onPressed: () =>
                            showMockSuccess(context, 'Wishlist opened'),
                        icon: const Icon(Icons.favorite_border)),
                    IconButton(
                        tooltip: 'Notifications',
                        onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const NotificationsPage())),
                        icon: const Badge(
                            child: Icon(Icons.notifications_outlined)))
                  ]),
                  const SizedBox(height: 24),
                  Text('Find what you need,\nright when you need it.',
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 16),
                  TextField(
                      readOnly: true,
                      onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const ExplorePage())),
                      decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search),
                          hintText: 'Search cameras, cars, services...',
                          suffixIcon: Icon(Icons.tune)))
                ]))),
        SliverToBoxAdapter(child: _Categories()),
        SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverToBoxAdapter(
                child: Row(children: [
              Text('Recommended near you',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800)),
              const Spacer(),
              TextButton(
                  onPressed: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const ExplorePage())),
                  child: const Text('See all'))
            ]))),
        SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            sliver: SliverGrid(
                delegate: SliverChildBuilderDelegate(
                    (context, i) => ListingCard(
                        listing: MockData.listings[i],
                        onTap: () =>
                            _openListing(context, MockData.listings[i])),
                    childCount: 4),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: .66)))
      ]));
}

class _Categories extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    const data = [
      ('Electronics', Icons.devices),
      ('Vehicles', Icons.directions_car),
      ('Services', Icons.design_services),
      ('Outdoor', Icons.terrain_outlined)
    ];
    return SizedBox(
        height: 112,
        child: ListView.separated(
            padding: const EdgeInsets.all(16),
            scrollDirection: Axis.horizontal,
            itemCount: data.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, i) => InkWell(
                onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => ExplorePage(initialQuery: data[i].$1))),
                child: SizedBox(
                    width: 72,
                    child: Column(children: [
                      CircleAvatar(
                          radius: 28,
                          backgroundColor: AppColors.primaryLight,
                          child: Icon(data[i].$2, color: AppColors.primary)),
                      const SizedBox(height: 6),
                      Text(data[i].$1,
                          style: const TextStyle(fontSize: 12),
                          textAlign: TextAlign.center)
                    ])))));
  }
}

class ExplorePage extends StatefulWidget {
  const ExplorePage({super.key, this.initialQuery});
  final String? initialQuery;
  @override
  State<ExplorePage> createState() => _ExplorePageState();
}

class _ExplorePageState extends State<ExplorePage> {
  String query = '';
  bool verified = false;
  @override
  void initState() {
    super.initState();
    query = widget.initialQuery ?? '';
  }

  @override
  Widget build(BuildContext context) {
    final items = MockData.listings
        .where((e) =>
            (e.title + e.category)
                .toLowerCase()
                .contains(query.toLowerCase()) &&
            (!verified || e.verified))
        .toList();
    return Scaffold(
        appBar: AppBar(title: const Text('Explore')),
        body: SafeArea(
            child: Column(children: [
          Padding(
              padding: const EdgeInsets.all(16),
              child: TextFormField(
                  initialValue: query,
                  onChanged: (v) => setState(() => query = v),
                  decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText: 'Search RentHub',
                      suffixIcon: IconButton(
                          icon: const Icon(Icons.tune),
                          onPressed: () => showModalBottomSheet(
                              context: context,
                              showDragHandle: true,
                              builder: (_) => Padding(
                                  padding: const EdgeInsets.all(24),
                                  child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        Text('Filters',
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleLarge),
                                        SwitchListTile(
                                            contentPadding: EdgeInsets.zero,
                                            title: const Text(
                                                'Verified Owners only'),
                                            value: verified,
                                            onChanged: (v) {
                                              setState(() => verified = v);
                                              Navigator.pop(context);
                                            }),
                                        const Text('Type'),
                                        const Wrap(spacing: 8, children: [
                                          FilterChip(
                                              label: Text('Physical items'),
                                              selected: true,
                                              onSelected: null),
                                          FilterChip(
                                              label: Text('Services'),
                                              selected: false,
                                              onSelected: null)
                                        ]),
                                        const SizedBox(height: 12),
                                        FilledButton(
                                            onPressed: () =>
                                                Navigator.pop(context),
                                            child: const Text('Show results'))
                                      ]))))))),
          Expanded(
              child: items.isEmpty
                  ? const Center(
                      child: Text('No listings match these filters.'))
                  : GridView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 230,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                              childAspectRatio: .67),
                      itemCount: items.length,
                      itemBuilder: (context, i) => ListingCard(
                          listing: items[i],
                          onTap: () => _openListing(context, items[i]))))
        ])));
  }
}

void _openListing(BuildContext context, Listing listing) => Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => ListingDetailsPage(listing: listing)));

class ListingDetailsPage extends StatelessWidget {
  const ListingDetailsPage({super.key, required this.listing});
  final Listing listing;
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(actions: [
        IconButton(
            onPressed: () => showMockSuccess(context, 'Added to wishlist'),
            icon: const Icon(Icons.favorite_border)),
        PopupMenuButton(
            itemBuilder: (_) => const [
                  PopupMenuItem(value: 'report', child: Text('Report listing')),
                  PopupMenuItem(value: 'block', child: Text('Block Owner'))
                ],
            onSelected: (v) => confirmAction(context,
                title: v == 'block' ? 'Block Owner?' : 'Report listing?',
                message: 'This mock action can be reversed from Settings.',
                action: 'Continue',
                destructive: true))
      ]),
      bottomNavigationBar: SafeArea(
          child: Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton(
                  onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => BookingFlowPage(listing: listing))),
                  child: Text(listing.isService
                      ? 'Book service'
                      : 'Check availability')))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        AspectRatio(
            aspectRatio: 16 / 10,
            child: Container(
                decoration: BoxDecoration(
                    color: AppColors.primaryLight,
                    borderRadius: BorderRadius.circular(16)),
                child: Icon(
                    listing.isService
                        ? Icons.design_services
                        : Icons.inventory_2,
                    size: 72,
                    color: AppColors.primary))),
        const SizedBox(height: 20),
        Row(children: [
          Expanded(
              child: Text(listing.title,
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w800))),
          if (listing.verified)
            const Icon(Icons.verified, color: AppColors.primary)
        ]),
        const SizedBox(height: 8),
        Text('${listing.location}  •  ★ ${listing.rating} (48 reviews)',
            style: const TextStyle(color: AppColors.secondaryText)),
        const SizedBox(height: 16),
        Text(
            'RM ${listing.dailyPrice.toStringAsFixed(2)} ${listing.isService ? '/ package' : '/ day'}',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: AppColors.primaryDark, fontWeight: FontWeight.w800)),
        const Divider(height: 32),
        ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const CircleAvatar(child: Icon(Icons.person)),
            title: Text(listing.ownerName),
            subtitle: const Text('Verified Owner • Trust score 4.9'),
            trailing: const Icon(Icons.chevron_right)),
        const Divider(),
        Text(listing.isService ? 'Package details' : 'Item details',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Text(listing.isService
            ? 'Includes consultation, professional delivery and edited digital files. Choose a service date, duration and venue during booking.'
            : 'Condition: ${listing.condition}\nSecurity deposit: RM 200.00\nItem verified • Damage waiver available\nCollection or delivery available.'),
        const SizedBox(height: 20),
        Text('What renters say',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w800)),
        const Card(
            child: Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                    '★★★★★  “Easy arrangement and exactly as described.”\n— Aina, Petaling Jaya')))
      ]));
}

class BookingFlowPage extends StatefulWidget {
  const BookingFlowPage({super.key, required this.listing});
  final Listing listing;
  @override
  State<BookingFlowPage> createState() => _BookingFlowPageState();
}

class _BookingFlowPageState extends State<BookingFlowPage> {
  int step = 0;
  String fulfilment = 'Collection';
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(
          title: Text(
              widget.listing.isService ? 'Schedule service' : 'Book item')),
      body: Stepper(
          currentStep: step,
          onStepContinue: () {
            if (step < 2) {
              setState(() => step++);
            } else {
              Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                      builder: (_) =>
                          PaymentResultPage(listing: widget.listing)));
            }
          },
          onStepCancel: step == 0 ? null : () => setState(() => step--),
          controlsBuilder: (context, d) => Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Row(children: [
                Expanded(
                    child: FilledButton(
                        onPressed: d.onStepContinue,
                        child: Text(step == 2 ? 'Pay securely' : 'Continue'))),
                if (step > 0) ...[
                  const SizedBox(width: 8),
                  TextButton(
                      onPressed: d.onStepCancel, child: const Text('Back'))
                ]
              ])),
          steps: [
            StepperStep(
                title: Text(widget.listing.isService
                    ? 'Date, duration & venue'
                    : 'Rental dates'),
                content: const Column(children: [
                  TextField(
                      readOnly: true,
                      decoration: InputDecoration(
                          labelText: 'Start date',
                          suffixIcon: Icon(Icons.calendar_today))),
                  SizedBox(height: 12),
                  TextField(
                      readOnly: true,
                      decoration: InputDecoration(
                          labelText: 'End date / duration',
                          suffixIcon: Icon(Icons.schedule)))
                ])),
            if (!widget.listing.isService)
              StepperStep(
                  title: const Text('Fulfilment'),
                  content: DropdownButtonFormField(
                      initialValue: fulfilment,
                      items: ['Collection', 'Owner delivery']
                          .map(
                              (e) => DropdownMenuItem(value: e, child: Text(e)))
                          .toList(),
                      onChanged: (v) => setState(() => fulfilment = v!))),
            StepperStep(
                title: const Text('Review & payment'),
                content: Card(
                    child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(children: [
                          _PriceRow('Booking', widget.listing.dailyPrice),
                          const _PriceRow('Service fee', 12),
                          if (!widget.listing.isService)
                            const _PriceRow('Refundable deposit', 200),
                          const Divider(),
                          _PriceRow(
                              'Total',
                              widget.listing.dailyPrice +
                                  12 +
                                  (widget.listing.isService ? 0 : 200),
                              bold: true)
                        ]))))
          ]));
}

class StepperStep extends Step {
  const StepperStep({required super.title, required super.content})
      : super(isActive: true);
}

class _PriceRow extends StatelessWidget {
  const _PriceRow(this.label, this.value, {this.bold = false});
  final String label;
  final double value;
  final bool bold;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        Expanded(
            child: Text(label,
                style: TextStyle(fontWeight: bold ? FontWeight.bold : null))),
        Text('RM ${value.toStringAsFixed(2)}',
            style: TextStyle(fontWeight: bold ? FontWeight.bold : null))
      ]));
}

class PaymentResultPage extends StatelessWidget {
  const PaymentResultPage({super.key, required this.listing});
  final Listing listing;
  @override
  Widget build(BuildContext context) => Scaffold(
      body: SafeArea(
          child: Center(
              child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.check_circle,
                        color: AppColors.success, size: 80),
                    const SizedBox(height: 16),
                    Text('Payment successful',
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    Text(
                        'Your request for ${listing.title} was sent to the Owner.',
                        textAlign: TextAlign.center),
                    const SizedBox(height: 24),
                    FilledButton(
                        onPressed: () =>
                            Navigator.popUntil(context, (r) => r.isFirst),
                        child: const Text('Back to home'))
                  ])))));
}

class BookingsPage extends StatelessWidget {
  const BookingsPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('My bookings')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        for (int i = 0; i < 4; i++)
          Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Card(
                  child: ListTile(
                      contentPadding: const EdgeInsets.all(12),
                      leading: const CircleAvatar(
                          backgroundColor: AppColors.primaryLight,
                          child: Icon(Icons.inventory_2_outlined)),
                      title: Text(MockData.listings[i].title),
                      subtitle: Text(i == 2
                          ? 'Service date: 24 Aug 2026'
                          : '18–20 Aug 2026'),
                      trailing: StatusBadge(MockData.bookingStatuses[i + 1]),
                      onTap: () => showModalBottomSheet(
                          context: context,
                          showDragHandle: true,
                          builder: (_) => Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Text(
                                        MockData.listings[i].isService
                                            ? 'Service order'
                                            : 'Rental tracking',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleLarge),
                                    const SizedBox(height: 12),
                                    Text(MockData.listings[i].isService
                                        ? 'Confirm completion after the Owner delivers the service.'
                                        : 'Approved → Handover → In use → Return'),
                                    const SizedBox(height: 16),
                                    FilledButton(
                                        onPressed: () => showMockSuccess(
                                            context,
                                            MockData.listings[i].isService
                                                ? 'Service completion confirmed'
                                                : 'Extension request sent'),
                                        child: Text(
                                            MockData.listings[i].isService
                                                ? 'Confirm completion'
                                                : 'Request extension')),
                                    OutlinedButton(
                                        onPressed: () => showMockSuccess(
                                            context, 'Dispute form opened'),
                                        child: const Text('Report an issue'))
                                  ]))))))
      ]));
}

class MessagesPage extends StatelessWidget {
  const MessagesPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Messages')),
      body: ListView(children: [
        for (final l in MockData.listings.take(3))
          ListTile(
              leading: CircleAvatar(child: Text(l.ownerName[0])),
              title: Text(l.ownerName),
              subtitle: const Text('Yes, the selected date is available.'),
              trailing: const Text('10:24'),
              onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => ChatPage(name: l.ownerName))))
      ]));
}

class ChatPage extends StatelessWidget {
  const ChatPage({super.key, required this.name});
  final String name;
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: Text(name)),
      body: Column(children: [
        const Expanded(
            child: Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Align(
                          alignment: Alignment.centerLeft,
                          child: Chip(
                              label: Text('Hi! The listing is available.'))),
                      Align(
                          alignment: Alignment.centerRight,
                          child: Chip(
                              backgroundColor: AppColors.primaryLight,
                              label: Text('Great, I’ll make a booking.')))
                    ]))),
        const SafeArea(
            child: Padding(
                padding: EdgeInsets.all(12),
                child: TextField(
                    decoration: InputDecoration(
                        hintText: 'Write a message',
                        suffixIcon: Icon(Icons.send)))))
      ]));
}

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});
  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  final items = [...MockData.notifications];
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Notifications'), actions: [
        TextButton(
            onPressed: () => setState(items.clear),
            child: const Text('Clear all'))
      ]),
      body: items.isEmpty
          ? const Center(child: Text('You’re all caught up.'))
          : ListView.builder(
              itemCount: items.length,
              itemBuilder: (_, i) => Dismissible(
                  key: ValueKey(items[i]),
                  onDismissed: (_) => setState(() => items.removeAt(i)),
                  child: ListTile(
                      leading: const CircleAvatar(
                          child: Icon(Icons.notifications_outlined)),
                      title: Text(items[i]),
                      subtitle: const Text('Today')))));
}

class ProfilePage extends StatelessWidget {
  const ProfilePage(
      {super.key,
      required this.role,
      required this.canSwitch,
      required this.onSwitch});
  final String role;
  final bool canSwitch;
  final VoidCallback onSwitch;
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const CircleAvatar(radius: 38, child: Text('NI')),
        const SizedBox(height: 12),
        const Center(
            child: Text('Nur Izzati',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800))),
        Center(
            child: Text('$role • Verified identity • Trust 4.7',
                style: const TextStyle(color: AppColors.secondaryText))),
        const SizedBox(height: 24),
        if (canSwitch)
          Card(
              child: ListTile(
                  leading: const Icon(Icons.swap_horiz),
                  title: Text(
                      'Switch to ${role == 'Renter' ? 'Owner' : 'Renter'}'),
                  onTap: onSwitch)),
        for (final item in const [
          ('Edit profile', Icons.edit_outlined),
          ('Identity verification', Icons.verified_user_outlined),
          ('Loyalty & referrals', Icons.card_giftcard),
          ('Settings', Icons.settings_outlined),
          ('Help & support', Icons.help_outline)
        ])
          Card(
              child: ListTile(
                  leading: Icon(item.$2),
                  title: Text(item.$1),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => showMockSuccess(context, '${item.$1} opened')))
      ]));
}

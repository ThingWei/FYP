import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/widgets/account_components.dart';
import '../../shared/widgets/renthub_components.dart';
import '../renter/discovery/controllers/renter_prototype_state.dart';

class HelpSupportPage extends StatelessWidget {
  const HelpSupportPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Help & Support')),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              const AccountCard(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      backgroundColor: AppColors.primaryLight,
                      child: Icon(Icons.support_agent,
                          color: AppColors.primaryDark),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('RentHub Support',
                              style: TextStyle(fontWeight: FontWeight.w700)),
                          SizedBox(height: 4),
                          Text(
                            'Prototype support hours: Monday to Friday, 9:00 AM to 6:00 PM MYT.',
                            style: TextStyle(color: AppColors.secondaryText),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text('Frequently asked questions',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              const Card(
                child: Column(
                  children: [
                    ExpansionTile(
                      title: Text('When is a booking created?'),
                      childrenPadding: EdgeInsets.fromLTRB(16, 0, 16, 16),
                      children: [
                        Text(
                          'A physical-item request is created only after the simulated authorization succeeds.',
                        ),
                      ],
                    ),
                    Divider(height: 1),
                    ExpansionTile(
                      title: Text('How does the refundable deposit work?'),
                      childrenPadding: EdgeInsets.fromLTRB(16, 0, 16, 16),
                      children: [
                        Text(
                          'The prototype displays deposit authorization and release decisions without moving real money.',
                        ),
                      ],
                    ),
                    Divider(height: 1),
                    ExpansionTile(
                      title: Text('How do I report a rental problem?'),
                      childrenPadding: EdgeInsets.fromLTRB(16, 0, 16, 16),
                      children: [
                        Text(
                          'Open the relevant booking, choose Raise Dispute, describe the issue and add evidence placeholders.',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              RentHubActionButton(
                label: 'Submit Support Request',
                icon: Icons.edit_note_outlined,
                onPressed: () => Navigator.push<void>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const SupportRequestPage(),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              RentHubActionButton(
                label: 'Call Prototype Support',
                icon: Icons.call_outlined,
                style: RentHubButtonStyle.outline,
                onPressed: () => showMockSuccess(
                  context,
                  'Support number: +60 3-8899 2026',
                ),
              ),
            ],
          ),
        ),
      );
}

class SupportRequestPage extends StatefulWidget {
  const SupportRequestPage({super.key});

  @override
  State<SupportRequestPage> createState() => _SupportRequestPageState();
}

class _SupportRequestPageState extends State<SupportRequestPage> {
  final formKey = GlobalKey<FormState>();
  final details = TextEditingController();
  String topic = 'Booking help';
  bool submitted = false;

  @override
  void dispose() {
    details.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Support Request')),
        body: SafeArea(
          child: submitted
              ? RentHubFeedbackState(
                  kind: FeedbackKind.success,
                  title: 'Request submitted',
                  message:
                      'Ticket RH-SUP-2026-00418 was created locally. Prototype support will respond in Messages.',
                  actionLabel: 'Done',
                  onAction: () => Navigator.pop(context),
                )
              : Form(
                  key: formKey,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    children: [
                      DropdownButtonFormField<String>(
                        initialValue: topic,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Topic'),
                        items: const [
                          'Booking help',
                          'Payment authorization',
                          'Identity verification',
                          'Safety concern',
                          'Other',
                        ]
                            .map((value) => DropdownMenuItem(
                                  value: value,
                                  child: Text(value),
                                ))
                            .toList(),
                        onChanged: (value) => topic = value ?? topic,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: details,
                        minLines: 5,
                        maxLines: 8,
                        decoration: const InputDecoration(
                          labelText: 'How can we help?',
                          alignLabelWithHint: true,
                        ),
                        validator: (value) => (value?.trim().length ?? 0) < 10
                            ? 'Enter at least 10 characters'
                            : null,
                      ),
                      const SizedBox(height: 16),
                      RentHubActionButton(
                        label: 'Submit Request',
                        onPressed: () {
                          if (formKey.currentState!.validate()) {
                            setState(() => submitted = true);
                          }
                        },
                      ),
                    ],
                  ),
                ),
        ),
      );
}

class AddressManagementPage extends StatefulWidget {
  const AddressManagementPage({super.key});

  @override
  State<AddressManagementPage> createState() => _AddressManagementPageState();
}

class _AddressManagementPageState extends State<AddressManagementPage> {
  final addresses = <String>[
    '12 Jalan SS 2/72, Petaling Jaya, Selangor',
  ];
  int defaultIndex = 0;

  Future<void> _add() async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add address'),
        content: TextField(
          controller: controller,
          minLines: 2,
          maxLines: 3,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Malaysian address',
            hintText: 'Street, postcode, city and state',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final text = controller.text.trim();
              if (text.length >= 10) Navigator.pop(dialogContext, text);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value != null && mounted) setState(() => addresses.add(value));
  }

  Future<void> _remove(int index) async {
    final accepted = await confirmAction(
      context,
      title: 'Remove this address?',
      message: 'The address will be removed from this prototype session.',
      action: 'Remove',
      destructive: true,
    );
    if (!accepted || !mounted) return;
    setState(() {
      addresses.removeAt(index);
      defaultIndex = 0;
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Addresses')),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _add,
          icon: const Icon(Icons.add_location_alt_outlined),
          label: const Text('Add Address'),
        ),
        body: SafeArea(
          child: addresses.isEmpty
              ? RentHubFeedbackState(
                  kind: FeedbackKind.empty,
                  title: 'No saved addresses',
                  message: 'Add an address for delivery and service bookings.',
                  actionLabel: 'Add Address',
                  onAction: _add,
                )
              : RadioGroup<int>(
                  groupValue: defaultIndex,
                  onChanged: (value) =>
                      setState(() => defaultIndex = value ?? 0),
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                    itemCount: addresses.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) => Card(
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: RadioListTile<int>(
                          value: index,
                          title: Text(addresses[index]),
                          subtitle: Text(index == defaultIndex
                              ? 'Default address'
                              : 'Saved address'),
                          secondary: IconButton(
                            tooltip: 'Remove address',
                            onPressed: addresses.length == 1
                                ? null
                                : () => _remove(index),
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
        ),
      );
}

class PaymentMethodsPage extends StatefulWidget {
  const PaymentMethodsPage({super.key});

  @override
  State<PaymentMethodsPage> createState() => _PaymentMethodsPageState();
}

class _PaymentMethodsPageState extends State<PaymentMethodsPage> {
  final methods = <String>['Visa ending 4242'];

  Future<void> _add() async {
    final controller = TextEditingController();
    final digits = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add simulated card'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          maxLength: 4,
          decoration: const InputDecoration(
            labelText: 'Last four digits',
            helperText: 'No real card information is stored.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              if (RegExp(r'^\d{4}$').hasMatch(value)) {
                Navigator.pop(dialogContext, value);
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (digits != null && mounted) {
      setState(() => methods.add('Visa ending $digits'));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Payment Methods')),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              const Card(
                color: AppColors.blueSurface,
                child: ListTile(
                  leading: Icon(Icons.info_outline, color: AppColors.info),
                  title: Text('Prototype payment only'),
                  subtitle: Text(
                    'These methods are local placeholders. RentHub does not process or store real card details.',
                  ),
                ),
              ),
              const SizedBox(height: 8),
              for (var index = 0; index < methods.length; index++)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.credit_card),
                    title: Text(methods[index]),
                    subtitle:
                        Text(index == 0 ? 'Default method' : 'Saved method'),
                    trailing: index == 0
                        ? const StatusBadge('Default')
                        : IconButton(
                            tooltip: 'Remove payment method',
                            onPressed: () =>
                                setState(() => methods.removeAt(index)),
                            icon: const Icon(Icons.delete_outline),
                          ),
                  ),
                ),
              const SizedBox(height: 12),
              RentHubActionButton(
                label: 'Add Simulated Method',
                icon: Icons.add_card,
                style: RentHubButtonStyle.outline,
                onPressed: _add,
              ),
            ],
          ),
        ),
      );
}

class SecurityPage extends StatefulWidget {
  const SecurityPage({super.key});

  @override
  State<SecurityPage> createState() => _SecurityPageState();
}

class _SecurityPageState extends State<SecurityPage> {
  bool loginAlerts = true;

  Future<void> _changePassword() async {
    final formKey = GlobalKey<FormState>();
    final password = TextEditingController();
    final saved = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Change prototype password'),
            content: Form(
              key: formKey,
              child: TextFormField(
                controller: password,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'New password'),
                validator: (value) => (value?.length ?? 0) < 8
                    ? 'Use at least 8 characters'
                    : null,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  if (formKey.currentState!.validate()) {
                    Navigator.pop(dialogContext, true);
                  }
                },
                child: const Text('Save'),
              ),
            ],
          ),
        ) ??
        false;
    password.dispose();
    if (saved && mounted) {
      showMockSuccess(context, 'Prototype password updated');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Security')),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              AccountCard(
                child: Column(
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.password_outlined),
                      title: const Text('Password'),
                      subtitle: const Text('Last changed 30 days ago'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _changePassword,
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      secondary:
                          const Icon(Icons.notifications_active_outlined),
                      title: const Text('Login alerts'),
                      subtitle: const Text('Notify me of a new sign-in'),
                      value: loginAlerts,
                      onChanged: (value) => setState(() => loginAlerts = value),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const AccountCard(
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.phone_android_outlined),
                  title: Text('This device'),
                  subtitle: Text('Windows prototype session • Kuala Lumpur'),
                  trailing: StatusBadge('Active'),
                ),
              ),
            ],
          ),
        ),
      );
}

class BlockedOwnersPage extends StatefulWidget {
  const BlockedOwnersPage({super.key});

  @override
  State<BlockedOwnersPage> createState() => _BlockedOwnersPageState();
}

class _BlockedOwnersPageState extends State<BlockedOwnersPage> {
  Future<void> _unblock(String owner) async {
    final accepted = await confirmAction(
      context,
      title: 'Unblock $owner?',
      message: 'You will be able to view and book this Owner’s listings again.',
      action: 'Unblock',
    );
    if (!accepted) return;
    RenterPrototypeState.blockedOwners.value = {
      ...RenterPrototypeState.blockedOwners.value,
    }..remove(owner);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Blocked Owners')),
        body: SafeArea(
          child: ValueListenableBuilder<Set<String>>(
            valueListenable: RenterPrototypeState.blockedOwners,
            builder: (context, blocked, _) {
              final owners = blocked.toList()..sort();
              return owners.isEmpty
                  ? const RentHubFeedbackState(
                      kind: FeedbackKind.empty,
                      title: 'No blocked Owners',
                      message:
                          'Owners you block from a listing or profile will appear here.',
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: owners.length,
                      itemBuilder: (context, index) => Card(
                        child: ListTile(
                          leading: const CircleAvatar(
                            child: Icon(Icons.person_off_outlined),
                          ),
                          title: Text(owners[index]),
                          subtitle: const Text('Booking and messaging blocked'),
                          trailing: TextButton(
                            onPressed: () => _unblock(owners[index]),
                            child: const Text('Unblock'),
                          ),
                        ),
                      ),
                    );
            },
          ),
        ),
      );
}

class LanguagePage extends StatefulWidget {
  const LanguagePage({super.key});

  @override
  State<LanguagePage> createState() => _LanguagePageState();
}

class _LanguagePageState extends State<LanguagePage> {
  String selected = 'English (Malaysia)';

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Language')),
        body: SafeArea(
          child: RadioGroup<String>(
            groupValue: selected,
            onChanged: (value) {
              setState(() => selected = value ?? selected);
              showMockSuccess(context, '$selected selected');
            },
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                for (final language in const [
                  'English (Malaysia)',
                  'Bahasa Melayu',
                  '中文'
                ])
                  RadioListTile<String>(
                    value: language,
                    title: Text(language),
                  ),
              ],
            ),
          ),
        ),
      );
}

import '../../core/validation/input_validation.dart';
import '../../core/validation/input_rules.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/config/backend_mode.dart';
import '../../core/notifications/push_notification_service.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/account_components.dart';
import '../../shared/widgets/renthub_components.dart';
import '../live/live_renthub_controller.dart';
import '../../modules/user/controllers/auth_controller.dart';
import '../../modules/user/views/forgot_password_screen.dart';
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
                        decoration: (const InputDecoration(
                          labelText: 'How can we help?',
                          alignLabelWithHint: true,
                        )).copyWith(counterText: '', errorMaxLines: 3),
                        validator: InputValidation.compose(
                            InputRules.howCanWeHelp.validate,
                            (value) => (value?.trim().length ?? 0) < 10
                                ? 'Enter at least 10 characters'
                                : null),
                        inputFormatters: InputValidation.formatters(
                            InputRules.howCanWeHelp, details),
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                        maxLength: InputRules.howCanWeHelp.maxLength,
                        maxLengthEnforcement: InputValidation.lengthEnforcement,
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
    final value = await InputValidation.showFormDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add address'),
        content: TextFormField(
          controller: controller,
          minLines: 2,
          maxLines: 3,
          autofocus: true,
          decoration: (const InputDecoration(
            labelText: 'Malaysian address',
            hintText: 'Street, postcode, city and state',
          )).copyWith(counterText: '', errorMaxLines: 3),
          validator: InputRules.malaysianAddress.validate,
          inputFormatters: InputValidation.formatters(
              InputRules.malaysianAddress, controller),
          autovalidateMode: AutovalidateMode.onUserInteraction,
          maxLength: InputRules.malaysianAddress.maxLength,
          maxLengthEnforcement: InputValidation.lengthEnforcement,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final text = controller.text.trim();
              InputValidation.popIfValid(dialogContext, text);
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
    final digits = await InputValidation.showFormDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add simulated card'),
        content: TextFormField(
          controller: controller,
          keyboardType: TextInputType.number,
          maxLength: 4,
          maxLengthEnforcement: InputValidation.lengthEnforcement,
          decoration: (const InputDecoration(
            labelText: 'Last four digits',
            helperText: 'No real card information is stored.',
          )).copyWith(counterText: '', errorMaxLines: 3),
          validator: InputRules.lastFourDigits.validate,
          inputFormatters:
              InputValidation.formatters(InputRules.lastFourDigits, controller),
          autovalidateMode: AutovalidateMode.onUserInteraction,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              InputValidation.popIfValid(dialogContext, value);
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
  String? currentDeviceId;
  bool liveControllerAvailable = false;
  bool localSessionsAvailable = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadDevices());
  }

  Future<void> _loadDevices() async {
    if (BackendMode.useMocks) return;
    try {
      final controller = context.read<LiveRentHubController>();
      final push = context.read<PushNotificationService>();
      final auth = context.read<AuthController>();
      final deviceId = await push.currentDeviceId();
      await controller.loadNotificationDevices();
      if (!auth.usesExternalProvider) await controller.loadLoginSessions();
      if (mounted) {
        setState(() {
          currentDeviceId = deviceId;
          liveControllerAvailable = true;
          localSessionsAvailable = !auth.usesExternalProvider;
        });
      }
    } on ProviderNotFoundException {
      // Standalone prototype previews intentionally have no live dependencies.
    } catch (exception) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Could not load security activity: $exception')),
        );
      }
    }
  }

  Future<void> _revokeLoginSession(Map<String, dynamic> session) async {
    final accepted = await confirmAction(
      context,
      title: 'Sign out this device?',
      message:
          'RentHub access will end on ${_loginSessionName(session)}. This device will need to sign in again.',
      action: 'Sign Out',
      destructive: true,
    );
    if (!accepted || !mounted) return;
    try {
      await context
          .read<LiveRentHubController>()
          .revokeLoginSession(session['id'] as String);
      if (mounted) showMockSuccess(context, 'Device signed out');
    } catch (exception) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(exception.toString())));
      }
    }
  }

  Future<void> _revokeOtherLoginSessions() async {
    final accepted = await confirmAction(
      context,
      title: 'Sign out all other devices?',
      message:
          'Your current device will remain signed in. Every other RentHub login session will be revoked.',
      action: 'Sign Out Others',
      destructive: true,
    );
    if (!accepted || !mounted) return;
    try {
      await context.read<LiveRentHubController>().revokeOtherLoginSessions();
      if (mounted) showMockSuccess(context, 'Other devices signed out');
    } catch (exception) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(exception.toString())));
      }
    }
  }

  Future<void> _removeDevice(Map<String, dynamic> device) async {
    final id = device['deviceId'] as String? ?? '';
    final isCurrent = id == currentDeviceId;
    final accepted = await confirmAction(
      context,
      title: isCurrent ? 'Remove this device?' : 'Remove notification device?',
      message: isCurrent
          ? 'Push notifications will stop on this device until they are enabled again.'
          : 'Push notifications will stop on ${device['deviceName'] ?? 'this device'}.',
      action: 'Remove',
      destructive: true,
    );
    if (!accepted || !mounted) return;
    try {
      await context.read<LiveRentHubController>().removeNotificationDevice(id);
      if (mounted) showMockSuccess(context, 'Notification device removed');
    } catch (exception) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(exception.toString())));
      }
    }
  }

  Future<void> _changePassword() async {
    final auth = context.read<AuthController>();
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => ForgotPasswordScreen(
          initialEmail: auth.user?.email ?? '',
        ),
      ),
    );
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
                      subtitle: const Text(
                        'Change it using a verified email code',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _changePassword,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              if (localSessionsAvailable)
                _LiveLoginSessions(
                  onRevoke: _revokeLoginSession,
                  onRevokeOthers: _revokeOtherLoginSessions,
                  onRefresh: _loadDevices,
                ),
              if (BackendMode.useMocks)
                const AccountCard(
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.phone_android_outlined),
                    title: Text('This device'),
                    subtitle: Text('Windows prototype session • Kuala Lumpur'),
                    trailing: StatusBadge('Active'),
                  ),
                ),
              if (liveControllerAvailable) ...[
                const SizedBox(height: 12),
                _LiveNotificationDevices(
                  currentDeviceId: currentDeviceId,
                  onRemove: _removeDevice,
                  onRefresh: _loadDevices,
                ),
              ],
              const SizedBox(height: 12),
              Text(
                context.watch<AuthController>().usesExternalProvider
                    ? 'Login sessions are managed by your identity provider. Removing a notification device only stops push delivery.'
                    : 'Login sessions control account access. Notification devices only control push delivery.',
                style: const TextStyle(
                  color: AppColors.secondaryText,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      );
}

class _LiveLoginSessions extends StatelessWidget {
  const _LiveLoginSessions({
    required this.onRevoke,
    required this.onRevokeOthers,
    required this.onRefresh,
  });

  final Future<void> Function(Map<String, dynamic>) onRevoke;
  final Future<void> Function() onRevokeOthers;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<LiveRentHubController>();
    final sessions = controller.loginSessions;
    final otherCount = sessions.where((item) => item['current'] != true).length;
    return AccountCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Where you are signed in',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                tooltip: 'Refresh login sessions',
                onPressed: controller.loading ? null : onRefresh,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          if (sessions.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'No active login sessions were found.',
                style: TextStyle(color: AppColors.secondaryText),
              ),
            ),
          for (final session in sessions)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(_loginSessionIcon(session)),
              title: Text(_loginSessionName(session)),
              subtitle: Text(_loginSessionDetails(session)),
              trailing: session['current'] == true
                  ? const StatusBadge('This device')
                  : IconButton(
                      tooltip: 'Sign out this device',
                      onPressed:
                          controller.loading ? null : () => onRevoke(session),
                      icon: const Icon(Icons.logout, color: AppColors.error),
                    ),
            ),
          if (otherCount > 0) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: controller.loading ? null : onRevokeOthers,
                icon: const Icon(Icons.logout),
                label: Text(
                  'Sign out $otherCount other ${otherCount == 1 ? 'device' : 'devices'}',
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

IconData _loginSessionIcon(Map<String, dynamic> session) {
  final agent = (session['userAgent'] as String? ?? '').toLowerCase();
  if (agent.contains('android')) return Icons.phone_android_outlined;
  if (agent.contains('iphone') || agent.contains('ipad')) {
    return Icons.phone_iphone;
  }
  if (agent.contains('windows') ||
      agent.contains('macintosh') ||
      agent.contains('linux')) {
    return Icons.computer_outlined;
  }
  return Icons.devices_other_outlined;
}

String _loginSessionName(Map<String, dynamic> session) {
  final agent = session['userAgent'] as String? ?? '';
  final lowerAgent = agent.toLowerCase();
  final platform = lowerAgent.contains('android')
      ? 'Android'
      : lowerAgent.contains('iphone') || lowerAgent.contains('ipad')
          ? 'iPhone or iPad'
          : lowerAgent.contains('windows')
              ? 'Windows'
              : lowerAgent.contains('macintosh') || lowerAgent.contains('macos')
                  ? 'Mac'
                  : lowerAgent.contains('linux')
                      ? 'Linux'
                      : 'Unknown device';
  final browser = agent.contains('Edg/')
      ? 'Edge'
      : agent.contains('Chrome/')
          ? 'Chrome'
          : agent.contains('Firefox/')
              ? 'Firefox'
              : agent.contains('Safari/')
                  ? 'Safari'
                  : '';
  return browser.isEmpty ? platform : '$browser on $platform';
}

String _loginSessionDetails(Map<String, dynamic> session) {
  final lastUsed =
      DateTime.tryParse(session['lastUsedAt']?.toString() ?? '')?.toLocal();
  final date = lastUsed == null
      ? 'Unknown activity'
      : 'Refreshed ${lastUsed.day}/${lastUsed.month}/${lastUsed.year} at ${lastUsed.hour.toString().padLeft(2, '0')}:${lastUsed.minute.toString().padLeft(2, '0')}';
  final ip = (session['ip'] as String? ?? '').trim();
  return ip.isEmpty ? date : '$date · IP $ip';
}

class _LiveNotificationDevices extends StatelessWidget {
  const _LiveNotificationDevices({
    required this.currentDeviceId,
    required this.onRemove,
    required this.onRefresh,
  });

  final String? currentDeviceId;
  final Future<void> Function(Map<String, dynamic>) onRemove;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<LiveRentHubController>();
    final devices = controller.notificationDevices;
    return AccountCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Notification devices',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                tooltip: 'Refresh devices',
                onPressed: controller.loading ? null : onRefresh,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          if (devices.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'No device is registered for push notifications.',
                style: TextStyle(color: AppColors.secondaryText),
              ),
            ),
          for (final device in devices)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                switch (device['platform']) {
                  'web' => Icons.language,
                  'ios' || 'macos' => Icons.phone_iphone,
                  _ => Icons.phone_android_outlined,
                },
              ),
              title: Text(
                (device['deviceName'] as String?)?.trim().isNotEmpty ?? false
                    ? device['deviceName'] as String
                    : '${device['platform'] ?? 'Unknown'} device',
              ),
              subtitle: Text(
                device['deviceId'] == currentDeviceId
                    ? 'This device · Push enabled'
                    : 'Last active ${_displayDate(device['lastSeenAt'])}',
              ),
              trailing: IconButton(
                tooltip: 'Remove device',
                onPressed: () => onRemove(device),
                icon: const Icon(Icons.delete_outline),
              ),
            ),
        ],
      ),
    );
  }

  static String _displayDate(dynamic value) {
    final date = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
    if (date == null) return 'unknown';
    return '${date.day}/${date.month}/${date.year}';
  }
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

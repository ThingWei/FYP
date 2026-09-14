import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../modules/user/controllers/auth_controller.dart';
import '../../shared/models/domain_models.dart';
import '../../shared/widgets/account_components.dart';
import '../../shared/widgets/renthub_components.dart';
import '../auth/pages/kyc_document_submission_page.dart';
import 'account_management_pages.dart';
import 'loyalty_referral_page.dart';
import 'role_selection_screen.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({
    super.key,
    required this.role,
    required this.canSwitch,
    required this.onSwitch,
  });

  final String role;
  final bool canSwitch;
  final VoidCallback onSwitch;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  bool verified = true;

  Future<void> _chooseRole() async {
    final current = widget.role == 'Owner' ? UserRole.owner : UserRole.renter;
    final selected = await Navigator.push<UserRole>(
      context,
      MaterialPageRoute(
        builder: (_) => RoleSelectionScreen(initialRole: current),
      ),
    );
    if (selected != null && selected != current) widget.onSwitch();
  }

  Future<void> _verification() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const KycDocumentSubmissionPage()),
    );
    if (result == true && mounted) setState(() => verified = true);
  }

  Future<void> _editProfile() async {
    final auth = context.read<AuthController>();
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => EditProfilePage(
          initialName: auth.user?.name ?? 'Nur Izzati',
          initialEmail: auth.user?.email ?? 'demo@renthub.my',
        ),
      ),
    );
    if (saved == true && mounted) {
      showMockSuccess(context, 'Profile changes saved for this session');
    }
  }

  Future<void> _signOut() async {
    final confirmed = await confirmAction(
      context,
      title: 'Sign out?',
      message: 'You can sign in again with the mock account at any time.',
      action: 'Sign Out',
      destructive: true,
    );
    if (confirmed && mounted) await context.read<AuthController>().logout();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final user = auth.user;
    final name = user?.name ?? 'Nur Izzati';
    final initials = name
        .split(' ')
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part[0])
        .join();
    return Scaffold(
      appBar: AppBar(
        title: const RentHubLogo(compact: true),
        actions: [
          IconButton(
            tooltip: 'Notifications',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const NotificationsPage()),
            ),
            icon: const Badge(child: Icon(Icons.notifications_outlined)),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Center(
              child: CircleAvatar(
                radius: 38,
                backgroundColor: AppColors.primaryLight,
                child: Text(
                  initials,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: AppColors.primaryDark,
                      ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              name,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 4),
            Text(
              '${verified ? 'Verified' : 'Unverified'} ${widget.role} · Member since 2024',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: verified ? AppColors.success : AppColors.warning,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            AccountCard(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  const Text('TRUST SCORE'),
                  const Spacer(),
                  Text(
                    '${((user?.trustScore ?? 4.7) * 20).round()}',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: AppColors.success,
                        ),
                  ),
                  const Text(' /100'),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _ProfileSection(
              title: 'Personal Info',
              trailing: TextButton(
                  onPressed: _editProfile, child: const Text('Edit')),
              child:
                  Text('${user?.email ?? 'demo@renthub.my'}\n+60 12-345 6789'),
            ),
            const SizedBox(height: 12),
            _ProfileSection(
              title: 'Identity Verification',
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  verified ? Icons.verified_user_outlined : Icons.warning_amber,
                  color: verified ? AppColors.success : AppColors.warning,
                ),
                title: const Text('Government ID'),
                subtitle:
                    Text(verified ? 'Verified securely' : 'Action required'),
                trailing: StatusBadge(verified ? 'Verified' : 'Pending'),
                onTap: _verification,
              ),
            ),
            const SizedBox(height: 12),
            if (widget.role == 'Renter') ...[
              Card(
                child: ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: AppColors.primaryLight,
                    child: Icon(
                      Icons.card_giftcard_outlined,
                      color: AppColors.primaryDark,
                    ),
                  ),
                  title: const Text('Loyalty & Referrals'),
                  subtitle:
                      const Text('Points, rewards and your referral code'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push<void>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const LoyaltyReferralPage(),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            _ProfileSection(
              title: 'Addresses',
              child: _ManageBlock(
                icon: Icons.location_on_outlined,
                value: '1 default address\nPetaling Jaya, Selangor',
                onManage: () => Navigator.push<void>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const AddressManagementPage(),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            _ProfileSection(
              title: 'Payment Methods',
              child: _ManageBlock(
                icon: Icons.credit_card,
                value: 'Visa ···· 4242',
                onManage: () => Navigator.push<void>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const PaymentMethodsPage(),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  if (widget.canSwitch)
                    _SettingsTile(
                      icon: Icons.swap_horiz,
                      label:
                          'Switch to ${widget.role == 'Renter' ? 'Owner' : 'Renter'} Mode',
                      onTap: _chooseRole,
                    ),
                  _SettingsTile(
                    icon: Icons.settings_outlined,
                    label: 'Application Settings',
                    onTap: () => Navigator.push<void>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ApplicationSettingsPage(),
                      ),
                    ),
                  ),
                  _SettingsTile(
                    icon: Icons.help_outline,
                    label: 'Help & Support',
                    onTap: () => Navigator.push<void>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const HelpSupportPage(),
                      ),
                    ),
                  ),
                  _SettingsTile(
                    icon: Icons.shield_outlined,
                    label: 'Security',
                    onTap: () => Navigator.push<void>(
                      context,
                      MaterialPageRoute(builder: (_) => const SecurityPage()),
                    ),
                  ),
                  _SettingsTile(
                    icon: Icons.logout,
                    label: 'Sign Out',
                    color: AppColors.error,
                    onTap: auth.loading ? null : _signOut,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class EditProfilePage extends StatefulWidget {
  const EditProfilePage({
    super.key,
    required this.initialName,
    required this.initialEmail,
  });

  final String initialName;
  final String initialEmail;

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  final formKey = GlobalKey<FormState>();
  late final name = TextEditingController(text: widget.initialName);
  late final email = TextEditingController(text: widget.initialEmail);
  final phone = TextEditingController(text: '+60 12-345 6789');
  final address = TextEditingController(
    text: '123 Nexus Way, Apt 4B, Kuala Lumpur',
  );

  @override
  void dispose() {
    name.dispose();
    email.dispose();
    phone.dispose();
    address.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Edit Profile')),
        body: SafeArea(
          child: Form(
            key: formKey,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                Center(
                  child: Stack(
                    children: [
                      const CircleAvatar(
                        radius: 42,
                        backgroundColor: AppColors.primaryLight,
                        child: Icon(Icons.person,
                            size: 44, color: AppColors.primaryDark),
                      ),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: IconButton.filled(
                          tooltip: 'Change avatar',
                          onPressed: () => showMockSuccess(
                            context,
                            'Avatar placeholder updated',
                          ),
                          icon: const Icon(Icons.edit, size: 18),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                AccountCard(
                  child: Column(
                    children: [
                      TextFormField(
                        controller: name,
                        decoration:
                            const InputDecoration(labelText: 'Full name'),
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                                ? 'Name is required'
                                : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: email,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          labelText: 'Email address',
                          helperText: 'Verified',
                        ),
                        validator: (value) => value?.contains('@') == true
                            ? null
                            : 'Enter a valid email',
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: phone,
                        keyboardType: TextInputType.phone,
                        decoration:
                            const InputDecoration(labelText: 'Phone number'),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: address,
                        minLines: 2,
                        maxLines: 3,
                        decoration:
                            const InputDecoration(labelText: 'Primary address'),
                      ),
                      const SizedBox(height: 20),
                      RentHubActionButton(
                        label: 'Save Changes',
                        onPressed: () {
                          if (formKey.currentState!.validate()) {
                            Navigator.pop(context, true);
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

class ApplicationSettingsPage extends StatefulWidget {
  const ApplicationSettingsPage({super.key});

  @override
  State<ApplicationSettingsPage> createState() =>
      _ApplicationSettingsPageState();
}

class _ApplicationSettingsPageState extends State<ApplicationSettingsPage> {
  bool bookingAlerts = true;
  bool messageAlerts = true;
  bool promotions = false;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Settings')),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              AccountCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Notifications',
                        style: Theme.of(context).textTheme.titleMedium),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Booking updates'),
                      value: bookingAlerts,
                      onChanged: (value) =>
                          setState(() => bookingAlerts = value),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('New messages'),
                      value: messageAlerts,
                      onChanged: (value) =>
                          setState(() => messageAlerts = value),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Promotions'),
                      value: promotions,
                      onChanged: (value) => setState(() => promotions = value),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              AccountCard(
                child: Column(
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.block_outlined),
                      title: const Text('Blocked Owners'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.push<void>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const BlockedOwnersPage(),
                        ),
                      ),
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.language_outlined),
                      title: const Text('Language'),
                      subtitle: const Text('English (Malaysia)'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.push<void>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const LanguagePage(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}

class _ProfileSection extends StatelessWidget {
  const _ProfileSection(
      {required this.title, required this.child, this.trailing});
  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => AccountCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(title,
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 8),
            DefaultTextStyle.merge(
              style: const TextStyle(color: AppColors.secondaryText),
              child: child,
            ),
          ],
        ),
      );
}

class _ManageBlock extends StatelessWidget {
  const _ManageBlock(
      {required this.icon, required this.value, required this.onManage});
  final IconData icon;
  final String value;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, color: AppColors.primaryDark),
              const SizedBox(width: 10),
              Expanded(child: Text(value)),
            ],
          ),
          const SizedBox(height: 12),
          RentHubActionButton(
            label: 'Manage',
            style: RentHubButtonStyle.secondary,
            onPressed: onManage,
          ),
        ],
      );
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) => ListTile(
        leading: Icon(icon, color: color),
        title: Text(label, style: TextStyle(color: color)),
        trailing: onTap == null ? null : const Icon(Icons.chevron_right),
        onTap: onTap,
      );
}

enum NotificationCategory { bookings, messages, promotions }

class AccountNotification {
  const AccountNotification({
    required this.id,
    required this.category,
    required this.title,
    required this.message,
    required this.time,
    required this.today,
    this.read = false,
  });
  final String id;
  final NotificationCategory category;
  final String title;
  final String message;
  final String time;
  final bool today;
  final bool read;

  AccountNotification copyWith({bool? read}) => AccountNotification(
        id: id,
        category: category,
        title: title,
        message: message,
        time: time,
        today: today,
        read: read ?? this.read,
      );
}

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  String filter = 'All';
  bool loading = true;
  String? error;
  List<AccountNotification> items = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    await Future<void>.delayed(const Duration(milliseconds: 350));
    if (!mounted) return;
    setState(() {
      loading = false;
      items = const [
        AccountNotification(
          id: 'pickup-camera',
          category: NotificationCategory.bookings,
          title: 'Upcoming Pickup: Sony Camera',
          message:
              'Your rental with Sarah J. is scheduled for pickup in 2 hours at Lot 10, Bukit Bintang.',
          time: '10:45 AM',
          today: true,
        ),
        AccountNotification(
          id: 'message-sarah',
          category: NotificationCategory.messages,
          title: 'New Message from Sarah J.',
          message:
              'Hi! I was wondering if the projector comes with HDMI cables?',
          time: '9:12 AM',
          today: true,
        ),
        AccountNotification(
          id: 'booking-confirmed',
          category: NotificationCategory.bookings,
          title: 'Booking Confirmed',
          message:
              'Your booking request for the Camping Tent has been accepted.',
          time: '8:00 AM',
          today: true,
        ),
        AccountNotification(
          id: 'weekend-offer',
          category: NotificationCategory.promotions,
          title: 'Weekend Special: 20% Off',
          message:
              'Rent any power tool this weekend and get 20% off with code BUILD20.',
          time: 'Yesterday',
          today: false,
          read: true,
        ),
      ];
    });
  }

  List<AccountNotification> get visible => filter == 'All'
      ? items
      : items
          .where((item) => item.category.name == filter.toLowerCase())
          .toList();

  void _markAllRead() => setState(
        () => items = items.map((item) => item.copyWith(read: true)).toList(),
      );

  void _remove(AccountNotification item) {
    final index = items.indexWhere((candidate) => candidate.id == item.id);
    setState(() => items.removeAt(index));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Notification removed'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => setState(() => items.insert(index, item)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Notifications'),
          actions: [
            TextButton(
              onPressed: items.any((item) => !item.read) ? _markAllRead : null,
              child: const Text('Mark all read'),
            ),
            IconButton(
              tooltip: 'Clear all notifications',
              onPressed: items.isEmpty
                  ? null
                  : () async {
                      final accepted = await confirmAction(
                        context,
                        title: 'Clear all notifications?',
                        message:
                            'All notifications will be removed from this prototype session.',
                        action: 'Clear All',
                        destructive: true,
                      );
                      if (accepted && mounted) setState(() => items = []);
                    },
              icon: const Icon(Icons.delete_sweep_outlined),
            ),
          ],
        ),
        body: SafeArea(child: _body()),
      );

  Widget _body() {
    if (loading) {
      return const RentHubFeedbackState(
        kind: FeedbackKind.loading,
        title: 'Loading notifications',
        message: 'Checking your latest RentHub activity.',
      );
    }
    if (error != null) {
      return RentHubFeedbackState(
        kind: FeedbackKind.error,
        title: 'Notifications unavailable',
        message: error!,
        actionLabel: 'Try Again',
        onAction: _load,
      );
    }
    return Column(
      children: [
        SizedBox(
          height: 54,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            children: [
              for (final label in const [
                'All',
                'Bookings',
                'Messages',
                'Promotions'
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(label),
                    selected: filter == label,
                    onSelected: (_) => setState(() => filter = label),
                  ),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: visible.isEmpty
              ? RentHubFeedbackState(
                  kind: FeedbackKind.empty,
                  title: filter == 'All'
                      ? 'You’re all caught up'
                      : 'No $filter notifications',
                  message: 'New activity will appear here.',
                  actionLabel: filter == 'All' ? null : 'Show All',
                  onAction: filter == 'All'
                      ? null
                      : () => setState(() => filter = 'All'),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  children: [
                    if (visible.any((item) => item.today)) ...[
                      const _DateHeading('Today'),
                      for (final item in visible.where((item) => item.today))
                        _NotificationTile(
                          item: item,
                          onRemove: () => _remove(item),
                          onTap: () => _open(item),
                        ),
                    ],
                    if (visible.any((item) => !item.today)) ...[
                      const SizedBox(height: 12),
                      const _DateHeading('Yesterday'),
                      for (final item in visible.where((item) => !item.today))
                        _NotificationTile(
                          item: item,
                          onRemove: () => _remove(item),
                          onTap: () => _open(item),
                        ),
                    ],
                  ],
                ),
        ),
      ],
    );
  }

  void _open(AccountNotification item) {
    setState(() {
      items = items
          .map((candidate) => candidate.id == item.id
              ? candidate.copyWith(read: true)
              : candidate)
          .toList();
    });
    showMockSuccess(context, '${item.title} opened');
  }
}

class _DateHeading extends StatelessWidget {
  const _DateHeading(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(label, style: Theme.of(context).textTheme.titleMedium),
      );
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({
    required this.item,
    required this.onRemove,
    required this.onTap,
  });
  final AccountNotification item;
  final VoidCallback onRemove;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final icon = switch (item.category) {
      NotificationCategory.bookings => Icons.receipt_long_outlined,
      NotificationCategory.messages => Icons.chat_bubble_outline,
      NotificationCategory.promotions => Icons.local_offer_outlined,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Dismissible(
        key: ValueKey(item.id),
        direction: DismissDirection.endToStart,
        onDismissed: (_) => onRemove(),
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 20),
          decoration: BoxDecoration(
            color: AppColors.error,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.delete_outline, color: Colors.white),
        ),
        child: Card(
          color: item.read ? AppColors.background : AppColors.blueSurface,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
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
                        Text(item.title,
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 4),
                        Text(
                          item.message,
                          style:
                              const TextStyle(color: AppColors.secondaryText),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        item.time,
                        style: const TextStyle(
                          color: AppColors.secondaryText,
                          fontSize: 11,
                        ),
                      ),
                      if (!item.read) ...[
                        const SizedBox(height: 8),
                        const CircleAvatar(
                          radius: 4,
                          backgroundColor: AppColors.primary,
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

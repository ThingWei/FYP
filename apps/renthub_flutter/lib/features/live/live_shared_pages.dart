import '../../core/validation/input_validation.dart';
import '../../core/validation/input_rules.dart';
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../modules/user/controllers/auth_controller.dart';
import '../../shared/models/domain_models.dart';
import '../../shared/widgets/account_components.dart';
import '../../shared/widgets/renthub_components.dart';
import 'live_renthub_controller.dart';
import 'live_photo_widgets.dart';
import 'live_loyalty_page.dart';
import 'live_kyc_scanner_page.dart';
import 'live_identity_policy.dart';

/// Refresh approval before protected actions; the Express API is authoritative.
Future<bool> ensureMarketplaceIdentity(BuildContext context,
    {required String action}) async {
  final controller = context.read<LiveRentHubController>();
  try {
    final profile = await controller.refreshIdentityProfile();
    if (!context.mounted) return false;
    if (marketplaceIdentityApproved(profile)) return true;
    final proceed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.verified_user_outlined),
        title: const Text('Identity verification required'),
        content: Text(marketplaceIdentityMessage(profile.mykadStatus, action)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Not now')),
          FilledButton(
            onPressed: () => InputValidation.popIfValid(dialogContext, true),
            child: Text(profile.mykadStatus == 'pending'
                ? 'View verification status'
                : 'Verify MyKad'),
          ),
        ],
      ),
    );
    if (proceed != true || !context.mounted) return false;
    await Navigator.push<void>(context,
        MaterialPageRoute(builder: (_) => const LiveVerificationPage()));
    if (!context.mounted) return false;
    final updated = await controller.refreshIdentityProfile();
    return context.mounted && marketplaceIdentityApproved(updated);
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            'Could not check identity verification. Please try again. No booking or listing was submitted.'),
      ));
    }
    return false;
  }
}

class LiveMessagesPage extends StatefulWidget {
  const LiveMessagesPage({super.key});

  @override
  State<LiveMessagesPage> createState() => _LiveMessagesPageState();
}

class _LiveMessagesPageState extends State<LiveMessagesPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh() async {
    try {
      await context.read<LiveRentHubController>().refreshConversations();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<LiveRentHubController>();
    return Scaffold(
      appBar: AppBar(title: const Text('Messages')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: controller.conversations.isEmpty
            ? ListView(
                children: [
                  SizedBox(
                    height: MediaQuery.sizeOf(context).height * .68,
                    child: RentHubFeedbackState(
                      kind: controller.error == null
                          ? FeedbackKind.empty
                          : FeedbackKind.error,
                      title: controller.error == null
                          ? 'No conversations yet'
                          : 'Messages unavailable',
                      message: controller.error ??
                          'A conversation is created automatically when you request a booking.',
                      actionLabel: 'Refresh',
                      onAction: _refresh,
                    ),
                  ),
                ],
              )
            : ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: controller.conversations.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final conversation = controller.conversations[index];
                  return ListTile(
                    minVerticalPadding: 12,
                    leading: CircleAvatar(
                      child: Text(conversation.otherParticipantName[0]),
                    ),
                    title: Text(conversation.otherParticipantName),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          conversation.listingTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12),
                        ),
                        Text(
                          conversation.lastMessageText.isEmpty
                              ? 'Booking conversation ready'
                              : conversation.lastMessageText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                    trailing: conversation.unreadCount == 0
                        ? const Icon(Icons.chevron_right)
                        : Badge(
                            label: Text('${conversation.unreadCount}'),
                            child: const Icon(Icons.chat_bubble_outline),
                          ),
                    onTap: () => Navigator.push<void>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => LiveChatPage(
                          conversation: conversation,
                        ),
                      ),
                    ).then((_) => _refresh()),
                  );
                },
              ),
      ),
    );
  }
}

class LiveChatPage extends StatefulWidget {
  const LiveChatPage({super.key, required this.conversation});

  final Conversation conversation;

  @override
  State<LiveChatPage> createState() => _LiveChatPageState();
}

class _LiveChatPageState extends State<LiveChatPage> {
  final input = TextEditingController();
  final messages = <Message>[];
  StreamSubscription<Message>? subscription;
  bool loading = true;
  bool sending = false;
  String? error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final controller = context.read<LiveRentHubController>();
    subscription ??= controller
        .watchThread(widget.conversation.id)
        .listen((message) => _addMessage(message));
    try {
      final loaded = await controller.loadMessages(widget.conversation.id);
      await controller.markThreadRead(widget.conversation.id);
      if (!mounted) return;
      setState(() {
        messages
          ..clear()
          ..addAll(loaded);
        loading = false;
        error = null;
      });
    } catch (exception) {
      if (!mounted) return;
      setState(() {
        loading = false;
        error = exception.toString();
      });
    }
  }

  void _addMessage(Message message) {
    if (!mounted || messages.any((item) => item.id == message.id)) return;
    setState(() => messages.add(message));
  }

  Future<void> _send() async {
    if (!InputValidation.validate(context)) return;
    final text = input.text.trim();
    if (text.isEmpty || sending) return;
    setState(() => sending = true);
    try {
      final message = await context
          .read<LiveRentHubController>()
          .sendMessage(widget.conversation.id, text);
      input.clear();
      _addMessage(message);
    } catch (exception) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(exception.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Future<void> _sendImage() async {
    if (sending) return;
    setState(() => sending = true);
    try {
      final message = await context
          .read<LiveRentHubController>()
          .pickAndSendMessageImage(widget.conversation.id,
              confirmSelection: (bytes, name) =>
                  confirmPhotoSelection(context, bytes, name));
      if (message != null) _addMessage(message);
    } catch (exception) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(exception.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Future<void> _report(Message message) async {
    var reason = 'inappropriate';
    final details = TextEditingController();
    final accepted = await InputValidation.showFormDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Report message'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: reason,
                decoration: const InputDecoration(labelText: 'Reason'),
                items: const [
                  DropdownMenuItem(
                      value: 'harassment', child: Text('Harassment')),
                  DropdownMenuItem(value: 'scam', child: Text('Scam')),
                  DropdownMenuItem(value: 'spam', child: Text('Spam')),
                  DropdownMenuItem(
                    value: 'inappropriate',
                    child: Text('Inappropriate'),
                  ),
                  DropdownMenuItem(value: 'other', child: Text('Other')),
                ],
                onChanged: (value) =>
                    setDialogState(() => reason = value ?? reason),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: details,
                maxLength: 1000,
                maxLengthEnforcement: InputValidation.lengthEnforcement,
                decoration: (const InputDecoration(
                  labelText: 'Details',
                  hintText: 'Explain what happened',
                )).copyWith(counterText: '', errorMaxLines: 3),
                validator: InputRules.details.validate,
                inputFormatters:
                    InputValidation.formatters(InputRules.details, details),
                autovalidateMode: AutovalidateMode.onUserInteraction,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => InputValidation.popIfValid(dialogContext, true),
              child: const Text('Submit Report'),
            ),
          ],
        ),
      ),
    );
    if (accepted != true || !mounted) {
      details.dispose();
      return;
    }
    try {
      await context.read<LiveRentHubController>().reportMessage(
            message.id,
            reason,
            details.text,
          );
      if (mounted) showMockSuccess(context, 'Message report submitted');
    } catch (exception) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(exception.toString())),
        );
      }
    } finally {
      details.dispose();
    }
  }

  @override
  void dispose() {
    subscription?.cancel();
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ownId = context.watch<LiveRentHubController>().profile?.id;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.conversation.otherParticipantName),
            Text(
              widget.conversation.listingTitle,
              style: const TextStyle(fontSize: 11),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : error != null
                    ? RentHubFeedbackState(
                        kind: FeedbackKind.error,
                        title: 'Conversation unavailable',
                        message: error!,
                        actionLabel: 'Try Again',
                        onAction: _load,
                      )
                    : messages.isEmpty
                        ? const RentHubFeedbackState(
                            kind: FeedbackKind.empty,
                            title: 'Start the conversation',
                            message:
                                'Messages are stored with this booking in MongoDB.',
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: messages.length,
                            itemBuilder: (context, index) {
                              final message = messages[index];
                              final own = message.senderId == ownId;
                              return Align(
                                alignment: own
                                    ? Alignment.centerRight
                                    : Alignment.centerLeft,
                                child: GestureDetector(
                                  onLongPress:
                                      own ? null : () => _report(message),
                                  child: Container(
                                    constraints:
                                        const BoxConstraints(maxWidth: 300),
                                    margin: const EdgeInsets.only(bottom: 8),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      color: own
                                          ? AppColors.primaryLight
                                          : AppColors.background,
                                      border:
                                          Border.all(color: AppColors.border),
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        if (message.attachment?.kind == 'image')
                                          _ProtectedMessageImage(
                                            attachment: message.attachment!,
                                          ),
                                        if (message.attachment != null &&
                                            message.text.isNotEmpty)
                                          const SizedBox(height: 8),
                                        if (message.text.isNotEmpty)
                                          Text(message.text),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: TextFormField(
                controller: input,
                enabled: !sending,
                maxLength: 2000,
                maxLengthEnforcement: InputValidation.lengthEnforcement,
                minLines: 1,
                maxLines: 4,
                onFieldSubmitted: (_) => _send(),
                decoration: (InputDecoration(
                  hintText: 'Write a message',
                  counterText: '',
                  prefixIcon: IconButton(
                    tooltip: 'Send image',
                    onPressed: sending ? null : _sendImage,
                    icon: const Icon(Icons.add_photo_alternate_outlined),
                  ),
                  suffixIcon: IconButton(
                    tooltip: 'Send message',
                    onPressed: sending ? null : _send,
                    icon: sending
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send),
                  ),
                )).copyWith(errorMaxLines: 3),
                validator: InputRules.writeAMessage.validate,
                inputFormatters:
                    InputValidation.formatters(InputRules.writeAMessage, input),
                autovalidateMode: AutovalidateMode.onUserInteraction,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProtectedMessageImage extends StatefulWidget {
  const _ProtectedMessageImage({required this.attachment});

  final MessageAttachment attachment;

  @override
  State<_ProtectedMessageImage> createState() => _ProtectedMessageImageState();
}

class _ProtectedMessageImageState extends State<_ProtectedMessageImage> {
  late Future<Uint8List> imageBytes;

  @override
  void initState() {
    super.initState();
    imageBytes = context
        .read<LiveRentHubController>()
        .api
        .downloadBytes(widget.attachment.url);
  }

  void _open(Uint8List bytes) {
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 4,
          child: Image.memory(
            bytes,
            semanticLabel: widget.attachment.filename,
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List>(
        future: imageBytes,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const SizedBox(
              width: 220,
              height: 120,
              child: Center(
                child: Text(
                  'Image unavailable',
                  style: TextStyle(color: AppColors.secondaryText),
                ),
              ),
            );
          }
          final bytes = snapshot.data;
          if (bytes == null) {
            return const SizedBox(
              width: 220,
              height: 120,
              child: Center(child: CircularProgressIndicator()),
            );
          }
          return Semantics(
            button: true,
            label: 'Open image ${widget.attachment.filename}',
            child: InkWell(
              onTap: () => _open(bytes),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: 260,
                    maxHeight: 260,
                  ),
                  child: Image.memory(
                    bytes,
                    semanticLabel: widget.attachment.filename,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
          );
        },
      );
}

class LiveNotificationsPage extends StatefulWidget {
  const LiveNotificationsPage({super.key});

  @override
  State<LiveNotificationsPage> createState() => _LiveNotificationsPageState();
}

class _LiveNotificationsPageState extends State<LiveNotificationsPage> {
  String filter = 'all';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      await context.read<LiveRentHubController>().loadNotifications(
            category: filter == 'all' ? null : filter,
          );
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<LiveRentHubController>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          TextButton(
            onPressed: controller.notifications.any((item) => !item.read)
                ? () => controller.markAllNotificationsRead()
                : null,
            child: const Text('Mark all read'),
          ),
          IconButton(
            tooltip: 'Clear all notifications',
            onPressed: controller.notifications.isEmpty
                ? null
                : () async {
                    final accepted = await confirmAction(
                      context,
                      title: 'Clear all notifications?',
                      message:
                          'This permanently removes your notifications from MongoDB.',
                      action: 'Clear All',
                      destructive: true,
                    );
                    if (accepted && context.mounted) {
                      await controller.clearNotifications();
                    }
                  },
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          SizedBox(
            height: 56,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              children: [
                for (final item in const [
                  ('all', 'All'),
                  ('booking', 'Bookings'),
                  ('message', 'Messages'),
                  ('payment', 'Payments'),
                  ('rental', 'Rentals'),
                  ('review', 'Reviews'),
                  ('dispute', 'Disputes'),
                  ('loyalty', 'Rewards'),
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(item.$2),
                      selected: filter == item.$1,
                      onSelected: (_) {
                        setState(() => filter = item.$1);
                        _load();
                      },
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: controller.loading && controller.notifications.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : controller.notifications.isEmpty
                      ? ListView(
                          children: [
                            SizedBox(
                              height: MediaQuery.sizeOf(context).height * .6,
                              child: const RentHubFeedbackState(
                                kind: FeedbackKind.empty,
                                title: 'You’re all caught up',
                                message:
                                    'Booking and marketplace activity will appear here.',
                              ),
                            ),
                          ],
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: controller.notifications.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final item = controller.notifications[index];
                            return Dismissible(
                              key: ValueKey(item.id),
                              direction: DismissDirection.endToStart,
                              onDismissed: (_) =>
                                  controller.removeNotification(item.id),
                              background: Container(
                                alignment: Alignment.centerRight,
                                padding: const EdgeInsets.only(right: 20),
                                color: AppColors.error,
                                child: const Icon(
                                  Icons.delete_outline,
                                  color: Colors.white,
                                ),
                              ),
                              child: Card(
                                color: item.read
                                    ? AppColors.background
                                    : AppColors.blueSurface,
                                child: ListTile(
                                  leading: Icon(
                                    switch (item.category) {
                                      'message' => Icons.chat_bubble_outline,
                                      'payment' => Icons.payments_outlined,
                                      'rental' => Icons.inventory_2_outlined,
                                      'review' => Icons.star_outline,
                                      'dispute' => Icons.gavel_outlined,
                                      'loyalty' => Icons.card_giftcard_outlined,
                                      'verification' =>
                                        Icons.verified_user_outlined,
                                      _ => Icons.receipt_long_outlined,
                                    },
                                    color: AppColors.primaryDark,
                                  ),
                                  title: Text(item.title),
                                  subtitle: Text(item.body),
                                  trailing: item.read
                                      ? null
                                      : const Icon(
                                          Icons.circle,
                                          size: 10,
                                          color: AppColors.primary,
                                        ),
                                  onTap: () =>
                                      controller.markNotificationRead(item.id),
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ),
        ],
      ),
    );
  }
}

class LiveProfilePage extends StatelessWidget {
  const LiveProfilePage({
    super.key,
    required this.role,
    required this.canSwitch,
    required this.onSwitch,
    required this.onLogout,
  });

  final String role;
  final bool canSwitch;
  final VoidCallback onSwitch;
  final Future<void> Function() onLogout;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<LiveRentHubController>();
    final profile = controller.profile;
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 36,
                      child: Text(
                        profile?.name.substring(0, 1).toUpperCase() ?? '?',
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      profile?.name ?? 'RentHub user',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Text(profile?.email ?? ''),
                    const SizedBox(height: 8),
                    StatusBadge('$role account'),
                    const SizedBox(height: 8),
                    Text(
                        'Trust score ${profile?.trustScore.toStringAsFixed(0) ?? '—'}'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.cloud_done_outlined),
              title: const Text('Connected to RentHub API'),
              subtitle:
                  const Text('Profile and activity are stored in MongoDB.'),
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit profile'),
              subtitle: Text(profile?.phone.isEmpty ?? true
                  ? 'Add your phone number'
                  : profile!.phone),
              trailing: const Icon(Icons.chevron_right),
              onTap: profile == null
                  ? null
                  : () => Navigator.push<void>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => _LiveEditProfilePage(profile),
                        ),
                      ),
            ),
            ListTile(
              leading: const Icon(Icons.verified_user_outlined),
              title: const Text('Identity verification'),
              subtitle: Text(
                profile?.verificationStatus.replaceAll('_', ' ') ??
                    'unverified',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push<void>(
                context,
                MaterialPageRoute(
                  builder: (_) => const LiveVerificationPage(),
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.drive_eta_outlined),
              title: const Text('Vehicle driving eligibility'),
              subtitle: Text(profile?.drivingEligibility.displayStatus
                      .replaceAll('_', ' ') ??
                  'unverified'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push<void>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const LiveVerificationPage(driving: true),
                  )),
            ),
            ListTile(
              leading: const Icon(Icons.location_on_outlined),
              title: const Text('Saved addresses'),
              subtitle: Text(
                profile?.addresses.isEmpty ?? true
                    ? 'No saved addresses'
                    : '${profile!.addresses.length} saved | ${profile.addresses.where((item) => item.isDefault).firstOrNull?.label ?? 'No default'}',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push<void>(
                context,
                MaterialPageRoute(
                  builder: (_) => const _LiveAddressesPage(),
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: const Text('Application settings'),
              subtitle: Text(
                '${profile?.language == 'ms' ? 'Bahasa Melayu' : 'English'} | Notification preferences',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: profile == null
                  ? null
                  : () => Navigator.push<void>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => _LiveSettingsPage(profile),
                        ),
                      ),
            ),
            ListTile(
              leading: const Icon(Icons.card_giftcard_outlined),
              title: const Text('Loyalty & Referrals'),
              subtitle: Text(
                '${controller.loyalty?.points ?? 0} points • Rewards and referral code',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push<void>(
                context,
                MaterialPageRoute(builder: (_) => const LiveLoyaltyPage()),
              ),
            ),
            if (canSwitch)
              ListTile(
                leading: const Icon(Icons.swap_horiz),
                title:
                    Text('Switch to ${role == 'Renter' ? 'Owner' : 'Renter'}'),
                onTap: onSwitch,
              ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => onLogout(),
              icon: const Icon(Icons.logout),
              label: const Text('Log Out'),
            ),
          ],
        ),
      ),
    );
  }
}

class _LiveEditProfilePage extends StatefulWidget {
  const _LiveEditProfilePage(this.user);

  final User user;

  @override
  State<_LiveEditProfilePage> createState() => _LiveEditProfilePageState();
}

class _LiveEditProfilePageState extends State<_LiveEditProfilePage> {
  final formKey = GlobalKey<FormState>();
  late final name = TextEditingController(text: widget.user.name);
  late final phone = TextEditingController(text: widget.user.phone);
  bool saving = false;

  @override
  void dispose() {
    name.dispose();
    phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(formKey.currentState?.validate() ?? false)) return;
    setState(() => saving = true);
    try {
      await context.read<LiveRentHubController>().updateProfile(
            displayName: name.text,
            phone: phone.text,
          );
      if (mounted) Navigator.pop(context);
    } catch (exception) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(exception.toString())));
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Edit Profile')),
        body: SafeArea(
          child: Form(
            key: formKey,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                TextFormField(
                  controller: name,
                  decoration: (const InputDecoration(labelText: 'Display name'))
                      .copyWith(counterText: '', errorMaxLines: 3),
                  textInputAction: TextInputAction.next,
                  validator: InputValidation.compose(
                      InputRules.displayName.validate,
                      (value) => (value?.trim().length ?? 0) < 2
                          ? 'Enter at least 2 characters'
                          : null),
                  inputFormatters:
                      InputValidation.formatters(InputRules.displayName, name),
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  maxLength: InputRules.displayName.maxLength,
                  maxLengthEnforcement: InputValidation.lengthEnforcement,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: phone,
                  decoration: (const InputDecoration(
                    labelText: 'Phone number',
                    hintText: '+60 12-345 6789',
                  )).copyWith(counterText: '', errorMaxLines: 3),
                  keyboardType: TextInputType.phone,
                  validator: InputRules.phoneNumber.validate,
                  inputFormatters:
                      InputValidation.formatters(InputRules.phoneNumber, phone),
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  maxLength: InputRules.phoneNumber.maxLength,
                  maxLengthEnforcement: InputValidation.lengthEnforcement,
                ),
                const SizedBox(height: 8),
                Text(
                  'Email is managed by your sign-in identity and cannot be changed here.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: saving ? null : _save,
                  child: Text(saving ? 'Saving…' : 'Save Profile'),
                ),
              ],
            ),
          ),
        ),
      );
}

class _LiveAddressesPage extends StatelessWidget {
  const _LiveAddressesPage();

  Future<void> _persist(
    BuildContext context,
    List<UserAddress> addresses,
  ) async {
    try {
      await context.read<LiveRentHubController>().updateAddresses(addresses);
    } catch (exception) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(exception.toString())));
      }
    }
  }

  Future<void> _add(BuildContext context) async {
    final formKey = GlobalKey<FormState>();
    final label = TextEditingController(text: 'Home');
    final line1 = TextEditingController();
    final city = TextEditingController();
    final state = TextEditingController(text: 'Selangor');
    final postcode = TextEditingController();
    final address = await InputValidation.showFormDialog<UserAddress>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add Malaysian address'),
        content: SizedBox(
          width: 440,
          child: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final field in [
                    (label, 'Label', TextInputType.text),
                    (line1, 'Address line', TextInputType.streetAddress),
                    (city, 'City', TextInputType.text),
                    (state, 'State', TextInputType.text),
                    (postcode, 'Postcode', TextInputType.number),
                  ]) ...[
                    TextFormField(
                      controller: field.$1,
                      decoration: (InputDecoration(labelText: field.$2))
                          .copyWith(counterText: '', errorMaxLines: 3),
                      keyboardType: field.$3,
                      validator: InputValidation.compose(
                          InputRule(field.$2,
                                  kind: field.$2 == 'Postcode'
                                      ? InputKind.digits
                                      : InputKind.text,
                                  exactLength:
                                      field.$2 == 'Postcode' ? 5 : null,
                                  maxLength: field.$2 == 'Postcode'
                                      ? 5
                                      : field.$2 == 'Label'
                                          ? 40
                                          : field.$2 == 'Address line'
                                              ? 120
                                              : 80)
                              .validate, (value) {
                        if (value?.trim().isEmpty ?? true) {
                          return '${field.$2} is required';
                        }
                        if (field.$2 == 'Postcode' &&
                            !RegExp(r'^\d{5}$').hasMatch(value!.trim())) {
                          return 'Enter a 5-digit postcode';
                        }
                        return null;
                      }),
                      inputFormatters: InputValidation.formatters(
                          InputRule(field.$2,
                              kind: field.$2 == 'Postcode'
                                  ? InputKind.digits
                                  : InputKind.text,
                              exactLength: field.$2 == 'Postcode' ? 5 : null,
                              maxLength: field.$2 == 'Postcode'
                                  ? 5
                                  : field.$2 == 'Label'
                                      ? 40
                                      : field.$2 == 'Address line'
                                          ? 120
                                          : 80),
                          field.$1),
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                      maxLength: InputRule(field.$2,
                              kind: field.$2 == 'Postcode'
                                  ? InputKind.digits
                                  : InputKind.text,
                              exactLength: field.$2 == 'Postcode' ? 5 : null,
                              maxLength: field.$2 == 'Postcode'
                                  ? 5
                                  : field.$2 == 'Label'
                                      ? 40
                                      : field.$2 == 'Address line'
                                          ? 120
                                          : 80)
                          .maxLength,
                      maxLengthEnforcement: InputValidation.lengthEnforcement,
                    ),
                    const SizedBox(height: 12),
                  ],
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (!(formKey.currentState?.validate() ?? false)) return;
              InputValidation.popIfValid(
                dialogContext,
                UserAddress(
                  label: label.text.trim(),
                  line1: line1.text.trim(),
                  city: city.text.trim(),
                  state: state.text.trim(),
                  postcode: postcode.text.trim(),
                ),
              );
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
    for (final controller in [label, line1, city, state, postcode]) {
      controller.dispose();
    }
    if (address == null || !context.mounted) return;
    final existing = context.read<LiveRentHubController>().profile!.addresses;
    final added = address.copyWith(isDefault: existing.isEmpty);
    await _persist(context, [...existing, added]);
  }

  Future<void> _setDefault(BuildContext context, int index) async {
    final addresses = context
        .read<LiveRentHubController>()
        .profile!
        .addresses
        .indexed
        .map((entry) => entry.$2.copyWith(isDefault: entry.$1 == index))
        .toList();
    await _persist(context, addresses);
  }

  Future<void> _remove(BuildContext context, int index) async {
    final accepted = await confirmAction(
      context,
      title: 'Remove saved address?',
      message: 'This address will be removed from your RentHub profile.',
      action: 'Remove',
      destructive: true,
    );
    if (!accepted || !context.mounted) return;
    final addresses = [
      ...context.read<LiveRentHubController>().profile!.addresses,
    ]..removeAt(index);
    if (addresses.isNotEmpty && !addresses.any((item) => item.isDefault)) {
      addresses[0] = addresses[0].copyWith(isDefault: true);
    }
    await _persist(context, addresses);
  }

  @override
  Widget build(BuildContext context) {
    final addresses =
        context.watch<LiveRentHubController>().profile?.addresses ?? const [];
    return Scaffold(
      appBar: AppBar(title: const Text('Saved Addresses')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _add(context),
        icon: const Icon(Icons.add),
        label: const Text('Add Address'),
      ),
      body: SafeArea(
        child: addresses.isEmpty
            ? const RentHubFeedbackState(
                kind: FeedbackKind.empty,
                title: 'No saved addresses',
                message: 'Add an address for delivery and service bookings.',
              )
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                itemCount: addresses.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final address = addresses[index];
                  return Card(
                    child: ListTile(
                      leading: Icon(
                        address.isDefault
                            ? Icons.home
                            : Icons.location_on_outlined,
                      ),
                      title: Text(address.label),
                      subtitle: Text(
                        '${address.line1}\n${address.postcode} ${address.city}, ${address.state}',
                      ),
                      isThreeLine: true,
                      trailing: PopupMenuButton<String>(
                        onSelected: (action) => action == 'default'
                            ? _setDefault(context, index)
                            : _remove(context, index),
                        itemBuilder: (_) => [
                          if (!address.isDefault)
                            const PopupMenuItem(
                              value: 'default',
                              child: Text('Set as default'),
                            ),
                          const PopupMenuItem(
                            value: 'remove',
                            child: Text('Remove'),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}

class _LiveSettingsPage extends StatefulWidget {
  const _LiveSettingsPage(this.user);

  final User user;

  @override
  State<_LiveSettingsPage> createState() => _LiveSettingsPageState();
}

class _LiveSettingsPageState extends State<_LiveSettingsPage> {
  late String language = widget.user.language;
  late bool push = widget.user.pushNotifications;
  late bool email = widget.user.emailNotifications;
  bool saving = false;
  bool deactivating = false;

  Future<void> _save() async {
    setState(() => saving = true);
    try {
      await context.read<LiveRentHubController>().updateAccountSettings(
            language: language,
            pushNotifications: push,
            emailNotifications: email,
          );
      if (mounted) Navigator.pop(context);
    } catch (exception) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(exception.toString())));
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> _deactivate() async {
    final reason = TextEditingController();
    var confirmed = false;
    final accepted = await InputValidation.showFormDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          icon: const Icon(Icons.person_off_outlined, color: AppColors.error),
          title: const Text('Deactivate your account?'),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'You will be signed out, your active listings will be hidden, '
                  'and new access will be blocked. An administrator can reactivate '
                  'the account later.',
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: reason,
                  minLines: 2,
                  maxLines: 4,
                  maxLength: 500,
                  maxLengthEnforcement: InputValidation.lengthEnforcement,
                  onChanged: (_) => setDialogState(() {}),
                  decoration: (const InputDecoration(
                    labelText: 'Reason for leaving',
                    hintText: 'At least 5 characters',
                  )).copyWith(counterText: '', errorMaxLines: 3),
                  validator: InputRules.reasonForLeaving.validate,
                  inputFormatters: InputValidation.formatters(
                      InputRules.reasonForLeaving, reason),
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: confirmed,
                  title: const Text(
                    'I understand that I will lose access immediately.',
                  ),
                  onChanged: (value) =>
                      setDialogState(() => confirmed = value ?? false),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Keep Account'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.error),
              onPressed: confirmed && reason.text.trim().length >= 5
                  ? () => InputValidation.popIfValid(dialogContext, true)
                  : null,
              child: const Text('Deactivate Account'),
            ),
          ],
        ),
      ),
    );
    if (accepted != true || !mounted) {
      reason.dispose();
      return;
    }
    setState(() => deactivating = true);
    try {
      await context
          .read<LiveRentHubController>()
          .deactivateAccount(reason.text);
      if (mounted) await context.read<AuthController>().logout();
    } catch (exception) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(exception.toString())),
        );
      }
    } finally {
      reason.dispose();
      if (mounted) setState(() => deactivating = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Application Settings')),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              DropdownButtonFormField<String>(
                initialValue: language,
                decoration: const InputDecoration(labelText: 'Language'),
                items: const [
                  DropdownMenuItem(value: 'en', child: Text('English')),
                  DropdownMenuItem(
                    value: 'ms',
                    child: Text('Bahasa Melayu'),
                  ),
                ],
                onChanged: (value) => setState(() => language = value ?? 'en'),
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                value: push,
                title: const Text('Push notifications'),
                subtitle: const Text('Booking, message and rental updates'),
                onChanged: (value) => setState(() => push = value),
              ),
              SwitchListTile(
                value: email,
                title: const Text('Email notifications'),
                subtitle: const Text('Important account and payment updates'),
                onChanged: (value) => setState(() => email = value),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: saving ? null : _save,
                child: Text(saving ? 'Saving…' : 'Save Settings'),
              ),
              const SizedBox(height: 32),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: .05),
                  border: Border.all(
                    color: AppColors.error.withValues(alpha: .25),
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Deactivate account',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: AppColors.error,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Account access is disabled immediately. You cannot '
                      'deactivate while a booking, rental, or dispute is open.',
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.error,
                        side: const BorderSide(color: AppColors.error),
                      ),
                      onPressed: deactivating ? null : _deactivate,
                      icon: const Icon(Icons.person_off_outlined),
                      label: Text(
                        deactivating ? 'Deactivating…' : 'Deactivate Account',
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

class LiveVerificationPage extends StatefulWidget {
  const LiveVerificationPage({super.key, this.driving = false});
  final bool driving;

  @override
  State<LiveVerificationPage> createState() => _LiveVerificationPageState();
}

class _LiveVerificationPageState extends State<LiveVerificationPage> {
  String documentType = 'mykad';
  @override
  void initState() {
    super.initState();
    documentType = widget.driving ? 'driving_licence' : 'mykad';
  }

  bool submitting = false;
  final List<String> documentRefs = [];

  int get requiredDocuments => documentType == 'mykad' ? 2 : 1;

  String get documentLabel => switch (documentType) {
        'mykad' => 'MyKad',
        'passport' => 'Passport',
        'driving_licence' => 'Driving Licence',
        _ => 'Identity document',
      };

  Future<void> _scanDocument() async {
    if (documentRefs.length >= requiredDocuments) return;
    final controller = context.read<LiveRentHubController>();
    final side = documentType == 'mykad'
        ? (documentRefs.isEmpty ? 'MyKad Front' : 'MyKad Back')
        : documentLabel;
    final captured = await Navigator.push<KycCapturedDocument>(
      context,
      MaterialPageRoute(
        builder: (_) => LiveKycScannerPage(
          documentType: documentType,
          sideLabel: side,
          expectedSide: documentType == 'mykad'
              ? (documentRefs.isEmpty ? 'front' : 'back')
              : null,
          validateCapture: (bytes, type) => controller.inspectVerificationFrame(
            bytes,
            type,
            expectedSide: documentRefs.isEmpty ? 'front' : 'back',
            validateCapture: true,
          ),
          analyzeFrame: documentType == 'driving_licence'
              ? (_, __) async => {
                    'available': false,
                    'ready': false,
                    'guidance':
                        'Use manual capture for licence / MyJPJ evidence. Administrator review is required.'
                  }
              : (bytes, type) => controller.inspectVerificationFrame(
                    bytes,
                    type,
                    expectedSide: type == 'mykad'
                        ? (documentRefs.isEmpty ? 'front' : 'back')
                        : null,
                  ),
        ),
      ),
    );
    if (captured == null || !mounted) return;
    try {
      final reference = await controller.uploadVerificationCapture(
        captured.bytes,
        filename: captured.filename,
      );
      if (mounted) setState(() => documentRefs.add(reference));
    } catch (exception) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(exception.toString())));
      }
    }
  }

  Future<void> _pickDocument() async {
    if (documentRefs.length >= requiredDocuments) return;
    try {
      final reference =
          await pickAndPreviewUpload(context, purpose: 'verification_document');
      if (reference != null && mounted) {
        setState(() => documentRefs.add(reference));
      }
    } catch (exception) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(exception.toString())));
      }
    }
  }

  Future<void> _removeDocument(int index) async {
    final reference = documentRefs[index];
    try {
      await context.read<LiveRentHubController>().deleteUpload(reference);
      if (mounted) setState(() => documentRefs.remove(reference));
    } catch (exception) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(exception.toString())));
      }
    }
  }

  Future<void> _submit() async {
    if (documentRefs.length != requiredDocuments) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                'Upload $requiredDocuments document image${requiredDocuments == 1 ? '' : 's'} first.')),
      );
      return;
    }
    if (documentType == 'driving_licence' &&
        context
                .read<LiveRentHubController>()
                .profile
                ?.drivingEligibility
                .status ==
            'approved') {
      final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
                title: const Text('Submit updated driving evidence?'),
                content: const Text(
                    'Your previous review stays in history. Driving eligibility becomes pending until an administrator reviews the renewed licence or changed classes.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(dialogContext, false),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () =>
                          InputValidation.popIfValid(dialogContext, true),
                      child: const Text('Submit'))
                ],
              ));
      if (confirmed != true || !mounted) return;
    }
    setState(() => submitting = true);
    try {
      await context
          .read<LiveRentHubController>()
          .submitIdentityVerification(documentType, documentRefs);
    } catch (exception) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(exception.toString())));
      }
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<LiveRentHubController>().profile;
    final status = profile?.mykadStatus ?? 'unverified';
    final eligibility =
        profile?.drivingEligibility ?? const DrivingEligibility();
    final selectedStatus =
        documentType == 'driving_licence' ? eligibility.displayStatus : status;
    final canSubmit = documentType == 'driving_licence'
        ? selectedStatus != 'pending'
        : const [
            'unverified',
            'rejected',
            'resubmission_required',
            'expired',
          ].contains(selectedStatus);
    return Scaffold(
      appBar: AppBar(
          title: Text(documentType == 'driving_licence'
              ? 'Vehicle Driving Eligibility'
              : 'MyKad Identity Verification')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    const Icon(
                      Icons.verified_user_outlined,
                      size: 48,
                      color: AppColors.primary,
                    ),
                    const SizedBox(height: 12),
                    const Text('Identity Verification — MyKad'),
                    StatusBadge(status.replaceAll('_', ' ')),
                    const SizedBox(height: 16),
                    const Text('Vehicle Driving Eligibility'),
                    StatusBadge(eligibility.displayStatus.replaceAll('_', ' ')),
                    Text(
                        'Licence class: ${eligibility.licenceClasses.isEmpty ? 'Not reviewed' : eligibility.licenceClasses.join(', ')}'),
                    Text('Valid until: ${eligibility.validUntil}'),
                    if (eligibility.reviewNotes.isNotEmpty)
                      Text(eligibility.reviewNotes),
                    if (profile?.verificationDocuments
                            .containsKey('passport') ??
                        false)
                      Text(
                          'Legacy passport: ${profile!.verificationDocuments['passport']} (not required)'),
                    if (profile?.verificationReason.isNotEmpty ?? false) ...[
                      const SizedBox(height: 12),
                      Text(
                        profile!.verificationReason,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: documentType,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Verification flow'),
              items: const [
                DropdownMenuItem(value: 'mykad', child: Text('MyKad')),
                DropdownMenuItem(
                  value: 'driving_licence',
                  child: Text('Driving licence / MyJPJ evidence',
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ],
              onChanged: submitting
                  ? null
                  : (value) => setState(() {
                        documentType = value ?? 'mykad';
                        documentRefs.clear();
                      }),
            ),
            const SizedBox(height: 16),
            if (canSubmit) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        documentType == 'driving_licence'
                            ? 'Capture driving evidence'
                            : 'Live MyKad camera scan',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        documentType == 'driving_licence'
                            ? 'Provide your own licence or MyJPJ e-LMM screenshot. RentHub administrators review holder identity, class and validity. No JPJ API or QR validation.'
                            : 'Upload distinct MyKad front and back images. Both sides are analysed; final identity approval is by an administrator, not government authentication.',
                        style: TextStyle(color: AppColors.secondaryText),
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: submitting ||
                                documentRefs.length >= requiredDocuments
                            ? null
                            : _scanDocument,
                        icon: const Icon(Icons.document_scanner_outlined),
                        label: Text(
                          documentRefs.isEmpty
                              ? 'Start Live Scan'
                              : 'Scan Next Side',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.image_outlined),
                title: Text(
                  '${documentRefs.length} of $requiredDocuments document images uploaded',
                ),
                subtitle: const Text(
                  'Manual file upload is available as a development fallback. Files remain protected.',
                ),
                trailing: documentRefs.length < requiredDocuments
                    ? IconButton(
                        tooltip: 'Upload document image',
                        onPressed: submitting ? null : _pickDocument,
                        icon: const Icon(Icons.add_photo_alternate_outlined),
                      )
                    : const Icon(Icons.check_circle, color: AppColors.success),
              ),
              for (var index = 0; index < documentRefs.length; index++)
                PhotoAttachmentTile(
                  reference: documentRefs[index],
                  label: documentType == 'mykad'
                      ? (index == 0 ? 'MyKad front' : 'MyKad back')
                      : 'Driving licence / MyJPJ evidence',
                  onRemove: submitting ? null : () => _removeDocument(index),
                ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed:
                    submitting || documentRefs.length != requiredDocuments
                        ? null
                        : _submit,
                icon: const Icon(Icons.upload_file_outlined),
                label: Text(
                  submitting ? 'Submitting…' : 'Submit for Review',
                ),
              ),
            ] else if (selectedStatus == 'pending')
              RentHubFeedbackState(
                kind: FeedbackKind.loading,
                title: '$documentLabel review in progress',
                message:
                    'An administrator will review the submitted document images and verification details.',
              )
            else
              RentHubFeedbackState(
                kind: FeedbackKind.success,
                title: '$documentLabel verified',
                message: documentType == 'driving_licence'
                    ? 'Driving eligibility is approved. Vehicle requests still require approved MyKad, valid dates and any listing-specific licence class.'
                    : 'Your identity verification badge is active across RentHub.',
              ),
          ],
        ),
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/models/domain_models.dart';
import '../../shared/widgets/account_components.dart';
import '../../shared/widgets/renthub_components.dart';
import 'live_renthub_controller.dart';
import 'live_loyalty_page.dart';

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

  Future<void> _report(Message message) async {
    var reason = 'inappropriate';
    final details = TextEditingController();
    final accepted = await showDialog<bool>(
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
              TextField(
                controller: details,
                maxLength: 1000,
                decoration: const InputDecoration(
                  labelText: 'Details',
                  hintText: 'Explain what happened',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
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
                                    child: Text(message.text),
                                  ),
                                ),
                              );
                            },
                          ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                controller: input,
                enabled: !sending,
                maxLength: 2000,
                minLines: 1,
                maxLines: 4,
                onSubmitted: (_) => _send(),
                decoration: InputDecoration(
                  hintText: 'Write a message',
                  counterText: '',
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
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
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

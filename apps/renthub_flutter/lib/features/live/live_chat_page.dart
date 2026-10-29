import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/network/user_facing_error.dart';
import '../../core/network/idempotency_key.dart';
import '../../core/validation/input_validation.dart';
import '../../core/validation/input_rules.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/models/domain_models.dart';
import '../../shared/widgets/renthub_components.dart';
import '../../shared/widgets/account_components.dart';
import 'live_renthub_controller.dart';
import 'live_photo_widgets.dart';
import 'live_location_picker.dart';
import 'live_chat_location.dart';
import 'live_contact_profile.dart';

class LiveChatPage extends StatefulWidget {
  const LiveChatPage(
      {super.key, required this.conversation, this.locationMapBuilder});

  final Conversation conversation;
  final LocationMapBuilder? locationMapBuilder;

  @override
  State<LiveChatPage> createState() => _LiveChatPageState();
}

class _LiveChatPageState extends State<LiveChatPage> {
  final input = TextEditingController();
  final scroll = ScrollController();
  final messages = <Message>[];
  final removedIds = <String>{};
  StreamSubscription<Message>? subscription;
  bool loading = true;
  bool sending = false;
  String? error;
  String? sendError;
  String? account, before;
  bool hasMore = false, olderLoading = false;
  int generation = 0;
  ListingLocationSelection? pendingLocation;
  String? locationKey, textKey, keyText;
  String? get peerId => widget.conversation.otherParticipantId.isEmpty
      ? null
      : widget.conversation.otherParticipantId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      account = context.read<LiveRentHubController>().profile?.id;
      _load();
    });
  }

  Future<void> _load({bool older = false}) async {
    final controller = context.read<LiveRentHubController>();
    if (older && (olderLoading || !hasMore)) return;
    final request = ++generation;
    final versions = {for (final m in messages) m.id: m.revision};
    final oldOffset = scroll.hasClients ? scroll.offset : 0.0,
        oldExtent = scroll.hasClients ? scroll.position.maxScrollExtent : 0.0;
    bool current() =>
        mounted && request == generation && controller.profile?.id == account;
    setState(() {
      if (older) {
        olderLoading = true;
      } else {
        loading = messages.isEmpty;
      }
      error = null;
    });
    subscription ??= controller
        .watchThread(widget.conversation.id, peerId: peerId)
        .listen((message) => _addMessage(message));
    try {
      final loaded = await controller.loadMessagePage(widget.conversation.id,
          before: older ? before : null);
      if (!current()) return;
      unawaited(
          controller.markThreadRead(widget.conversation.id).catchError((_) {}));
      setState(() {
        final map = {for (final m in loaded.$1) m.id: m};
        for (final m in messages) {
          if (older ||
              !versions.containsKey(m.id) ||
              versions[m.id] != m.revision) {
            map[m.id] = m;
          }
        }
        map.removeWhere((id, _) => removedIds.contains(id));
        messages
          ..clear()
          ..addAll(map.values.toList()..sort(_order));
        hasMore = loaded.$2;
        before = loaded.$3;
        loading = false;
        olderLoading = false;
        error = null;
      });
      if (!older) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && scroll.hasClients) {
            scroll.jumpTo(scroll.position.maxScrollExtent);
          }
        });
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && scroll.hasClients) {
            scroll.jumpTo(
                (oldOffset + scroll.position.maxScrollExtent - oldExtent)
                    .clamp(0.0, scroll.position.maxScrollExtent));
          }
        });
      }
    } catch (exception) {
      if (!current()) return;
      setState(() {
        loading = false;
        olderLoading = false;
        error = friendlyError(exception);
      });
    }
  }

  void _addMessage(Message message) {
    if (!mounted ||
        context.read<LiveRentHubController>().profile?.id != account) {
      return;
    }
    setState(() {
      final index = messages.indexWhere((item) => item.id == message.id);
      if (message.deletedForMe) {
        removedIds.add(message.id);
        messages.removeWhere((m) => m.id == message.id);
        return;
      }
      if (removedIds.contains(message.id)) return;
      if (index >= 0 && message.revision < messages[index].revision) return;
      if (index >= 0) {
        messages[index] = message;
      } else {
        messages.add(message);
      }
      messages.sort(_order);
    });
  }

  int _order(Message a, Message b) {
    final d = (a.createdAt ?? DateTime(1970))
        .compareTo(b.createdAt ?? DateTime(1970));
    return d == 0 ? a.id.compareTo(b.id) : d;
  }

  Future<void> _sendLocation() async {
    final c = context.read<LiveRentHubController>();
    final location = pendingLocation ??
        await Navigator.push<ListingLocationSelection>(
            context,
            MaterialPageRoute(
                builder: (_) => LiveLocationPicker(
                    api: ListingLocationApi(c.api),
                    mapBuilder: widget.locationMapBuilder,
                    confirmationLabel: 'Share location',
                    notice:
                        'This exact pin will be shared with ${widget.conversation.otherParticipantName}.',
                    title: 'Share a location')));
    if (!mounted || location == null || c.profile?.id != account) return;
    setState(() => pendingLocation = location);
    locationKey ??=
        newCheckoutIdempotencyKey().replaceFirst('checkout:', 'message:');
    setState(() {
      sending = true;
      sendError = null;
    });
    try {
      final msg = await c.sendMessage(widget.conversation.id, '',
          clientMessageId: locationKey,
          location: MessageLocation(location.point.latitude,
              location.point.longitude, location.label));
      _addMessage(msg);
      if (mounted) {
        setState(() {
          pendingLocation = null;
          locationKey = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => sendError = friendlyError(e));
      }
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Future<void> _actions(Message message) async {
    final own = message.senderId == account;
    final action = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        builder: (c) => SafeArea(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (own && message.canChange && message.text.isNotEmpty)
                ListTile(
                    leading: const Icon(Icons.edit_outlined),
                    title: const Text('Edit message'),
                    onTap: () => Navigator.pop(c, 'edit')),
              if (own && message.canChange)
                ListTile(
                    leading: const Icon(Icons.undo),
                    title: const Text('Recall for everyone'),
                    onTap: () => Navigator.pop(c, 'recall')),
              ListTile(
                  leading: const Icon(Icons.delete_outline),
                  title: const Text('Delete for me'),
                  onTap: () => Navigator.pop(c, 'delete')),
              if (!own && message.recalledAt == null)
                ListTile(
                    leading: const Icon(Icons.flag_outlined),
                    title: const Text('Report message'),
                    onTap: () => Navigator.pop(c, 'report')),
            ])));
    if (!mounted || action == null) return;
    if (action == 'report') {
      await _report(message);
      return;
    }
    String? edited;
    if (action == 'edit') {
      final draft = TextEditingController(text: message.text);
      edited = await InputValidation.showFormDialog<String>(
          context: context,
          builder: (dialog) => AlertDialog(
                  title: const Text('Edit message'),
                  content: TextFormField(
                      controller: draft,
                      minLines: 2,
                      maxLines: 5,
                      maxLength: 2000,
                      validator: InputRules.writeAMessage.validate),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(dialog),
                        child: const Text('Cancel')),
                    FilledButton(
                        onPressed: () => InputValidation.popIfValid(
                            dialog, draft.text.trim()),
                        child: const Text('Save'))
                  ]));
      draft.dispose();
      if (edited == null || edited.isEmpty) return;
    } else {
      final accepted = await confirmAction(context,
          title: action == 'delete'
              ? 'Delete this message for you?'
              : 'Recall this message?',
          message: action == 'delete'
              ? 'The other person will still have their copy.'
              : 'Both participants will see “Message recalled”. Previously received notifications or screenshots cannot be removed.',
          action: action == 'delete' ? 'Delete for me' : 'Recall',
          destructive: true);
      if (!accepted) return;
    }
    if (!mounted) return;
    try {
      final updated = await context
          .read<LiveRentHubController>()
          .changeMessage(message, action, text: edited);
      if (!mounted) return;
      if (updated == null) {
        removedIds.add(message.id);
        setState(() => messages.removeWhere((m) => m.id == message.id));
      } else {
        _addMessage(updated);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    }
  }

  Future<void> _send() async {
    if (!InputValidation.validate(context)) return;
    final text = input.text.trim();
    if (text.isEmpty || sending) return;
    if (keyText != text) {
      keyText = text;
      textKey =
          newCheckoutIdempotencyKey().replaceFirst('checkout:', 'message:');
    }
    setState(() {
      sending = true;
      sendError = null;
    });
    try {
      final message = await context
          .read<LiveRentHubController>()
          .sendMessage(widget.conversation.id, text, clientMessageId: textKey);
      if (!mounted) return;
      if (input.text.trim() == text) input.clear();
      textKey = null;
      keyText = null;
      _addMessage(message);
    } catch (exception) {
      if (mounted) {
        setState(() => sendError = friendlyError(exception));
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
          SnackBar(content: Text(friendlyError(exception))),
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
          SnackBar(content: Text(friendlyError(exception))),
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
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ownId = context.watch<LiveRentHubController>().profile?.id;
    if (account != null && ownId != account) {
      return Scaffold(
          appBar: AppBar(title: const Text('Conversation')),
          body: const Center(
              child: Text(
                  'Your session changed. Return to Messages to continue.')));
    }
    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
              tooltip: 'Refresh conversation',
              onPressed: loading ? null : () => _load(),
              icon: const Icon(Icons.refresh))
        ],
        title: InkWell(
            onTap: () => Navigator.push<void>(
                context,
                MaterialPageRoute(
                    builder: (_) => LiveContactProfilePage(
                        threadId: widget.conversation.id))),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.conversation.otherParticipantName,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(
                  'Tap to view profile',
                  style: const TextStyle(fontSize: 11),
                ),
              ],
            )),
      ),
      body: Column(
        children: [
          if (error != null && messages.isNotEmpty)
            MaterialBanner(content: Text(error!), actions: [
              TextButton(onPressed: () => _load(), child: const Text('Retry'))
            ]),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : error != null && messages.isEmpty
                    ? RentHubFeedbackState(
                        kind: FeedbackKind.error,
                        title: 'Conversation unavailable',
                        message: error!,
                        actionLabel: 'Try Again',
                        onAction: () => _load(),
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
                            controller: scroll,
                            itemCount: messages.length + 1,
                            itemBuilder: (context, index) {
                              if (index == 0) {
                                return Center(
                                    child: olderLoading
                                        ? const Padding(
                                            padding: EdgeInsets.all(12),
                                            child: CircularProgressIndicator())
                                        : hasMore
                                            ? TextButton.icon(
                                                onPressed: () =>
                                                    _load(older: true),
                                                icon: const Icon(Icons.history),
                                                label: const Text(
                                                    'Load earlier messages'))
                                            : const SizedBox.shrink());
                              }
                              final message = messages[index - 1];
                              final own = message.senderId == ownId;
                              return Align(
                                alignment: own
                                    ? Alignment.centerRight
                                    : Alignment.centerLeft,
                                child: GestureDetector(
                                  onLongPress: () => _actions(message),
                                  onSecondaryTap: () => _actions(message),
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
                                        if (message.recalledAt != null)
                                          const Text('Message recalled',
                                              style: TextStyle(
                                                  fontStyle: FontStyle.italic)),
                                        if (message.recalledAt == null &&
                                            message.attachment?.kind == 'image')
                                          _ProtectedMessageImage(
                                            attachment: message.attachment!,
                                          ),
                                        if (message.attachment != null &&
                                            message.text.isNotEmpty)
                                          const SizedBox(height: 8),
                                        if (message.recalledAt == null &&
                                            message.location != null)
                                          TextButton.icon(
                                              onPressed: () => Navigator.push<
                                                      void>(
                                                  context,
                                                  MaterialPageRoute(
                                                      builder: (_) =>
                                                          LiveSharedLocationPage(
                                                              location: message
                                                                  .location!))),
                                              icon: const Icon(
                                                  Icons.location_on_outlined),
                                              label: Text(
                                                  message.location!.label)),
                                        if (message.recalledAt == null &&
                                            message.text.isNotEmpty)
                                          Text(message.text),
                                        if (message.editedAt != null &&
                                            message.recalledAt == null)
                                          const Text('Edited',
                                              style: TextStyle(
                                                  fontSize: 11,
                                                  color:
                                                      AppColors.secondaryText)),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
          ),
          if (sendError != null)
            Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(children: [
                  const Icon(Icons.error_outline, color: AppColors.error),
                  const SizedBox(width: 8),
                  Expanded(child: Text(sendError!)),
                  IconButton(
                      tooltip: 'Dismiss message error',
                      onPressed: () => setState(() => sendError = null),
                      icon: const Icon(Icons.close))
                ])),
          if (pendingLocation != null)
            Card(
                child: ListTile(
                    leading: const Icon(Icons.location_on_outlined),
                    title: Text(pendingLocation!.label,
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                    subtitle: const Text('Location not sent yet'),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(
                          tooltip: 'Retry sharing location',
                          onPressed: sending ? null : _sendLocation,
                          icon: const Icon(Icons.send)),
                      IconButton(
                          tooltip: 'Remove selected location',
                          onPressed: sending
                              ? null
                              : () => setState(() {
                                    pendingLocation = null;
                                    locationKey = null;
                                  }),
                          icon: const Icon(Icons.close))
                    ]))),
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
                  prefixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(
                      tooltip: 'Send image',
                      onPressed: sending ? null : _sendImage,
                      icon: const Icon(Icons.add_photo_alternate_outlined),
                    ),
                    IconButton(
                        tooltip: 'Share location',
                        onPressed: sending ? null : _sendLocation,
                        icon: const Icon(Icons.location_on_outlined))
                  ]),
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

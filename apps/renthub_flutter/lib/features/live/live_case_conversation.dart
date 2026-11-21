import 'live_chat_bubble.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/network/api_client.dart';
import '../../core/network/idempotency_key.dart';
import '../../core/network/user_facing_error.dart';
import '../../core/theme/app_theme.dart';
import 'admin_record_models.dart' show adminDate;
import 'live_photo_widgets.dart';
import 'live_renthub_controller.dart';

/// One case-scoped conversation shared by the participants and admin team.
class CaseConversation extends StatefulWidget {
  const CaseConversation(
      {super.key,
      required this.disputeId,
      this.onStatusChanged,
      this.fillHeight = false});
  final String disputeId;
  final VoidCallback? onStatusChanged;
  final bool fillHeight;
  @override
  State<CaseConversation> createState() => _CaseConversationState();
}

class _CaseConversationState extends State<CaseConversation>
    with WidgetsBindingObserver {
  final text = TextEditingController();
  final scroll = ScrollController();
  final List<String> evidence = [];
  List<Map<String, dynamic>> messages = [];
  late LiveRentHubController controller;
  late int account;
  late String? viewer;
  String? cursor, status, sendKey, sendSignature;
  Object? error, sendError;
  bool loading = false,
      sending = false,
      uploading = false,
      pendingRefresh = false;
  int request = 0;
  StreamSubscription<dynamic>? subscription;
  Timer? fallback;
  bool foreground = true;
  bool get allowed =>
      controller.accountGeneration == account &&
      controller.profile?.id == viewer;
  bool get closed => status == 'resolved' || status == 'dismissed';

  @override
  void initState() {
    super.initState();
    controller = context.read<LiveRentHubController>();
    account = controller.accountGeneration;
    viewer = controller.profile?.id;
    WidgetsBinding.instance.addObserver(this);
    subscription =
        controller.watchCase(widget.disputeId).listen((_) => refresh());
    fallback = Timer.periodic(const Duration(seconds: 30), (_) {
      if (foreground && !closed) refresh();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => refresh());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    if (foreground) refresh();
  }

  Future<void> refresh({bool earlier = false}) async {
    if (!mounted || !allowed || !foreground) return;
    if (loading) {
      if (!earlier) pendingRefresh = true;
      return;
    }
    final generation = ++request;
    final oldOffset = scroll.hasClients ? scroll.offset : 0.0;
    final oldExtent = scroll.hasClients ? scroll.position.maxScrollExtent : 0.0;
    final followLatest = messages.isEmpty || oldExtent - oldOffset < 80;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = await controller.api.request('GET',
          '/messages/cases/${widget.disputeId}/messages?limit=20${earlier && cursor != null ? '&before=${Uri.encodeQueryComponent(cursor!)}' : ''}');
      if (!mounted || !allowed || generation != request) return;
      if (result is! ApiItems) {
        throw const FormatException('Invalid conversation');
      }
      final incoming =
          result.map((row) => Map<String, dynamic>.from(row as Map)).toList();
      final changed = status != result.meta['status'];
      setState(() {
        final previous = messages;
        // Reconnection can contain a gap. Reset to a contiguous latest page
        // rather than silently presenting incomplete history as continuous.
        final overlap = incoming
            .any((row) => previous.any((old) => old['id'] == row['id']));
        final keep = earlier || overlap ? previous : <Map<String, dynamic>>[];
        final combined = {
          for (final row in keep) '${row['id']}': row,
          for (final row in incoming) '${row['id']}': row
        };
        messages = combined.values.toList()
          ..sort((a, b) {
            final time = (DateTime.tryParse('${a['createdAt']}') ??
                    DateTime.fromMillisecondsSinceEpoch(0))
                .compareTo(DateTime.tryParse('${b['createdAt']}') ??
                    DateTime.fromMillisecondsSinceEpoch(0));
            return time != 0 ? time : '${a['id']}'.compareTo('${b['id']}');
          });
        if (earlier || !overlap || previous.isEmpty) {
          cursor = result.meta['nextCursor'] as String?;
        }
        status = result.meta['status'] as String?;
      });
      if (!earlier && result.meta['readThroughAt'] is String) {
        unawaited(markRead(result.meta['readThroughAt'] as String));
      }
      if (changed) widget.onStatusChanged?.call();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !allowed || !scroll.hasClients) return;
        if (earlier) {
          scroll.jumpTo(
              (oldOffset + scroll.position.maxScrollExtent - oldExtent)
                  .clamp(0, scroll.position.maxScrollExtent));
        } else if (followLatest) {
          scroll.jumpTo(scroll.position.maxScrollExtent);
        }
      });
    } catch (e) {
      if (mounted && allowed && generation == request) {
        setState(() {
          error = e;
          if (e is ApiException && [401, 403, 404].contains(e.status)) {
            messages = [];
            status = null;
          }
        });
      }
    } finally {
      if (mounted && allowed && generation == request) {
        setState(() => loading = false);
        if (pendingRefresh) {
          pendingRefresh = false;
          unawaited(refresh());
        }
      }
    }
  }

  Future<void> markRead(String through) async {
    try {
      await controller.api.request(
          'POST', '/messages/cases/${widget.disputeId}/read',
          body: {'readThroughAt': through});
      if (mounted && allowed) await controller.refreshNotificationActivity();
    } catch (_) {/* Reading a message does not depend on its read receipt. */}
  }

  Future<void> attach() async {
    if (uploading || sending || closed || !allowed || evidence.length >= 10) {
      return;
    }
    setState(() => uploading = true);
    try {
      final ref = await pickAndPreviewUpload(context,
          purpose: 'dispute_evidence', allowPdf: true);
      if (mounted && allowed && ref != null) setState(() => evidence.add(ref));
    } catch (e) {
      if (mounted && allowed) setState(() => sendError = e);
    } finally {
      if (mounted && allowed) setState(() => uploading = false);
    }
  }

  Future<void> send() async {
    if (!allowed ||
        sending ||
        uploading ||
        closed ||
        status == null ||
        text.text.trim().isEmpty && evidence.isEmpty) {
      return;
    }
    final draft = text.text.trim();
    final refs = List<String>.of(evidence);
    final signature = jsonEncode([draft, refs]);
    if (sendSignature != signature) {
      sendSignature = signature;
      sendKey = newCheckoutIdempotencyKey().replaceAll(':', '-');
    }
    setState(() {
      sending = true;
      sendError = null;
    });
    try {
      await controller.api.request(
          'POST', '/messages/cases/${widget.disputeId}/messages',
          body: {
            'text': draft,
            'evidence': refs,
            'idempotencyKey': sendKey,
          });
      if (!mounted || !allowed) return;
      setState(() {
        text.clear();
        evidence.clear();
        sendKey = null;
        sendSignature = null;
      });
      await refresh();
    } catch (e) {
      if (mounted && allowed) {
        setState(() => sendError = e);
        // Keep the original send key and draft after an uncertain response.
        await refresh();
      }
    } finally {
      if (mounted && allowed) setState(() => sending = false);
    }
  }

  @override
  void dispose() {
    request++;
    fallback?.cancel();
    subscription?.cancel();
    if (allowed) controller.leaveCase(widget.disputeId);
    WidgetsBinding.instance.removeObserver(this);
    text.dispose();
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    context.watch<LiveRentHubController>();
    if (!allowed) return const Text('This conversation is unavailable.');
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(
            child: Text('Case conversation',
                style: Theme.of(context).textTheme.titleMedium)),
        IconButton(
            tooltip: 'Refresh conversation',
            onPressed: loading ? null : () => refresh(),
            icon: const Icon(Icons.refresh)),
      ]),
      const Text('Renter · Owner · Admin',
          style: TextStyle(color: AppColors.secondaryText)),
      if (loading) const LinearProgressIndicator(),
      if (error != null)
        TextButton(
            onPressed: () => refresh(),
            child: Text('${friendlyError(error!)} Retry')),
      if (cursor != null)
        TextButton(
            onPressed: loading ? null : () => refresh(earlier: true),
            child: const Text('Earlier messages')),
      if (!loading && error == null && messages.isEmpty)
        const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text('Discuss this case here.')),
      if (widget.fillHeight)
        Expanded(
            child: ListView.builder(
                controller: scroll,
                itemCount: messages.length,
                itemBuilder: (_, index) => _bubble(messages[index])))
      else
        for (final row in messages) _bubble(row),
      if (closed)
        const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text('Case closed'))
      else ...[
        const SizedBox(height: 12),
        TextField(
            controller: text,
            minLines: 1,
            maxLines: 4,
            maxLength: 2000,
            enabled: !sending && status != null,
            decoration: const InputDecoration(
                labelText: 'Message',
                hintText: 'Write to the case participants',
                counterText: '')),
        for (var i = 0; i < evidence.length; i++)
          PhotoAttachmentTile(
              reference: evidence[i],
              label: 'Attachment ${i + 1}',
              onRemove:
                  sending ? null : () => setState(() => evidence.removeAt(i))),
        if (sendError != null)
          Text(friendlyError(sendError!),
              style: const TextStyle(color: AppColors.error)),
        Wrap(alignment: WrapAlignment.end, spacing: 8, children: [
          IconButton(
              tooltip: 'Attach evidence',
              onPressed: sending ||
                      uploading ||
                      status == null ||
                      evidence.length >= 10
                  ? null
                  : attach,
              icon: const Icon(Icons.attach_file)),
          FilledButton.icon(
              onPressed: sending || uploading || status == null ? null : send,
              icon: const Icon(Icons.send_outlined),
              label: Text(sending ? 'Sending…' : 'Send')),
        ]),
      ],
    ]);
  }

  Widget _bubble(Map<String, dynamic> row) {
    final system = row['kind'] == 'system';
    final mine = row['senderId'] == viewer;
    final role = switch (row['role']) {
      'owner' => 'Owner',
      'renter' => 'Renter',
      'admin' => 'Admin',
      _ => 'RentHub'
    };
    return Align(
        alignment: system
            ? Alignment.center
            : mine
                ? Alignment.centerRight
                : Alignment.centerLeft,
        child: ChatBubbleFrame(
            own: mine,
            system: system,
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!system)
                    Text('${row['senderName'] ?? 'Not available'} · $role',
                        style: Theme.of(context).textTheme.labelLarge),
                  if ('${row['text'] ?? ''}'.isNotEmpty) Text('${row['text']}'),
                  for (final ref in (row['evidence'] as List? ?? []))
                    PhotoAttachmentTile(
                        reference: '$ref', label: 'Case evidence'),
                  const SizedBox(height: 4),
                  Text(adminDate(row['createdAt']),
                      style: Theme.of(context).textTheme.labelSmall),
                ])));
  }
}

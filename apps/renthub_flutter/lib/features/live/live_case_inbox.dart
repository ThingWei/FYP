import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/network/user_facing_error.dart';
import '../../shared/widgets/renthub_components.dart';
import 'admin_record_models.dart' show adminDate;
import 'live_case_navigation.dart';
import 'live_renthub_controller.dart';
import 'user_record_pagination.dart';

class CaseInbox extends StatefulWidget {
  const CaseInbox({super.key});
  @override
  State<CaseInbox> createState() => _CaseInboxState();
}

class _CaseInboxState extends State<CaseInbox> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) refresh();
    });
  }

  Future<void> refresh() async {
    try {
      await context
          .read<LiveRentHubController>()
          .loadUserRecords('case-conversations');
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<LiveRentHubController>(),
        rows = context.watch<LiveRentHubController>().caseConversations;
    final page = c.userRecordPages['case-conversations'];
    return Column(children: [
      const UserRecordToolbar(collection: 'case-conversations'),
      if (page?.loading == true) const LinearProgressIndicator(),
      Expanded(
          child: RefreshIndicator(
              onRefresh: refresh,
              child: rows.isEmpty
                  ? ListView(children: [
                      Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(children: [
                            Text(page?.error != null
                                ? friendlyError(page!.error!)
                                : page?.loading == true
                                    ? 'Loading conversations'
                                    : 'No case conversations'),
                            TextButton(
                                onPressed: refresh,
                                child: const Text('Refresh'))
                          ]))
                    ])
                  : ListView.separated(
                      itemCount: rows.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final row = rows[index],
                            unread =
                                (rows[index]['unreadCount'] as num?)?.toInt() ??
                                    0;
                        return ListTile(
                            leading: Badge(
                                isLabelVisible: unread > 0,
                                label: Text('$unread'),
                                child: const CircleAvatar(
                                    child: Icon(Icons.forum_outlined))),
                            title: Text('${row['listingTitle'] ?? 'Case'}',
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('${row['lastMessageText'] ?? ''}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis),
                                  Text(adminDate(row['lastMessageAt']),
                                      style:
                                          Theme.of(context).textTheme.bodySmall)
                                ]),
                            trailing: StatusBadge(['resolved', 'dismissed']
                                    .contains(row['status'])
                                ? 'Closed'
                                : 'Open'),
                            onTap: () async {
                              await openCaseConversation(
                                  context, '${row['id']}',
                                  title:
                                      '${row['listingTitle'] ?? 'Case conversation'}');
                              if (mounted) await refresh();
                            });
                      }))),
      const UserRecordPagination(collection: 'case-conversations'),
    ]);
  }
}

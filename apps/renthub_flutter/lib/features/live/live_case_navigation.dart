import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../shared/models/domain_models.dart';
import '../../core/network/user_facing_error.dart';
import 'admin_case_workspace.dart';
import 'live_chat_page.dart';
import 'live_dispute_page.dart';
import 'live_renthub_controller.dart';

Future<void> openCaseConversation(BuildContext context, String id,
        {String title = 'Case conversation'}) =>
    Navigator.push<void>(
        context,
        MaterialPageRoute(
            builder: (_) =>
                LiveChatPage.forCase(disputeId: id, caseTitle: title)));

Future<void> openCaseManagement(BuildContext context, String id) async {
  final c = context.read<LiveRentHubController>(),
      account = context.read<LiveRentHubController>().accountGeneration;
  if (c.profile?.roles.contains(UserRole.admin) == true) {
    await openAdminCase(context, disputeId: id);
    return;
  }
  try {
    final row = await c.loadDisputeCase(id);
    final rental = await c.api.request(
        'GET', '/rentals/${Uri.encodeComponent('${row['rentalId']}')}');
    if (!context.mounted || c.accountGeneration != account) return;
    final value = Rental.fromJson(Map<String, dynamic>.from(rental as Map));
    c.disputes = [
      ...c.disputes.where((r) => r.id != id),
      Dispute.fromJson(row)
    ];
    await Navigator.push<void>(
        context,
        MaterialPageRoute(
            builder: (_) => LiveDisputePage(
                rental: value, owner: value.ownerId == c.profile?.id)));
  } catch (error) {
    if (context.mounted && c.accountGeneration == account) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(friendlyError(error))));
    }
  }
}

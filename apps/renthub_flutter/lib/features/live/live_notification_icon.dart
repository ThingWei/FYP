import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import 'live_renthub_controller.dart';

/// Unread state belongs to the account, not the currently visible inbox page.
class LiveNotificationIcon extends StatelessWidget {
  const LiveNotificationIcon({super.key});

  @override
  Widget build(BuildContext context) => Selector<LiveRentHubController, bool>(
      selector: (_, controller) => controller.hasUnreadNotifications,
      builder: (_, unread, __) => Semantics(
          label: unread ? 'Unread notifications' : 'No unread notifications',
          child: Badge(
              key: const ValueKey('notification-unread-badge'),
              isLabelVisible: unread,
              backgroundColor: AppColors.error,
              smallSize: 8,
              child: const Icon(Icons.notifications_outlined))));
}

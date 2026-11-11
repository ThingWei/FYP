import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import 'live_renthub_controller.dart';

enum NavigationActivity { requests, listings, bookings, messages }

class LiveActivityIcon extends StatelessWidget {
  const LiveActivityIcon(
      {super.key, required this.activity, required this.icon});
  final NavigationActivity activity;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Selector<LiveRentHubController, bool>(
      selector: (_, controller) => switch (activity) {
            NavigationActivity.requests => controller.hasPendingOwnerRequests,
            NavigationActivity.listings => controller.hasListingAttention,
            NavigationActivity.bookings => controller.hasBookingActivity,
            NavigationActivity.messages => controller.hasUnreadMessages,
          },
      builder: (_, attention, __) => Semantics(
          label: attention
              ? switch (activity) {
                  NavigationActivity.requests => 'Pending booking requests',
                  NavigationActivity.listings =>
                    'Listings awaiting review or attention',
                  NavigationActivity.bookings =>
                    'Booking updates or payment needed',
                  NavigationActivity.messages => 'Unread messages',
                }
              : null,
          child: Badge(
              key: ValueKey('navigation-${activity.name}-badge'),
              isLabelVisible: attention,
              backgroundColor: AppColors.error,
              smallSize: 8,
              child: Icon(icon))));
}

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

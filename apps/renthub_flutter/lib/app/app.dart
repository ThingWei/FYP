import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/theme/app_theme.dart';
import '../core/config/backend_mode.dart';
import '../core/notifications/push_notification_service.dart';
import '../core/persistence/onboarding_preferences.dart';
import '../features/live/live_renthub_controller.dart';
import '../features/live/live_shared_pages.dart';
import '../features/live/live_owner_shell.dart';
import '../features/live/live_renter_shell.dart';
import '../features/live/live_dispute_page.dart';
import '../features/live/live_loyalty_page.dart';
import '../features/owner/owner_app.dart';
import '../features/onboarding/onboarding_flow.dart';
import '../features/renter/renter_app.dart';
import '../modules/user/controllers/auth_controller.dart';
import '../modules/user/views/login_screen.dart';
import '../shared/models/domain_models.dart';

class RentHubApp extends StatefulWidget {
  const RentHubApp({
    super.key,
    this.showIntroduction = true,
    this.markOnboardingCompleted = OnboardingPreferences.markCompleted,
  });

  // Nullable so a hot reload from a build that predates this field can safely
  // migrate the existing widget instance. New instances still default to true.
  final bool? showIntroduction;
  final Future<void> Function() markOnboardingCompleted;

  @override
  State<RentHubApp> createState() => _RentHubAppState();
}

enum _EntryStage { splash, onboarding, application }

class _RentHubAppState extends State<RentHubApp> {
  final messengerKey = GlobalKey<ScaffoldMessengerState>();
  final navigatorKey = GlobalKey<NavigatorState>();
  StreamSubscription<PushNotificationEvent>? pushSubscription;
  late _EntryStage stage = (widget.showIntroduction ?? true)
      ? _EntryStage.splash
      : _EntryStage.application;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      PushNotificationService push;
      try {
        push = context.read<PushNotificationService>();
      } on ProviderNotFoundException {
        return;
      }
      pushSubscription = push.events.listen(_handlePush);
      final initial = push.takeInitialEvent();
      if (initial != null) _handlePush(initial);
    });
  }

  void _handlePush(PushNotificationEvent event) {
    if (!mounted) return;
    final auth = context.read<AuthController>();
    if (auth.authenticated && !BackendMode.useMocks) {
      unawaited(_refreshNotifications());
      if (event.openedFromNotification) {
        final controller = context.read<LiveRentHubController>();
        navigatorKey.currentState?.push<void>(
          MaterialPageRoute(
            builder: (_) => _pushDestination(
              event,
              auth.selectedRole,
              controller,
            ),
          ),
        );
      }
    }
    messengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Text('${event.title}: ${event.body}'),
      ),
    );
  }

  Widget _pushDestination(
    PushNotificationEvent event,
    UserRole role,
    LiveRentHubController controller,
  ) {
    final type = event.data['entityType']?.toString() ?? '';
    final id = event.data['entityId']?.toString() ?? '';
    if (type == 'thread') {
      final matches = controller.conversations.where((item) => item.id == id);
      return matches.isEmpty
          ? const LiveMessagesPage()
          : LiveChatPage(conversation: matches.first);
    }
    if (type == 'booking' || type == 'rental' || type == 'payment') {
      return role == UserRole.owner
          ? const LiveOwnerRequestsPage()
          : const LiveRenterBookingsPage();
    }
    if (type == 'dispute') {
      final disputes = controller.disputes.where((item) => item.id == id);
      if (disputes.isNotEmpty) {
        final rentals = controller.rentals.where(
          (item) => item.id == disputes.first.rentalId,
        );
        if (rentals.isNotEmpty) {
          return LiveDisputePage(
            rental: rentals.first,
            owner: role == UserRole.owner,
          );
        }
      }
    }
    if (type == 'reward' || type == 'referral') {
      return const LiveLoyaltyPage();
    }
    return const LiveNotificationsPage();
  }

  Future<void> _refreshNotifications() async {
    try {
      await context.read<LiveRentHubController>().loadNotifications();
    } catch (_) {}
  }

  Future<void> _completeOnboarding() async {
    try {
      await widget.markOnboardingCompleted();
    } catch (_) {}
    if (mounted) setState(() => stage = _EntryStage.application);
  }

  @override
  void dispose() {
    pushSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'RentHub',
        navigatorKey: navigatorKey,
        scaffoldMessengerKey: messengerKey,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        builder: (context, child) => ColoredBox(
          color: AppColors.surface,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: ColoredBox(
                color: AppColors.surface,
                child: child ?? const SizedBox.shrink(),
              ),
            ),
          ),
        ),
        home: switch (stage) {
          _EntryStage.splash => SplashScreen(
              onFinished: () => setState(() => stage = _EntryStage.onboarding),
            ),
          _EntryStage.onboarding => OnboardingPage(
              onFinished: () => unawaited(_completeOnboarding()),
            ),
          _EntryStage.application => Consumer<AuthController>(
              builder: (_, auth, __) {
                if (!auth.authenticated) return const LoginScreen();
                final canSwitch = auth.user!.roles.contains(UserRole.renter) &&
                    auth.user!.roles.contains(UserRole.owner);
                void switchRole() => unawaited(
                      auth
                          .selectRole(
                        auth.selectedRole == UserRole.renter
                            ? UserRole.owner
                            : UserRole.renter,
                      )
                          .catchError((Object error) {
                        messengerKey.currentState?.showSnackBar(
                          SnackBar(content: Text(error.toString())),
                        );
                      }),
                    );
                if (!BackendMode.useMocks) {
                  return auth.selectedRole == UserRole.owner
                      ? LiveOwnerShell(
                          canSwitch: canSwitch,
                          onSwitchRole: switchRole,
                          onLogout: auth.logout,
                        )
                      : LiveRenterShell(
                          canSwitch: canSwitch,
                          onSwitchRole: switchRole,
                          onLogout: auth.logout,
                        );
                }
                return auth.selectedRole == UserRole.owner
                    ? OwnerShell(canSwitch: canSwitch, onSwitchRole: switchRole)
                    : RenterShell(
                        canSwitch: canSwitch,
                        onSwitchRole: switchRole,
                      );
              },
            ),
        },
      );
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/theme/app_theme.dart';
import '../core/config/backend_mode.dart';
import '../features/live/live_owner_shell.dart';
import '../features/live/live_renter_shell.dart';
import '../features/owner/owner_app.dart';
import '../features/onboarding/onboarding_flow.dart';
import '../features/renter/renter_app.dart';
import '../modules/user/controllers/auth_controller.dart';
import '../modules/user/views/login_screen.dart';
import '../shared/models/domain_models.dart';

class RentHubApp extends StatefulWidget {
  const RentHubApp({super.key, this.showIntroduction = true});

  // Nullable so a hot reload from a build that predates this field can safely
  // migrate the existing widget instance. New instances still default to true.
  final bool? showIntroduction;

  @override
  State<RentHubApp> createState() => _RentHubAppState();
}

enum _EntryStage { splash, onboarding, application }

class _RentHubAppState extends State<RentHubApp> {
  late _EntryStage stage = (widget.showIntroduction ?? true)
      ? _EntryStage.splash
      : _EntryStage.application;

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'RentHub',
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
              onFinished: () => setState(() => stage = _EntryStage.application),
            ),
          _EntryStage.application => Consumer<AuthController>(
              builder: (_, auth, __) {
                if (!auth.authenticated) return const LoginScreen();
                final canSwitch = auth.user!.roles.contains(UserRole.renter) &&
                    auth.user!.roles.contains(UserRole.owner);
                void switchRole() => auth.selectRole(
                      auth.selectedRole == UserRole.renter
                          ? UserRole.owner
                          : UserRole.renter,
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

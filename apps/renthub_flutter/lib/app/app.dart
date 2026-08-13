import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/theme/app_theme.dart';
import '../features/owner/owner_app.dart';
import '../features/renter/renter_app.dart';
import '../modules/user/controllers/auth_controller.dart';
import '../modules/user/views/login_screen.dart';
import '../shared/models/domain_models.dart';

class RentHubApp extends StatelessWidget {
  const RentHubApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'RentHub',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        home: Consumer<AuthController>(
          builder: (_, auth, __) {
            if (!auth.authenticated) return const LoginScreen();
            final canSwitch = auth.user!.roles.contains(UserRole.renter) &&
                auth.user!.roles.contains(UserRole.owner);
            void switchRole() => auth.selectRole(
                  auth.selectedRole == UserRole.renter
                      ? UserRole.owner
                      : UserRole.renter,
                );
            return auth.selectedRole == UserRole.owner
                ? OwnerShell(canSwitch: canSwitch, onSwitchRole: switchRole)
                : RenterShell(canSwitch: canSwitch, onSwitchRole: switchRole);
          },
        ),
      );
}

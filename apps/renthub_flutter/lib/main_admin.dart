import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app/dependencies.dart';
import 'core/config/backend_mode.dart';
import 'features/admin/admin_app.dart';
import 'features/live/live_admin_app.dart';
import 'features/live/live_renthub_controller.dart';
import 'modules/user/controllers/auth_controller.dart';
import 'shared/models/domain_models.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (BackendMode.useMocks) {
    runApp(const AdminApp());
    return;
  }
  final dependencies = AppDependencies.create();
  final authController = AuthController(dependencies.authRepository)
    ..selectRole(UserRole.admin);
  await authController.restoreSession(allowedRoles: const {UserRole.admin});
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: authController),
        ChangeNotifierProvider(
          create: (_) => LiveRentHubController(dependencies.api),
        ),
      ],
      child: const LiveAdminApp(),
    ),
  );
}

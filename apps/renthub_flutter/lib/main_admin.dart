import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app/dependencies.dart';
import 'core/config/backend_mode.dart';
import 'features/admin/admin_app.dart';
import 'features/live/live_admin_app.dart';
import 'features/live/live_renthub_controller.dart';
import 'modules/user/controllers/auth_controller.dart';
import 'shared/models/domain_models.dart';

void main() {
  if (BackendMode.useMocks) {
    runApp(const AdminApp());
    return;
  }
  final dependencies = AppDependencies.create();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => AuthController(dependencies.authRepository)
            ..selectRole(UserRole.admin),
        ),
        ChangeNotifierProvider(
          create: (_) => LiveRentHubController(dependencies.api),
        ),
      ],
      child: const LiveAdminApp(),
    ),
  );
}

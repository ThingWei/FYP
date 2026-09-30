import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'app/app.dart';
import 'app/dependencies.dart';
import 'core/config/backend_mode.dart';
import 'modules/user/controllers/auth_controller.dart';
import 'modules/listing/controllers/listing_controller.dart';
import 'modules/booking/controllers/booking_controller.dart';
import 'modules/loyalty/controllers/loyalty_controller.dart';
import 'features/live/live_renthub_controller.dart';
import 'core/notifications/push_notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final dependencies = AppDependencies.create();
  await dependencies.pushNotifications.initialize();
  runApp(
    MultiProvider(
      providers: [
        Provider.value(value: dependencies),
        Provider<PushNotificationService>.value(
          value: dependencies.pushNotifications,
        ),
        ChangeNotifierProvider(
          create: (_) => AuthController(
            dependencies.authRepository,
            pushNotifications: dependencies.pushNotifications,
          ),
        ),
        ChangeNotifierProvider(
          create: (_) =>
              ListingController(dependencies.listingRepository)..load(),
        ),
        ChangeNotifierProvider(
          create: (_) => BookingController(dependencies.bookingRepository),
        ),
        ChangeNotifierProvider(
          create: (_) {
            final controller =
                LoyaltyController(dependencies.loyaltyRepository);
            if (BackendMode.useMocks) controller.load();
            return controller;
          },
        ),
        ChangeNotifierProvider(
          create: (_) => LiveRentHubController(
            dependencies.api,
            pushNotifications: dependencies.pushNotifications,
            socketUrl: const String.fromEnvironment(
              'SOCKET_URL',
              defaultValue: 'http://localhost:3000',
            ),
          ),
        ),
      ],
      child: const RentHubApp(),
    ),
  );
}

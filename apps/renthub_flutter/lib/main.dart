import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'app/app.dart';
import 'app/dependencies.dart';
import 'modules/user/controllers/auth_controller.dart';
import 'modules/listing/controllers/listing_controller.dart';
import 'modules/booking/controllers/booking_controller.dart';

void main() {
  final dependencies = AppDependencies.create();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => AuthController(dependencies.authRepository),
        ),
        ChangeNotifierProvider(
          create: (_) =>
              ListingController(dependencies.listingRepository)..load(),
        ),
        ChangeNotifierProvider(
          create: (_) => BookingController(dependencies.bookingRepository),
        ),
      ],
      child: const RentHubApp(),
    ),
  );
}

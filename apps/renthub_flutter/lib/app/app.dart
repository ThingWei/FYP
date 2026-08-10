import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/theme/app_theme.dart';
import '../modules/user/controllers/auth_controller.dart';
import '../modules/user/views/login_screen.dart';
import 'navigation_shells.dart';
class RentHubApp extends StatelessWidget { const RentHubApp({super.key}); @override Widget build(BuildContext context)=>MaterialApp(title:'RentHub',debugShowCheckedModeBanner:false,theme:AppTheme.light,home:Consumer<AuthController>(builder:(_,auth,__)=>auth.authenticated?RoleHome(user:auth.user!):const LoginScreen())); }


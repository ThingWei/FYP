import 'package:flutter/material.dart';
abstract final class AppTheme {
  static const primary = Color(0xFF1A4ED8), success = Color(0xFF10B981), danger = Color(0xFFEF4444), surface = Color(0xFFF8FAFC), border = Color(0xFFE2E8F0), text = Color(0xFF0F172A);
  static ThemeData get light => ThemeData(useMaterial3: true, colorScheme: ColorScheme.fromSeed(seedColor: primary, surface: surface), scaffoldBackgroundColor: surface, cardTheme: const CardThemeData(elevation: 0, shape: RoundedRectangleBorder(side: BorderSide(color: border), borderRadius: BorderRadius.all(Radius.circular(12)))), inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()), filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)))));
}


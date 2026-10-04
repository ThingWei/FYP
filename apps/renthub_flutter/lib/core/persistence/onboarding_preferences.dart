import 'package:shared_preferences/shared_preferences.dart';

abstract final class OnboardingPreferences {
  static const completedKey = 'renthub_onboarding_completed';

  static Future<bool> isCompleted() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool(completedKey) ?? false;
  }

  static Future<void> markCompleted() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(completedKey, true);
  }

  static Future<bool> resolveCompleted({
    required bool hasRestoredSession,
  }) async {
    final completed = await isCompleted();
    if (!completed && hasRestoredSession) await markCompleted();
    return completed || hasRestoredSession;
  }
}

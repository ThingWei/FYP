import 'dart:async';
import 'dart:math';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../network/api_client.dart';

@pragma('vm:entry-point')
Future<void> rentHubFirebaseBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(
    options: RentHubFirebaseConfiguration.options,
  );
}

abstract final class RentHubFirebaseConfiguration {
  static const enabled = bool.fromEnvironment(
    'FIREBASE_ENABLED',
    defaultValue: false,
  );
  static const apiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const appId = String.fromEnvironment('FIREBASE_APP_ID');
  static const messagingSenderId = String.fromEnvironment(
    'FIREBASE_MESSAGING_SENDER_ID',
  );
  static const projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
  static const authDomain = String.fromEnvironment('FIREBASE_AUTH_DOMAIN');
  static const storageBucket = String.fromEnvironment(
    'FIREBASE_STORAGE_BUCKET',
  );
  static const vapidKey = String.fromEnvironment('FIREBASE_VAPID_KEY');

  static FirebaseOptions? get options {
    if (apiKey.isEmpty ||
        appId.isEmpty ||
        messagingSenderId.isEmpty ||
        projectId.isEmpty) {
      return null;
    }
    return FirebaseOptions(
      apiKey: apiKey,
      appId: appId,
      messagingSenderId: messagingSenderId,
      projectId: projectId,
      authDomain: authDomain.isEmpty ? null : authDomain,
      storageBucket: storageBucket.isEmpty ? null : storageBucket,
    );
  }
}

class PushNotificationEvent {
  const PushNotificationEvent({
    required this.title,
    required this.body,
    required this.data,
    required this.openedFromNotification,
  });

  final String title;
  final String body;
  final Map<String, dynamic> data;
  final bool openedFromNotification;
}

class PushNotificationService {
  PushNotificationService(this.api);

  static const _deviceIdKey = 'renthub_push_device_id';
  final ApiClient api;
  final _events = StreamController<PushNotificationEvent>.broadcast();
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  bool _initialized = false;
  bool _userEnabled = false;
  String? _deviceId;
  PushNotificationEvent? _initialEvent;

  Stream<PushNotificationEvent> get events => _events.stream;
  bool get available => _initialized;

  String? get _platform {
    if (kIsWeb) return 'web';
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => 'android',
      TargetPlatform.iOS => 'ios',
      TargetPlatform.macOS => 'macos',
      _ => null,
    };
  }

  Future<void> initialize() async {
    if (!RentHubFirebaseConfiguration.enabled || _platform == null) return;
    final options = RentHubFirebaseConfiguration.options;
    if (kIsWeb && options == null) return;
    try {
      await Firebase.initializeApp(options: options);
      FirebaseMessaging.onBackgroundMessage(
        rentHubFirebaseBackgroundHandler,
      );
      _subscriptions.add(
        FirebaseMessaging.onMessage.listen(
          (message) => _emit(message, opened: false),
        ),
      );
      _subscriptions.add(
        FirebaseMessaging.onMessageOpenedApp.listen(
          (message) => _emit(message, opened: true),
        ),
      );
      _subscriptions.add(
        FirebaseMessaging.instance.onTokenRefresh.listen(_refreshToken),
      );
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) _initialEvent = _event(initial, opened: true);
      _initialized = true;
    } catch (error) {
      debugPrint('Firebase Messaging initialization skipped: $error');
    }
  }

  PushNotificationEvent? takeInitialEvent() {
    final event = _initialEvent;
    _initialEvent = null;
    return event;
  }

  Future<bool> enableForCurrentUser() async {
    if (!_initialized) return false;
    try {
      final permission = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );
      if (permission.authorizationStatus != AuthorizationStatus.authorized &&
          permission.authorizationStatus != AuthorizationStatus.provisional) {
        return false;
      }
      final token = await FirebaseMessaging.instance.getToken(
        vapidKey: kIsWeb && RentHubFirebaseConfiguration.vapidKey.isNotEmpty
            ? RentHubFirebaseConfiguration.vapidKey
            : null,
      );
      if (token == null || token.isEmpty) return false;
      _userEnabled = true;
      await _register(token);
      return true;
    } catch (error) {
      debugPrint('Push notification registration failed: $error');
      return false;
    }
  }

  Future<void> disableForCurrentUser() async {
    _userEnabled = false;
    try {
      final deviceId = await _loadDeviceId();
      await api.request('DELETE', '/messages/push/devices/$deviceId');
    } catch (error) {
      debugPrint('Push device removal failed: $error');
    }
  }

  void forgetCurrentUser() => _userEnabled = false;

  Future<void> _refreshToken(String token) async {
    if (!_userEnabled) return;
    try {
      await _register(token);
    } catch (error) {
      debugPrint('Push token refresh failed: $error');
    }
  }

  Future<void> _register(String token) async {
    final platform = _platform;
    if (platform == null) return;
    final deviceId = await _loadDeviceId();
    await api.request(
      'POST',
      '/messages/push/devices',
      body: {
        'deviceId': deviceId,
        'deviceName': 'RentHub ${platform.toUpperCase()}',
        'platform': platform,
        'token': token,
      },
    );
  }

  Future<String> _loadDeviceId() async {
    if (_deviceId != null) return _deviceId!;
    final preferences = await SharedPreferences.getInstance();
    final existing = preferences.getString(_deviceIdKey);
    if (existing != null && existing.isNotEmpty) {
      _deviceId = existing;
      return existing;
    }
    final random = Random.secure();
    final suffix = List.generate(
      12,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    final created = 'device-$suffix';
    await preferences.setString(_deviceIdKey, created);
    _deviceId = created;
    return created;
  }

  PushNotificationEvent _event(
    RemoteMessage message, {
    required bool opened,
  }) =>
      PushNotificationEvent(
        title: message.notification?.title ?? 'RentHub update',
        body: message.notification?.body ?? 'You have a new notification.',
        data: Map<String, dynamic>.from(message.data),
        openedFromNotification: opened,
      );

  void _emit(RemoteMessage message, {required bool opened}) {
    _events.add(_event(message, opened: opened));
  }

  Future<void> dispose() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await _events.close();
  }
}

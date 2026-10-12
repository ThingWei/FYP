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

abstract class PushMessagingClient {
  Future<void> initialize();
  Stream<RemoteMessage> get foregroundMessages;
  Stream<RemoteMessage> get openedMessages;
  Stream<String> get tokenRefresh;
  Future<RemoteMessage?> initialMessage();
  Future<bool> requestPermission();
  Future<String?> token();
}

class FirebasePushMessagingClient implements PushMessagingClient {
  @override
  Future<void> initialize() async {
    await Firebase.initializeApp(options: RentHubFirebaseConfiguration.options);
    FirebaseMessaging.onBackgroundMessage(rentHubFirebaseBackgroundHandler);
  }

  @override
  Stream<RemoteMessage> get foregroundMessages => FirebaseMessaging.onMessage;
  @override
  Stream<RemoteMessage> get openedMessages =>
      FirebaseMessaging.onMessageOpenedApp;
  @override
  Stream<String> get tokenRefresh => FirebaseMessaging.instance.onTokenRefresh;
  @override
  Future<RemoteMessage?> initialMessage() =>
      FirebaseMessaging.instance.getInitialMessage();
  @override
  Future<bool> requestPermission() async {
    final permission = await FirebaseMessaging.instance.requestPermission(
        alert: true, badge: true, sound: true, provisional: false);
    return permission.authorizationStatus == AuthorizationStatus.authorized ||
        permission.authorizationStatus == AuthorizationStatus.provisional;
  }

  @override
  Future<String?> token() => FirebaseMessaging.instance.getToken(
      vapidKey: kIsWeb && RentHubFirebaseConfiguration.vapidKey.isNotEmpty
          ? RentHubFirebaseConfiguration.vapidKey
          : null);
}

enum PushRegistrationState {
  disabled,
  unsupported,
  unavailable,
  ready,
  denied,
  registered,
  failed
}

class PushNotificationService {
  PushNotificationService(this.api,
      {PushMessagingClient? messaging,
      this.enabledOverride,
      this.platformOverride})
      : messaging = messaging ?? FirebasePushMessagingClient();
  final PushMessagingClient messaging;
  final bool? enabledOverride;
  final String? platformOverride;
  PushRegistrationState state = PushRegistrationState.disabled;
  String get statusMessage => switch (state) {
        PushRegistrationState.disabled =>
          'Phone push is not configured yet. Updates remain available in the notification centre.',
        PushRegistrationState.unsupported =>
          'Phone push is not available on Windows. Use the Android app; in-app updates still work here.',
        PushRegistrationState.unavailable =>
          'Phone push could not start. Check Firebase configuration and try again.',
        PushRegistrationState.ready =>
          'Phone push is ready to register. Save settings to enable it on this device.',
        PushRegistrationState.denied =>
          'Notifications are blocked by this device. Allow RentHub notifications in Android settings, then try again.',
        PushRegistrationState.registered =>
          'This device is registered for push notifications. Delivery also requires the API to be running.',
        PushRegistrationState.failed =>
          'Phone push could not be updated on this device. Check your connection and try again.',
      };

  static const _deviceIdKey = 'renthub_push_device_id';
  final ApiClient api;
  final _events = StreamController<PushNotificationEvent>.broadcast();
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  bool _initialized = false;
  bool _userEnabled = false;
  int _registrationGeneration = 0;
  String? _deviceId;
  PushNotificationEvent? _initialEvent;

  Stream<PushNotificationEvent> get events => _events.stream;
  bool get available => _initialized;

  Future<String> currentDeviceId() => _loadDeviceId();

  String? get _platform {
    if (platformOverride != null) return platformOverride;
    if (kIsWeb) return 'web';
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => 'android',
      TargetPlatform.iOS => 'ios',
      TargetPlatform.macOS => 'macos',
      _ => null,
    };
  }

  Future<void> initialize() async {
    if (_initialized) return;
    if (_platform == null) {
      state = PushRegistrationState.unsupported;
      return;
    }
    if (!(enabledOverride ?? RentHubFirebaseConfiguration.enabled)) {
      state = PushRegistrationState.disabled;
      return;
    }
    final options = RentHubFirebaseConfiguration.options;
    if (kIsWeb && options == null && enabledOverride == null) {
      state = PushRegistrationState.unavailable;
      return;
    }
    try {
      await messaging.initialize();
      _subscriptions.add(
        messaging.foregroundMessages.listen(
          (message) => _emit(message, opened: false),
        ),
      );
      _subscriptions.add(
        messaging.openedMessages.listen(
          (message) => _emit(message, opened: true),
        ),
      );
      _subscriptions.add(
        messaging.tokenRefresh.listen(_refreshToken),
      );
      final initial = await messaging.initialMessage();
      if (initial != null) _initialEvent = _event(initial, opened: true);
      _initialized = true;
      state = PushRegistrationState.ready;
    } catch (error) {
      for (final subscription in _subscriptions) {
        await subscription.cancel();
      }
      _subscriptions.clear();
      state = PushRegistrationState.unavailable;
      debugPrint('Firebase Messaging initialization skipped: $error');
    }
  }

  PushNotificationEvent? takeInitialEvent() {
    final event = _initialEvent;
    _initialEvent = null;
    return event;
  }

  Future<bool> enableForCurrentUser() async {
    final generation = ++_registrationGeneration;
    if (!_initialized) await initialize();
    if (!_initialized || generation != _registrationGeneration) return false;
    _userEnabled = false;
    try {
      if (!await messaging.requestPermission()) {
        if (generation != _registrationGeneration) return false;
        state = PushRegistrationState.denied;
        return false;
      }
      final token = await messaging.token();
      if (generation != _registrationGeneration) return false;
      if (token == null || token.isEmpty) {
        state = PushRegistrationState.failed;
        return false;
      }
      final server = await api.request('GET', '/messages/push/status');
      if (generation != _registrationGeneration) return false;
      if (server is! Map || server['enabled'] != true) {
        state = PushRegistrationState.disabled;
        return false;
      }
      await _register(token, generation: generation);
      if (generation != _registrationGeneration) return false;
      _userEnabled = true;
      state = PushRegistrationState.registered;
      return true;
    } catch (error) {
      if (generation != _registrationGeneration) return false;
      state = PushRegistrationState.failed;
      debugPrint('Push notification registration failed: $error');
      return false;
    }
  }

  Future<bool> disableForCurrentUser() async {
    _registrationGeneration++;
    _userEnabled = false;
    try {
      final deviceId = await _loadDeviceId();
      await api.request('DELETE', '/messages/push/devices/$deviceId');
      state = _initialized ? PushRegistrationState.ready : state;
      return true;
    } catch (error) {
      debugPrint('Push device removal failed: $error');
      state = PushRegistrationState.failed;
      // Push cleanup must not prevent local logout and credential removal.
      return false;
    }
  }

  void forgetCurrentUser() {
    _registrationGeneration++;
    _userEnabled = false;
    if (_initialized) state = PushRegistrationState.ready;
  }

  Future<void> _refreshToken(String token) async {
    if (!_userEnabled) return;
    final generation = _registrationGeneration;
    try {
      await _register(token, generation: generation);
      if (generation != _registrationGeneration) return;
      state = PushRegistrationState.registered;
    } catch (error) {
      if (generation != _registrationGeneration) return;
      state = PushRegistrationState.failed;
      debugPrint('Push token refresh failed: $error');
    }
  }

  Future<void> _register(String token, {required int generation}) async {
    final platform = _platform;
    if (platform == null) return;
    final deviceId = await _loadDeviceId();
    if (generation != _registrationGeneration) return;
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
    forgetCurrentUser();
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await _events.close();
  }
}

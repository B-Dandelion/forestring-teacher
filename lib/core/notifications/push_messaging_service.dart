import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../../firebase_options.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
}

class PushMessagingDiagnostics {
  const PushMessagingDiagnostics({
    required this.authorizationStatus,
    required this.fcmToken,
    required this.apnsToken,
  });

  final AuthorizationStatus authorizationStatus;
  final String? fcmToken;
  final String? apnsToken;
}

class PushMessagingService {
  PushMessagingService._();

  static final PushMessagingService instance = PushMessagingService._();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  StreamSubscription<RemoteMessage>? _foregroundSubscription;
  StreamSubscription<RemoteMessage>? _openedSubscription;
  StreamSubscription<String>? _tokenRefreshSubscription;

  bool _initialized = false;

  void registerBackgroundHandler() {
    FirebaseMessaging.onBackgroundMessage(
      firebaseMessagingBackgroundHandler,
    );
  }

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    _initialized = true;

    if (Platform.isIOS) {
      await _messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
    }

    _foregroundSubscription = FirebaseMessaging.onMessage.listen(
      _handleForegroundMessage,
    );

    _openedSubscription = FirebaseMessaging.onMessageOpenedApp.listen(
      _handleOpenedMessage,
    );

    _tokenRefreshSubscription = _messaging.onTokenRefresh.listen(
      _handleTokenRefresh,
    );

    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      _handleOpenedMessage(initialMessage);
    }
  }

  Future<PushMessagingDiagnostics> requestPermissionAndGetToken() async {
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      announcement: false,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
    );

    String? apnsToken;

    if (Platform.isIOS &&
        settings.authorizationStatus != AuthorizationStatus.denied) {
      apnsToken = await _waitForApnsToken();
    }

    String? fcmToken;

    if (!Platform.isIOS || apnsToken != null) {
      fcmToken = await _messaging.getToken();
    }

    final diagnostics = PushMessagingDiagnostics(
      authorizationStatus: settings.authorizationStatus,
      fcmToken: fcmToken,
      apnsToken: apnsToken,
    );

    if (kDebugMode) {
      debugPrint(
        '[FCM] authorization: ${settings.authorizationStatus.name}',
      );
      debugPrint(
        '[FCM] APNs token available: ${apnsToken != null}',
      );
      debugPrint(
        '[FCM] registration token available: ${fcmToken != null}',
      );
    }

    return diagnostics;
  }

  Future<String?> _waitForApnsToken() async {
    const retryInterval = Duration(milliseconds: 250);
    const maxAttempts = 32;

    for (var attempt = 0; attempt < maxAttempts; attempt += 1) {
      final token = await _messaging.getAPNSToken();
      if (token != null && token.isNotEmpty) {
        return token;
      }

      await Future<void>.delayed(retryInterval);
    }

    return null;
  }

  void _handleForegroundMessage(RemoteMessage message) {
    if (!kDebugMode) {
      return;
    }

    debugPrint(
      '[FCM] foreground message: '
      'id=${message.messageId}, data=${message.data}',
    );
  }

  void _handleOpenedMessage(RemoteMessage message) {
    if (!kDebugMode) {
      return;
    }

    debugPrint(
      '[FCM] opened message: '
      'id=${message.messageId}, data=${message.data}',
    );
  }

  void _handleTokenRefresh(String token) {
    if (!kDebugMode) {
      return;
    }

    debugPrint(
      '[FCM] registration token refreshed: tokenPresent=${token.isNotEmpty}',
    );
  }

  Future<void> dispose() async {
    await _foregroundSubscription?.cancel();
    await _openedSubscription?.cancel();
    await _tokenRefreshSubscription?.cancel();

    _foregroundSubscription = null;
    _openedSubscription = null;
    _tokenRefreshSubscription = null;
    _initialized = false;
  }
}

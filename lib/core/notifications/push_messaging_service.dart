import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../../firebase_options.dart';
import 'notification_navigation_coordinator.dart';

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
        alert: false,
        badge: true,
        sound: false,
      );
    }

    _foregroundSubscription = FirebaseMessaging.onMessage.listen(
      _handleForegroundMessage,
    );

    _openedSubscription = FirebaseMessaging.onMessageOpenedApp.listen(
      (message) {
        _handleOpenedMessage(
          message,
          fromTerminated: false,
        );
      },
    );

    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      _handleOpenedMessage(
        initialMessage,
        fromTerminated: true,
      );
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
    NotificationNavigationCoordinator.instance.receiveForeground(
      message,
    );

    if (kDebugMode) {
      debugPrint(
        '[FCM] foreground message: '
        'id=${message.messageId}, '
        'dataKeys=${message.data.keys.toList()}',
      );
    }
  }

  void _handleOpenedMessage(
    RemoteMessage message, {
    required bool fromTerminated,
  }) {
    NotificationNavigationCoordinator.instance.receiveOpened(
      message,
      fromTerminated: fromTerminated,
    );

    if (kDebugMode) {
      debugPrint(
        '[FCM] opened message: '
        'id=${message.messageId}, '
        'fromTerminated=$fromTerminated, '
        'dataKeys=${message.data.keys.toList()}',
      );
    }
  }

  Future<void> dispose() async {
    await _foregroundSubscription?.cancel();
    await _openedSubscription?.cancel();

    _foregroundSubscription = null;
    _openedSubscription = null;
    _initialized = false;
  }
}

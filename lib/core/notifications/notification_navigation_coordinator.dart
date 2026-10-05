import 'dart:collection';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'notification_payload.dart';

class ForegroundNotificationPresentation {
  const ForegroundNotificationPresentation({
    required this.intent,
    required this.title,
    required this.body,
  });

  final NotificationNavigationIntent intent;
  final String? title;
  final String? body;
}

class NotificationNavigationCoordinator extends ChangeNotifier {
  NotificationNavigationCoordinator._();

  static final NotificationNavigationCoordinator instance =
      NotificationNavigationCoordinator._();

  static const _handledHistoryLimit = 64;

  final ListQueue<NotificationNavigationIntent> _pending =
      ListQueue<NotificationNavigationIntent>();
  final ListQueue<String> _handledOrder = ListQueue<String>();
  final Set<String> _handledIds = <String>{};

  ForegroundNotificationPresentation? _foregroundPresentation;

  bool get hasPendingNavigation => _pending.isNotEmpty;

  ForegroundNotificationPresentation? get foregroundPresentation =>
      _foregroundPresentation;

  void receiveForeground(RemoteMessage message) {
    final intent = NotificationNavigationIntent.tryParse(
      message.data,
    );
    if (intent == null || _handledIds.contains(intent.notificationId)) {
      _debugIgnored(message, 'foreground');
      return;
    }

    _foregroundPresentation = ForegroundNotificationPresentation(
      intent: intent,
      title: message.notification?.title,
      body: message.notification?.body,
    );
    notifyListeners();
  }

  void receiveOpened(
    RemoteMessage message, {
    required bool fromTerminated,
  }) {
    final intent = NotificationNavigationIntent.tryParse(
      message.data,
    );
    if (intent == null) {
      _debugIgnored(
        message,
        fromTerminated ? 'terminated-open' : 'background-open',
      );
      return;
    }

    if (_foregroundPresentation?.intent.notificationId ==
        intent.notificationId) {
      _foregroundPresentation = null;
    }

    _enqueue(intent);
  }

  void openForegroundNotification(String notificationId) {
    final presentation = _foregroundPresentation;
    if (presentation == null ||
        presentation.intent.notificationId != notificationId) {
      return;
    }

    _foregroundPresentation = null;
    _enqueue(presentation.intent);
  }

  void dismissForeground(String notificationId) {
    final presentation = _foregroundPresentation;
    if (presentation == null ||
        presentation.intent.notificationId != notificationId) {
      return;
    }

    _foregroundPresentation = null;
    notifyListeners();
  }

  NotificationNavigationIntent? takePendingForProfile(
    String profileId,
  ) {
    var changed = false;

    while (_pending.isNotEmpty) {
      final intent = _pending.removeFirst();
      changed = true;
      _markHandled(intent.notificationId);

      if (intent.recipientProfileId == profileId) {
        if (changed) {
          notifyListeners();
        }
        return intent;
      }

      if (kDebugMode) {
        debugPrint(
          '[NotificationNavigation] discarded notification for '
          'a different profile.',
        );
      }
    }

    if (changed) {
      notifyListeners();
    }
    return null;
  }

  void _enqueue(NotificationNavigationIntent intent) {
    if (_handledIds.contains(intent.notificationId) ||
        _pending.any(
          (pending) =>
              pending.notificationId == intent.notificationId,
        )) {
      return;
    }

    _pending.addLast(intent);
    notifyListeners();
  }

  void _markHandled(String notificationId) {
    if (!_handledIds.add(notificationId)) {
      return;
    }

    _handledOrder.addLast(notificationId);

    while (_handledOrder.length > _handledHistoryLimit) {
      final oldest = _handledOrder.removeFirst();
      _handledIds.remove(oldest);
    }
  }

  void _debugIgnored(RemoteMessage message, String source) {
    if (!kDebugMode) {
      return;
    }

    debugPrint(
      '[NotificationNavigation] ignored unsupported payload: '
      'source=$source, messageId=${message.messageId}, '
      'dataKeys=${message.data.keys.toList()}',
    );
  }
}

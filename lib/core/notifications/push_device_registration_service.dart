import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'push_device_repository.dart';
import 'push_messaging_service.dart';

class PushDeviceRegistrationService {
  PushDeviceRegistrationService._();

  static final PushDeviceRegistrationService instance =
      PushDeviceRegistrationService._();

  static const _installationKey =
      'forestring_teacher_push_installation_id_v1';

  PushDeviceRepository? _repository;
  StreamSubscription<String>? _tokenRefreshSubscription;
  bool _initialized = false;

  void initialize({
    PushDeviceRepository? repository,
  }) {
    if (_initialized) {
      return;
    }

    _initialized = true;
    _repository = repository ?? PushDeviceRepository();

    _tokenRefreshSubscription =
        FirebaseMessaging.instance.onTokenRefresh.listen(
      (token) {
        unawaited(
          _registerTokenIfSignedIn(token),
        );
      },
      onError: (Object error, StackTrace stackTrace) {
        if (kDebugMode) {
          debugPrint(
            '[PushRegistration] token refresh stream error: '
            '${error.runtimeType}',
          );
        }
      },
    );
  }

  Future<void> bindCurrentSession() async {
    final client = Supabase.instance.client;

    if (client.auth.currentSession == null ||
        client.auth.currentUser == null) {
      return;
    }

    final diagnostics =
        await PushMessagingService.instance.requestPermissionAndGetToken();

    if (diagnostics.authorizationStatus == AuthorizationStatus.denied) {
      await unbindCurrentSession();
      return;
    }

    final token = diagnostics.fcmToken;
    if (token == null || token.isEmpty) {
      if (kDebugMode) {
        debugPrint(
          '[PushRegistration] FCM token is not available yet.',
        );
      }
      return;
    }

    await _registerTokenIfSignedIn(token);
  }

  Future<void> unbindCurrentSession() async {
    final repository = _repository;
    if (repository == null) {
      return;
    }

    final client = Supabase.instance.client;
    if (client.auth.currentSession == null ||
        client.auth.currentUser == null) {
      return;
    }

    final installationId = await _readInstallationId();
    if (installationId == null) {
      return;
    }

    try {
      await repository.unregisterDevice(
        installationId: installationId,
      );

      if (kDebugMode) {
        debugPrint(
          '[PushRegistration] installation disabled before logout.',
        );
      }
    } catch (error) {
      if (kDebugMode) {
        debugPrint(
          '[PushRegistration] unregister failed: '
          '${error.runtimeType}',
        );
      }
    }
  }

  Future<void> _registerTokenIfSignedIn(String token) async {
    final repository = _repository;
    if (repository == null) {
      return;
    }

    final client = Supabase.instance.client;
    if (client.auth.currentSession == null ||
        client.auth.currentUser == null) {
      return;
    }

    final installationId = await _getOrCreateInstallationId();

    try {
      await repository.registerDevice(
        installationId: installationId,
        fcmToken: token,
        platform: _platform,
      );

      if (kDebugMode) {
        debugPrint(
          '[PushRegistration] device registered: '
          'platform=$_platform, tokenPresent=true',
        );
      }
    } catch (error) {
      if (kDebugMode) {
        debugPrint(
          '[PushRegistration] registration failed: '
          '${error.runtimeType}',
        );
      }
    }
  }

  String get _platform {
    if (Platform.isIOS) {
      return 'ios';
    }
    if (Platform.isAndroid) {
      return 'android';
    }

    throw UnsupportedError(
      'Push registration is supported only on Android and iOS.',
    );
  }

  Future<String?> _readInstallationId() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getString(_installationKey);
  }

  Future<String> _getOrCreateInstallationId() async {
    final preferences = await SharedPreferences.getInstance();
    final existing = preferences.getString(_installationKey);

    if (existing != null && existing.length >= 16) {
      return existing;
    }

    final random = Random.secure();
    final bytes = List<int>.generate(
      16,
      (_) => random.nextInt(256),
    );
    final installationId = bytes
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();

    await preferences.setString(
      _installationKey,
      installationId,
    );

    return installationId;
  }

  Future<void> dispose() async {
    await _tokenRefreshSubscription?.cancel();
    _tokenRefreshSubscription = null;
    _initialized = false;
  }
}

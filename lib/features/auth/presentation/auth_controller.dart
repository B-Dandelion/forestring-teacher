import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/notifications/push_device_registration_service.dart';
import '../data/auth_repository.dart';
import '../domain/current_profile.dart';

class AuthController extends ChangeNotifier {
  AuthController(
    this._repository, {
    PushDeviceRegistrationService? pushRegistration,
  }) : _pushRegistration =
            pushRegistration ?? PushDeviceRegistrationService.instance;

  static const _sessionCheckTimeout = Duration(seconds: 8);
  static const _signOutTimeout = Duration(seconds: 3);

  final AuthRepository _repository;
  final PushDeviceRegistrationService _pushRegistration;

  bool _isInitializing = true;
  bool _isLoading = false;

  String? _errorMessage;

  CurrentProfile? _profile;

  bool get isInitializing => _isInitializing;

  bool get isLoading => _isLoading;

  String? get errorMessage => _errorMessage;

  CurrentProfile? get profile => _profile;

  Session? get session => _repository.currentSession;

  User? get user => _repository.currentUser;

  bool get isSignedIn => session != null && _profile != null;

  Future<void> initialize({
    bool restoreSession = true,
  }) async {
    _isInitializing = true;
    _errorMessage = null;

    if (!restoreSession) {
      _profile = null;
      _isInitializing = false;
      notifyListeners();
      return;
    }

    try {
      if (_repository.currentSession == null) {
        _profile = null;
        return;
      }

      _profile = await _repository
          .fetchCurrentProfile()
          .timeout(_sessionCheckTimeout);

      unawaited(
        _pushRegistration.bindCurrentSession(),
      );
    } on TimeoutException {
      _profile = null;
      await _bestEffortUnbindPush();
      await _bestEffortSignOut();
      _errorMessage = '이전 로그인 정보를 확인하는 데 시간이 오래 걸려 로그아웃했습니다. 다시 로그인해주세요.';
    } on AuthFailure catch (error) {
      _profile = null;

      await _bestEffortUnbindPush();
      await _bestEffortSignOut();

      _errorMessage = error.message;
    } catch (_) {
      _profile = null;

      await _bestEffortUnbindPush();
      await _bestEffortSignOut();

      _errorMessage = '로그인 정보를 확인하지 못했습니다. 다시 로그인해주세요.';
    } finally {
      _isInitializing = false;
      notifyListeners();
    }
  }

  Future<bool> signIn({
    required String name,
    required String pin,
  }) async {
    if (_isLoading) {
      return false;
    }

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _repository.signInWithNameAndPin(
        name: name,
        pin: pin,
      );

      _profile = await _repository
          .fetchCurrentProfile()
          .timeout(_sessionCheckTimeout);

      unawaited(
        _pushRegistration.bindCurrentSession(),
      );

      return true;
    } on TimeoutException {
      _profile = null;
      await _bestEffortSignOut();
      _errorMessage = '로그인 확인이 지연되고 있습니다. 잠시 후 다시 시도해주세요.';
      return false;
    } on AuthFailure catch (error) {
      _profile = null;

      if (_repository.currentSession != null) {
        await _bestEffortSignOut();
      }

      _errorMessage = error.message;

      return false;
    } catch (_) {
      _profile = null;

      if (_repository.currentSession != null) {
        await _bestEffortSignOut();
      }

      _errorMessage = '로그인 중 알 수 없는 오류가 발생했습니다.';

      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> signOut() async {
    await _bestEffortUnbindPush();
    await _bestEffortSignOut();

    _profile = null;
    _errorMessage = null;

    notifyListeners();
  }

  Future<void> _bestEffortUnbindPush() async {
    try {
      await _pushRegistration
          .unbindCurrentSession()
          .timeout(_signOutTimeout);
    } catch (_) {
      // Logout must still continue if Push token cleanup cannot reach the
      // server. A later login will rebind the installation safely.
    }
  }

  Future<void> _bestEffortSignOut() async {
    try {
      await _repository.signOut().timeout(_signOutTimeout);
    } catch (_) {
      // Even if the server/network is unavailable, the app must leave the
      // initialization state instead of remaining on the splash screen.
    }
  }

  void clearError() {
    if (_errorMessage == null) {
      return;
    }

    _errorMessage = null;
    notifyListeners();
  }
}

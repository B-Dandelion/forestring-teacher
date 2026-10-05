import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/current_profile.dart';

class AuthFailure implements Exception {
  const AuthFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

class AuthRepository {
  AuthRepository({
    SupabaseClient? client,
  }) : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Session? get currentSession => _client.auth.currentSession;

  User? get currentUser => _client.auth.currentUser;

  Future<Session> signInWithNameAndPin({
    required String name,
    required String pin,
  }) async {
    final normalizedName = name.trim();

    if (normalizedName.isEmpty) {
      throw const AuthFailure(
        '이름을 입력해주세요.',
      );
    }

    if (!RegExp(r'^\d{4}$').hasMatch(pin)) {
      throw const AuthFailure(
        'PIN은 4자리 숫자로 입력해주세요.',
      );
    }

    dynamic response;

    try {
      response = await _client.functions.invoke(
        'login-with-pin',
        body: {
          'name': normalizedName,
          'pin': pin,
        },
      );
    } on FunctionException catch (error) {
      final details = error.details;
      if (details is Map && details['message'] != null) {
        throw AuthFailure(details['message'].toString());
      }

      throw const AuthFailure(
        '로그인 서버에 연결하지 못했습니다. 네트워크 상태를 확인해주세요.',
      );
    } catch (_) {
      throw const AuthFailure(
        '로그인 서버에 연결하지 못했습니다. 네트워크 상태를 확인해주세요.',
      );
    }

    final data = response.data;

    if (data is! Map) {
      throw const AuthFailure(
        '로그인 서버 응답을 확인하지 못했습니다. 잠시 후 다시 시도해주세요.',
      );
    }

    final tokenHash = data['tokenHash'];

    if (tokenHash is! String || tokenHash.isEmpty) {
      final message = data['message'];

      throw AuthFailure(
        message is String ? message : '이름 또는 PIN이 올바르지 않습니다.',
      );
    }

    AuthResponse authResponse;

    try {
      authResponse = await _client.auth.verifyOTP(
        type: OtpType.email,
        tokenHash: tokenHash,
      );
    } on AuthException {
      throw const AuthFailure(
        '로그인 인증 정보를 확인하지 못했습니다. 잠시 후 다시 시도해주세요.',
      );
    }

    final session = authResponse.session;

    if (session == null) {
      throw const AuthFailure(
        '로그인 세션을 생성하지 못했습니다. 다시 로그인해주세요.',
      );
    }

    return session;
  }

  Future<CurrentProfile> fetchCurrentProfile() async {
    final user = currentUser;

    if (user == null) {
      throw const AuthFailure(
        '로그인이 필요합니다.',
      );
    }

    try {
      final data = await _client
          .from('profiles')
          .select(
            'id, '
            'display_name, '
            'role, '
            'branch_id, '
            'is_active, '
            'is_review_account, '
            'is_qa_account',
          )
          .eq(
            'id',
            user.id,
          )
          .single();

      final profile = CurrentProfile.fromJson(
        data,
      );

      if (!profile.isActive) {
        throw const AuthFailure(
          '비활성화된 계정입니다.',
        );
      }

      return profile;
    } on AuthFailure {
      rethrow;
    } on PostgrestException {
      throw const AuthFailure(
        '사용자 정보를 불러오지 못했습니다. 잠시 후 다시 시도해주세요.',
      );
    } catch (_) {
      throw const AuthFailure(
        '사용자 정보를 확인하는 중 오류가 발생했습니다. 잠시 후 다시 시도해주세요.',
      );
    }
  }

  Future<void> signOut() {
    return _client.auth.signOut();
  }
}

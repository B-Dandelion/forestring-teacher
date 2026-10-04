import 'package:supabase_flutter/supabase_flutter.dart';

class NotificationPreferences {
  const NotificationPreferences({
    required this.pushEnabled,
    required this.lessonAssignmentEnabled,
    required this.lessonScheduleChangeEnabled,
    required this.lessonCancellationEnabled,
    required this.makeupEnabled,
    required this.flexBookingEnabled,
  });

  final bool pushEnabled;
  final bool lessonAssignmentEnabled;
  final bool lessonScheduleChangeEnabled;
  final bool lessonCancellationEnabled;
  final bool makeupEnabled;
  final bool flexBookingEnabled;

  factory NotificationPreferences.fromJson(Map<String, dynamic> json) {
    return NotificationPreferences(
      pushEnabled: json['pushEnabled'] as bool? ?? true,
      lessonAssignmentEnabled:
          json['lessonAssignmentEnabled'] as bool? ?? true,
      lessonScheduleChangeEnabled:
          json['lessonScheduleChangeEnabled'] as bool? ?? true,
      lessonCancellationEnabled:
          json['lessonCancellationEnabled'] as bool? ?? true,
      makeupEnabled: json['makeupEnabled'] as bool? ?? true,
      flexBookingEnabled: json['flexBookingEnabled'] as bool? ?? true,
    );
  }
}

class PushDeviceRepository {
  PushDeviceRepository({
    SupabaseClient? client,
  }) : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<String> registerDevice({
    required String installationId,
    required String fcmToken,
    required String platform,
    String appId = 'forestring.teacher.app',
  }) async {
    final result = await _client.rpc(
      'register_push_device',
      params: {
        'p_installation_id': installationId,
        'p_fcm_token': fcmToken,
        'p_platform': platform,
        'p_app_id': appId,
      },
    );

    if (result is! String || result.isEmpty) {
      throw const FormatException(
        'Push device registration did not return an id.',
      );
    }

    return result;
  }

  Future<void> unregisterDevice({
    required String installationId,
    String appId = 'forestring.teacher.app',
  }) async {
    await _client.rpc(
      'unregister_push_device',
      params: {
        'p_installation_id': installationId,
        'p_app_id': appId,
      },
    );
  }

  Future<NotificationPreferences> getPreferences() async {
    final result = await _client.rpc(
      'get_notification_preferences',
    );

    if (result is! Map) {
      throw const FormatException(
        'Notification preferences response is invalid.',
      );
    }

    return NotificationPreferences.fromJson(
      Map<String, dynamic>.from(result),
    );
  }

  Future<NotificationPreferences> updatePreferences({
    bool? pushEnabled,
    bool? lessonAssignmentEnabled,
    bool? lessonScheduleChangeEnabled,
    bool? lessonCancellationEnabled,
    bool? makeupEnabled,
    bool? flexBookingEnabled,
  }) async {
    final result = await _client.rpc(
      'update_notification_preferences',
      params: {
        'p_push_enabled': pushEnabled,
        'p_lesson_assignment_enabled': lessonAssignmentEnabled,
        'p_lesson_schedule_change_enabled': lessonScheduleChangeEnabled,
        'p_lesson_cancellation_enabled': lessonCancellationEnabled,
        'p_makeup_enabled': makeupEnabled,
        'p_flex_booking_enabled': flexBookingEnabled,
      },
    );

    if (result is! Map) {
      throw const FormatException(
        'Notification preferences response is invalid.',
      );
    }

    return NotificationPreferences.fromJson(
      Map<String, dynamic>.from(result),
    );
  }
}

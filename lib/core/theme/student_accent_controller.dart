import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'student_accent.dart';

enum ScheduleDisplayMode {
  classic,
  status,
  student,
}

extension ScheduleDisplayModeX on ScheduleDisplayMode {
  String get storageValue => switch (this) {
        ScheduleDisplayMode.classic => 'classic',
        ScheduleDisplayMode.status => 'status',
        ScheduleDisplayMode.student => 'student',
      };

  String get label => switch (this) {
        ScheduleDisplayMode.classic => '기본',
        ScheduleDisplayMode.status => '수업 상태',
        ScheduleDisplayMode.student => '학생별 색상',
      };

  String get description => switch (this) {
        ScheduleDisplayMode.classic =>
          '기존 시간표처럼 초록 계열 수업 칸에 학생 이름만 표시합니다.',
        ScheduleDisplayMode.status =>
          '정규·자율·보강·변경 상태를 색상과 상태 표시로 구분합니다.',
        ScheduleDisplayMode.student =>
          '학생마다 다른 색상으로 수업 칸을 구분합니다.',
      };

  IconData get icon => switch (this) {
        ScheduleDisplayMode.classic => Icons.calendar_view_week_outlined,
        ScheduleDisplayMode.status => Icons.sell_outlined,
        ScheduleDisplayMode.student => Icons.palette_outlined,
      };

  static ScheduleDisplayMode fromStorage(String? value) {
    return switch (value) {
      'status' => ScheduleDisplayMode.status,
      'student' => ScheduleDisplayMode.student,
      _ => ScheduleDisplayMode.classic,
    };
  }
}

class StudentAccentController extends ChangeNotifier {
  StudentAccentController(this.profileId);

  static const _storagePrefix = 'teacher_student_accent_v2';
  static const _displayModeStoragePrefix = 'schedule_display_mode_v1';

  final String profileId;
  final Map<String, Color> _overrides = {};
  final Map<String, Color> _generated = {};

  bool _loaded = false;
  ScheduleDisplayMode _displayMode = ScheduleDisplayMode.classic;

  bool get isLoaded => _loaded;
  ScheduleDisplayMode get displayMode => _displayMode;

  // Existing student-color UI can continue to use this compatibility getter.
  bool get isEnabled => _displayMode == ScheduleDisplayMode.student;
  bool get usesStudentColors => _displayMode == ScheduleDisplayMode.student;
  bool get usesStatusStyle => _displayMode == ScheduleDisplayMode.status;
  bool get usesClassicStyle => _displayMode == ScheduleDisplayMode.classic;

  String get _profilePrefix => '$_storagePrefix:$profileId:';
  String get _displayModeStorageKey =>
      '$_displayModeStoragePrefix:$profileId';

  Future<void> load() async {
    final preferences = await SharedPreferences.getInstance();
    final prefix = _profilePrefix;

    // A missing key intentionally falls back to the pre-3.3 classic view.
    // Do not migrate the old boolean toggle: existing users must not have
    // their weekly timetable appearance changed automatically.
    _displayMode = ScheduleDisplayModeX.fromStorage(
      preferences.getString(_displayModeStorageKey),
    );

    _overrides.clear();

    for (final key in preferences.getKeys()) {
      if (!key.startsWith(prefix)) {
        continue;
      }

      final value = preferences.getInt(key);
      if (value == null) {
        continue;
      }

      final studentId = key.substring(prefix.length);
      if (studentId.isEmpty) {
        continue;
      }

      _overrides[studentId] = Color(value);
    }

    _generated.clear();
    _loaded = true;
    notifyListeners();
  }

  Future<void> setDisplayMode(ScheduleDisplayMode mode) async {
    if (_displayMode == mode) return;

    _displayMode = mode;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _displayModeStorageKey,
      mode.storageValue,
    );
    notifyListeners();
  }

  // Kept temporarily for callers that still treat student colors as a toggle.
  Future<void> setEnabled(bool enabled) {
    return setDisplayMode(
      enabled ? ScheduleDisplayMode.student : ScheduleDisplayMode.classic,
    );
  }

  Map<String, Color> assignments(Iterable<String> studentIds) {
    final ids = studentIds
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList()
      ..sort();

    for (final studentId in ids) {
      _generated.putIfAbsent(
        studentId,
        () => _nextAvailableDefault(studentId),
      );
    }

    return {
      for (final studentId in ids)
        studentId: _overrides[studentId] ?? _generated[studentId]!,
    };
  }

  Color colorFor(String studentId) {
    final override = _overrides[studentId];
    if (override != null) {
      return override;
    }

    return _generated.putIfAbsent(
      studentId,
      () => _nextAvailableDefault(studentId),
    );
  }

  bool hasOverride(String studentId) => _overrides.containsKey(studentId);

  Future<void> setColor(String studentId, Color color) async {
    _overrides[studentId] = color;

    _generated.removeWhere(
      (id, generatedColor) =>
          id != studentId &&
          generatedColor.toARGB32() == color.toARGB32() &&
          !_overrides.containsKey(id),
    );

    final preferences = await SharedPreferences.getInstance();
    await preferences.setInt(
      '$_profilePrefix$studentId',
      color.toARGB32(),
    );

    notifyListeners();
  }

  Future<void> resetColor(String studentId) async {
    _overrides.remove(studentId);
    _generated.remove(studentId);

    final preferences = await SharedPreferences.getInstance();
    await preferences.remove('$_profilePrefix$studentId');

    notifyListeners();
  }

  Future<void> resetAll() async {
    final preferences = await SharedPreferences.getInstance();
    final prefix = _profilePrefix;

    for (final key in preferences.getKeys().where(
      (key) => key.startsWith(prefix),
    )) {
      await preferences.remove(key);
    }

    _overrides.clear();
    _generated.clear();
    notifyListeners();
  }

  Color _nextAvailableDefault(String studentId) {
    final usedColorValues = <int>{
      ..._generated.values.map((color) => color.toARGB32()),
      ..._overrides.values.map((color) => color.toARGB32()),
    };

    final startIndex = studentAccentSeedIndex(studentId);

    for (var offset = 0; offset < studentAccentPalette.length; offset++) {
      final index = (startIndex + offset) % studentAccentPalette.length;
      final candidate = studentAccentPalette[index];

      if (!usedColorValues.contains(candidate.toARGB32())) {
        return candidate;
      }
    }

    return studentAccentPalette[startIndex];
  }
}

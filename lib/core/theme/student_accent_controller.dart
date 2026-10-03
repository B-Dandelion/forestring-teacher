import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'student_accent.dart';

class StudentAccentController extends ChangeNotifier {
  StudentAccentController(this.profileId);

  static const _storagePrefix = 'teacher_student_accent_v2';
  static const _enabledStoragePrefix = 'student_accent_enabled_v1';

  final String profileId;
  final Map<String, Color> _overrides = {};
  final Map<String, Color> _generated = {};

  bool _loaded = false;
  bool _enabled = false;

  bool get isLoaded => _loaded;
  bool get isEnabled => _enabled;

  String get _profilePrefix => '$_storagePrefix:$profileId:';
  String get _enabledStorageKey => '$_enabledStoragePrefix:$profileId';

  Future<void> load() async {
    final preferences = await SharedPreferences.getInstance();
    final prefix = _profilePrefix;
    _enabled = preferences.getBool(_enabledStorageKey) ?? false;

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

  Future<void> setEnabled(bool enabled) async {
    if (_enabled == enabled) return;

    _enabled = enabled;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_enabledStorageKey, enabled);
    notifyListeners();
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

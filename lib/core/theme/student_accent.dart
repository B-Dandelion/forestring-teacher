import 'package:flutter/material.dart';

const List<Color> _studentAccentPalette = [
  Color(0xff19764C), // emerald
  Color(0xff0F857A), // teal
  Color(0xff187FA8), // cyan blue
  Color(0xff2F6FBD), // blue
  Color(0xff4D5FC2), // royal blue
  Color(0xff6851B8), // indigo
  Color(0xff8E4DB0), // violet
  Color(0xffB4478A), // magenta
  Color(0xffC94F6D), // rose
  Color(0xffD65A4B), // coral red
  Color(0xffD8782D), // orange
  Color(0xffA8443F), // brick red
]

int _studentAccentHash(String studentId) {
  var hash = 0;

  for (final codeUnit in studentId.codeUnits) {
    hash = (hash * 31 + codeUnit) & 0x7fffffff;
  }

  return hash;
}

Color studentAccentColor(String studentId) {
  final hash = _studentAccentHash(studentId);
  return _studentAccentPalette[hash % _studentAccentPalette.length];
}

Map<String, Color> buildStudentAccentAssignments(
  Iterable<String> studentIds,
) {
  final ids = studentIds
      .where((id) => id.isNotEmpty)
      .toSet()
      .toList()
    ..sort();

  final assignments = <String, Color>{};
  final usedIndexes = <int>{};

  for (final studentId in ids) {
    final hash = _studentAccentHash(studentId);
    var index = hash % _studentAccentPalette.length;

    if (usedIndexes.length < _studentAccentPalette.length) {
      while (usedIndexes.contains(index)) {
        index = (index + 1) % _studentAccentPalette.length;
      }
      usedIndexes.add(index);
    }

    assignments[studentId] = _studentAccentPalette[index];
  }

  return assignments;
}

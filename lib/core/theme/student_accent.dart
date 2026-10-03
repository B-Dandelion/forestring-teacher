import 'package:flutter/material.dart';

const List<Color> _studentAccentPalette = [
  Color(0xff2F6B4F),
  Color(0xff397A76),
  Color(0xff4C6FA8),
  Color(0xffB5655D),
  Color(0xff9B5F78),
  Color(0xff6266A1),
  Color(0xff3F7F5F),
  Color(0xff477C91),
  Color(0xffA65D52),
  Color(0xff76556B),
  Color(0xff3C7C8C),
  Color(0xff425F89),
  Color(0xff668472),
  Color(0xff6A7FA3),
  Color(0xffB46E68),
  Color(0xff356E66),
  Color(0xff55728A),
  Color(0xff8E5269),
  Color(0xff4C806F),
  Color(0xffA36555),
  Color(0xff4A7880),
  Color(0xff875B78),
  Color(0xff466F58),
  Color(0xff596E93),
];

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

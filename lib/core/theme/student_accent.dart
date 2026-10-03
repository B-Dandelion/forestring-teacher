import 'package:flutter/material.dart';

const List<Color> _studentAccentPalette = [
  Color(0xff2F6B4F),
  Color(0xff4B7EA8),
  Color(0xffC47A55),
  Color(0xff7C6FA8),
  Color(0xff4C8C87),
  Color(0xffA37B42),
];

Color studentAccentColor(String studentId) {
  var hash = 0;

  for (final codeUnit in studentId.codeUnits) {
    hash = (hash * 31 + codeUnit) & 0x7fffffff;
  }

  return _studentAccentPalette[hash % _studentAccentPalette.length];
}

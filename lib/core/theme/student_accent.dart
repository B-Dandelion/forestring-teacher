import 'package:flutter/material.dart';

const List<Color> _studentAccentPalette = [
  Color(0xff2F6B4F), // forest green
  Color(0xff397A76), // muted teal
  Color(0xff4C6FA8), // soft blue
  Color(0xffB5655D), // muted coral
  Color(0xff9B5F78), // dusty rose
  Color(0xff6266A1), // muted indigo
];

Color studentAccentColor(String studentId) {
  var hash = 0;

  for (final codeUnit in studentId.codeUnits) {
    hash = (hash * 31 + codeUnit) & 0x7fffffff;
  }

  return _studentAccentPalette[hash % _studentAccentPalette.length];
}

import 'package:flutter/material.dart';

const List<Color> studentAccentPalette = [
  Color(0xff77C99A),
  Color(0xff64C6BB),
  Color(0xff6DBBE8),
  Color(0xff839DE8),
  Color(0xffA58BE2),
  Color(0xffC585D8),
  Color(0xffE487B5),
  Color(0xffEA8F9D),
  Color(0xffF0957E),
  Color(0xffECA56D),
  Color(0xff77BFCB),
  Color(0xffDD827B),
];

int studentAccentSeedIndex(String studentId) {
  var hash = 0;

  for (final codeUnit in studentId.codeUnits) {
    hash = (hash * 31 + codeUnit) & 0x7fffffff;
  }

  return hash % studentAccentPalette.length;
}

Color studentAccentColor(String studentId) {
  return studentAccentPalette[studentAccentSeedIndex(studentId)];
}

Color studentAccentForeground(Color accentColor) {
  return Color.lerp(
    accentColor,
    const Color(0xff21322A),
    0.48,
  )!;
}

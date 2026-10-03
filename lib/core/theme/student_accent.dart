import 'package:flutter/material.dart';

const List<Color> studentAccentPalette = [
  Color(0xff19764C),
  Color(0xff0F857A),
  Color(0xff187FA8),
  Color(0xff2F6FBD),
  Color(0xff4D5FC2),
  Color(0xff6851B8),
  Color(0xff8E4DB0),
  Color(0xffB4478A),
  Color(0xffC94F6D),
  Color(0xffD65A4B),
  Color(0xffD8782D),
  Color(0xffA8443F),
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

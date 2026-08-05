import 'package:flutter/material.dart';

abstract final class AppTextStyles {
  static const TextStyle pageTitle = TextStyle(
    fontSize: 21,
    fontWeight: FontWeight.w600,
    color: Color(0xFF171717),
  );
  static const TextStyle sectionTitle = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    color: Color(0xFF171717),
  );
  static const TextStyle listTitle = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w500,
    color: Color(0xFF171717),
  );
  static const TextStyle body = TextStyle(
    fontSize: 16,
    height: 1.35,
    color: Color(0xFF171717),
  );
  static const TextStyle bodyCompact = TextStyle(
    fontSize: 15,
    height: 1.3,
    color: Color(0xFF171717),
  );
  static const TextStyle supporting = TextStyle(
    fontSize: 14,
    color: Color(0xFF999999),
  );
  static const TextStyle caption = TextStyle(
    fontSize: 13,
    color: Color(0xFF999999),
  );
}

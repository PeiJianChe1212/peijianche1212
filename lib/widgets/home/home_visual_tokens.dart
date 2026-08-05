import 'package:flutter/material.dart';

abstract final class HomeVisualTokens {
  static const double radiusHero = 34;
  static const double radiusMainCard = 28;
  static const double radiusCard = 24;
  static const double radiusButton = 22;
  static const double radiusSmall = 16;

  static const double spacing2 = 2;
  static const double spacing4 = 4;
  static const double spacing8 = 8;
  static const double spacing10 = 10;
  static const double spacing12 = 12;
  static const double spacing14 = 14;
  static const double spacing18 = 18;
  static const double spacing22 = 22;
  static const double spacing24 = 24;

  static const EdgeInsets pagePadding = EdgeInsets.fromLTRB(18, 14, 18, 4);
  static const EdgeInsets statusBarPadding = EdgeInsets.fromLTRB(22, 5, 22, 0);

  static const Duration motionFast = Duration(milliseconds: 150);
  static const Duration motionStandard = Duration(milliseconds: 320);
  static const Duration motionPage = Duration(milliseconds: 420);
  static const Duration motionHero = Duration(milliseconds: 560);
  static const Duration motionAmbient = Duration(seconds: 7);

  static const Curve motionCurve = Curves.easeOutCubic;
  static const Curve motionEmphasizedCurve = Curves.easeOutQuart;

  static const double blurMain = 24;
  static const double blurCard = 18;
  static const double blurButton = 14;

  static const Color backgroundTop = Color(0xFF6978A8);
  static const Color backgroundMiddle = Color(0xFF3F4D76);
  static const Color backgroundBottom = Color(0xFF252E4B);
  static const Color ambientBlue = Color(0xFF9DB8F2);
  static const Color ambientViolet = Color(0xFFC0AEF2);
  static const Color ambientWarm = Color(0xFFE2C7DF);

  static const List<BoxShadow> heroShadow = [
    BoxShadow(color: Color(0x66000000), blurRadius: 38, offset: Offset(0, 20)),
    BoxShadow(color: Color(0x1A9CCBE5), blurRadius: 28, offset: Offset(0, -4)),
  ];

  static const List<BoxShadow> cardShadow = [
    BoxShadow(color: Color(0x33000000), blurRadius: 24, offset: Offset(0, 12)),
  ];

  static const List<BoxShadow> buttonShadow = [
    BoxShadow(color: Color(0x2E000000), blurRadius: 18, offset: Offset(0, 9)),
  ];
}

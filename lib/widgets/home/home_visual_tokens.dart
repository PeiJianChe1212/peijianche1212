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

  static const double blurMain = 28;
  static const double blurCard = 22;
  static const double blurButton = 18;

  // PeiLink 桌面背景
  // 从深蓝系统感调整为白紫玻璃氛围
  static const Color backgroundTop = Color(0xFFFAF9FD);
  static const Color backgroundMiddle = Color(0xFFF0EEF7);
  static const Color backgroundBottom = Color(0xFFE7EAF4);

  // 环境光
  static const Color ambientBlue = Color(0xFFB9CCF8);
  static const Color ambientViolet = Color(0xFFD5C9F2);
  static const Color ambientWarm = Color(0xFFF1DCE8);

  static const Color inkPrimary = Color(0xFF252A46);
  static const Color inkSecondary = Color(0xFF65708E);
  static const Color inkTertiary = Color(0xFF9299AF);
  static const Color brandBlue = Color(0xFF7487E8);
  static const Color brandViolet = Color(0xFF9B8BDF);

  static const List<BoxShadow> heroShadow = [
    BoxShadow(color: Color(0x242E3558), blurRadius: 38, offset: Offset(0, 20)),
    BoxShadow(color: Color(0x38FFFFFF), blurRadius: 32, offset: Offset(0, -4)),
  ];

  static const List<BoxShadow> cardShadow = [
    BoxShadow(color: Color(0x183A4264), blurRadius: 28, offset: Offset(0, 14)),
    BoxShadow(color: Color(0x70FFFFFF), blurRadius: 18, offset: Offset(0, -4)),
  ];

  static const List<BoxShadow> buttonShadow = [
    BoxShadow(color: Color(0x1C3A4264), blurRadius: 24, offset: Offset(0, 12)),
    BoxShadow(color: Color(0x66FFFFFF), blurRadius: 18, offset: Offset(0, -3)),
  ];
}

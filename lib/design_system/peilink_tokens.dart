import 'package:flutter/material.dart';

abstract final class PeiLinkSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double section = 28;

  static const EdgeInsets page = EdgeInsets.fromLTRB(lg, md, lg, section);
}

abstract final class PeiLinkRadius {
  static const double small = 10;
  static const double input = 14;
  static const double card = 18;
  static const double largeCard = 26;
  static const double sheet = 28;
  static const double pill = 999;
}

abstract final class PeiLinkColors {
  static const Color brand = Color(0xFF7568D9);
  static const Color brandSecondary = Color(0xFF7893EA);
  static const Color textPrimary = Color(0xFF252A46);
  static const Color textSecondary = Color(0xFF65708E);
  static const Color textTertiary = Color(0xFF9299AF);
  static const Color surface = Color(0xDFFFFFFF);
  static const Color surfaceElevated = Color(0xF2FFFFFF);
  static const Color surfaceSubtle = Color(0xA8FFFFFF);
  static const Color border = Color(0x8AFFFFFF);
  static const Color divider = Color(0x18737B9B);
  static const Color disabled = Color(0xFFB8BDCC);
  static const Color success = Color(0xFF55AD83);
  static const Color warning = Color(0xFFE2A84C);
  static const Color danger = Color(0xFFD95D70);
  static const Color onDark = Colors.white;
}

abstract final class PeiLinkTypography {
  static const TextStyle pageTitle = TextStyle(
    color: PeiLinkColors.textPrimary,
    fontSize: 22,
    fontWeight: FontWeight.w700,
    height: 1.2,
  );
  static const TextStyle pageSubtitle = TextStyle(
    color: PeiLinkColors.textSecondary,
    fontSize: 13,
    height: 1.35,
  );
  static const TextStyle sectionTitle = TextStyle(
    color: PeiLinkColors.textSecondary,
    fontSize: 13,
    fontWeight: FontWeight.w700,
  );
  static const TextStyle cardTitle = TextStyle(
    color: PeiLinkColors.textPrimary,
    fontSize: 16,
    fontWeight: FontWeight.w600,
  );
  static const TextStyle body = TextStyle(
    color: PeiLinkColors.textPrimary,
    fontSize: 15,
    height: 1.4,
  );
  static const TextStyle secondary = TextStyle(
    color: PeiLinkColors.textSecondary,
    fontSize: 13,
    height: 1.4,
  );
  static const TextStyle caption = TextStyle(
    color: PeiLinkColors.textTertiary,
    fontSize: 12,
    height: 1.35,
  );
  static const TextStyle button = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w700,
  );
  static const TextStyle status = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w700,
  );
}

abstract final class PeiLinkMotion {
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration normal = Duration(milliseconds: 280);
  static const Duration slow = Duration(milliseconds: 420);
  static const Curve standard = Curves.easeOutCubic;
}

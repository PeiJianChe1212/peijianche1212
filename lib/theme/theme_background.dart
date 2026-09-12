import 'package:flutter/material.dart';

enum BackgroundPattern {
  butterfly,
  petals,
  osmanthus,
  ginkgo,
  snow,
  rain,
  waves,
  aurora,
}

@immutable
class ThemeBackground {
  const ThemeBackground({
    required this.id,
    required this.name,
    required this.gradient,
    required this.opacity,
    this.imagePath,
    this.pattern,
  }) : assert(opacity >= 0 && opacity <= 1);

  final String id;
  final String name;
  final String? imagePath;
  final BackgroundPattern? pattern;
  final Gradient gradient;
  final double opacity;

  Color get primaryColor => gradient.colors.first;
  Color get secondaryColor => gradient.colors.last;
  bool get isDark {
    final colors = gradient.colors;
    final luminance =
        colors
            .map((color) => color.computeLuminance())
            .reduce((a, b) => a + b) /
        colors.length;
    return luminance < 0.35;
  }

  ThemeBackground copyWith({
    String? id,
    String? name,
    String? imagePath,
    BackgroundPattern? pattern,
    Gradient? gradient,
    double? opacity,
  }) {
    return ThemeBackground(
      id: id ?? this.id,
      name: name ?? this.name,
      imagePath: imagePath ?? this.imagePath,
      pattern: pattern ?? this.pattern,
      gradient: gradient ?? this.gradient,
      opacity: opacity ?? this.opacity,
    );
  }
}

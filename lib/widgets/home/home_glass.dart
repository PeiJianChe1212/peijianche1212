import 'dart:ui';

import 'package:flutter/material.dart';

import 'home_visual_tokens.dart';

enum HomeGlassLevel { main, card, button }

class HomeGlass extends StatelessWidget {
  const HomeGlass({
    super.key,
    required this.child,
    this.level = HomeGlassLevel.card,
    this.borderRadius,
    this.padding,
    this.tint,
    this.blurSigma,
    this.surfaceOpacity,
    this.shadows,
  });

  final Widget child;
  final HomeGlassLevel level;
  final double? borderRadius;
  final EdgeInsetsGeometry? padding;
  final Color? tint;
  final double? blurSigma;
  final double? surfaceOpacity;
  final List<BoxShadow>? shadows;

  double get _radius =>
      borderRadius ??
      switch (level) {
        HomeGlassLevel.main => HomeVisualTokens.radiusMainCard,
        HomeGlassLevel.card => HomeVisualTokens.radiusCard,
        HomeGlassLevel.button => HomeVisualTokens.radiusButton,
      };

  double get _blur => switch (level) {
    HomeGlassLevel.main => HomeVisualTokens.blurMain,
    HomeGlassLevel.card => HomeVisualTokens.blurCard,
    HomeGlassLevel.button => HomeVisualTokens.blurButton,
  };

  double get _opacity => switch (level) {
    HomeGlassLevel.main => 0.460,
    HomeGlassLevel.card => 0.340,
    HomeGlassLevel.button => 0.300,
  };

  List<BoxShadow> get _shadow => switch (level) {
    HomeGlassLevel.main => HomeVisualTokens.cardShadow,
    HomeGlassLevel.card => HomeVisualTokens.cardShadow,
    HomeGlassLevel.button => HomeVisualTokens.buttonShadow,
  };

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(_radius);
    final baseTint = Color.lerp(Colors.white, tint ?? Colors.white, 0.12)!;
    final opacity = surfaceOpacity ?? _opacity;

    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: blurSigma ?? _blur,
          sigmaY: blurSigma ?? _blur,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                baseTint.withValues(alpha: (opacity + 0.18).clamp(0, 1)),
                baseTint.withValues(alpha: opacity),
                Colors.white.withValues(alpha: opacity * 0.62),
              ],
              stops: const [0, 0.48, 1],
            ),
            borderRadius: radius,
            border: Border.all(
              color: Colors.white.withValues(
                alpha: level == HomeGlassLevel.main ? 0.76 : 0.58,
              ),
            ),
            boxShadow: shadows ?? _shadow,
          ),
          child: Stack(
            children: [
              Positioned(
                top: 0,
                left: _radius * 0.55,
                right: _radius * 0.55,
                child: Container(
                  height: 1,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.transparent,
                        Colors.white.withValues(alpha: 0.92),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
              Padding(padding: padding ?? EdgeInsets.zero, child: child),
            ],
          ),
        ),
      ),
    );
  }
}

class HomeGlassButton extends StatefulWidget {
  const HomeGlassButton({
    super.key,
    required this.child,
    required this.onTap,
    this.level = HomeGlassLevel.button,
    this.borderRadius,
    this.tint,
  });

  final Widget child;
  final VoidCallback? onTap;
  final HomeGlassLevel level;
  final double? borderRadius;
  final Color? tint;

  @override
  State<HomeGlassButton> createState() => _HomeGlassButtonState();
}

class _HomeGlassButtonState extends State<HomeGlassButton> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;

    return Semantics(
      button: true,
      enabled: enabled,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onTapDown: enabled ? (_) => _setPressed(true) : null,
        onTapCancel: enabled ? () => _setPressed(false) : null,
        onTapUp: enabled ? (_) => _setPressed(false) : null,
        child: AnimatedScale(
          scale: _pressed ? 0.965 : 1,
          duration: HomeVisualTokens.motionFast,
          curve: HomeVisualTokens.motionCurve,
          child: AnimatedOpacity(
            opacity: enabled ? (_pressed ? 0.86 : 1) : 0.45,
            duration: HomeVisualTokens.motionFast,
            child: HomeGlass(
              level: widget.level,
              borderRadius: widget.borderRadius,
              tint: widget.tint,
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}

import 'dart:ui';

import 'package:flutter/material.dart';

import 'peilink_tokens.dart';

enum PeiLinkSurfaceLevel { normal, elevated, subtle }

class PeiLinkSurface extends StatelessWidget {
  const PeiLinkSurface({
    super.key,
    required this.child,
    this.level = PeiLinkSurfaceLevel.normal,
    this.padding,
    this.selected = false,
    this.enabled = true,
    this.borderRadius,
  });

  final Widget child;
  final PeiLinkSurfaceLevel level;
  final EdgeInsetsGeometry? padding;
  final bool selected;
  final bool enabled;
  final BorderRadiusGeometry? borderRadius;

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? BorderRadius.circular(PeiLinkRadius.card);
    final color = switch (level) {
      PeiLinkSurfaceLevel.normal => PeiLinkColors.surface,
      PeiLinkSurfaceLevel.elevated => PeiLinkColors.surfaceElevated,
      PeiLinkSurfaceLevel.subtle => PeiLinkColors.surfaceSubtle,
    };
    final blur = level == PeiLinkSurfaceLevel.subtle ? 12.0 : 20.0;

    return AnimatedOpacity(
      opacity: enabled ? 1 : 0.48,
      duration: PeiLinkMotion.fast,
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: color,
              borderRadius: radius,
              border: Border.all(
                color: selected
                    ? PeiLinkColors.brand.withValues(alpha: 0.5)
                    : PeiLinkColors.border,
              ),
              boxShadow: level == PeiLinkSurfaceLevel.elevated
                  ? const [
                      BoxShadow(
                        color: Color(0x173A4264),
                        blurRadius: 24,
                        offset: Offset(0, 12),
                      ),
                    ]
                  : null,
            ),
            child: Padding(padding: padding ?? EdgeInsets.zero, child: child),
          ),
        ),
      ),
    );
  }
}

class PeiLinkGlassCard extends StatelessWidget {
  const PeiLinkGlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(PeiLinkSpacing.lg),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => PeiLinkSurface(
    level: PeiLinkSurfaceLevel.elevated,
    padding: padding,
    child: child,
  );
}

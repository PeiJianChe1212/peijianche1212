import 'package:flutter/material.dart';

import 'peilink_tokens.dart';

enum _ButtonKind { primary, secondary, text, danger }

class PeiLinkPrimaryButton extends StatelessWidget {
  const PeiLinkPrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.loading = false,
    this.icon,
  });
  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => _PeiLinkButton(
    kind: _ButtonKind.primary,
    label: label,
    onPressed: onPressed,
    loading: loading,
    icon: icon,
  );
}

class PeiLinkSecondaryButton extends StatelessWidget {
  const PeiLinkSecondaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.loading = false,
    this.icon,
  });
  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => _PeiLinkButton(
    kind: _ButtonKind.secondary,
    label: label,
    onPressed: onPressed,
    loading: loading,
    icon: icon,
  );
}

class PeiLinkTextButton extends StatelessWidget {
  const PeiLinkTextButton({
    super.key,
    required this.label,
    this.onPressed,
    this.loading = false,
    this.icon,
  });
  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => _PeiLinkButton(
    kind: _ButtonKind.text,
    label: label,
    onPressed: onPressed,
    loading: loading,
    icon: icon,
  );
}

class PeiLinkDangerButton extends StatelessWidget {
  const PeiLinkDangerButton({
    super.key,
    required this.label,
    this.onPressed,
    this.loading = false,
    this.icon,
  });
  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => _PeiLinkButton(
    kind: _ButtonKind.danger,
    label: label,
    onPressed: onPressed,
    loading: loading,
    icon: icon,
  );
}

class _PeiLinkButton extends StatelessWidget {
  const _PeiLinkButton({
    required this.kind,
    required this.label,
    this.onPressed,
    required this.loading,
    this.icon,
  });
  final _ButtonKind kind;
  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    final foreground = switch (kind) {
      _ButtonKind.primary || _ButtonKind.danger => Colors.white,
      _ButtonKind.secondary => PeiLinkColors.brand,
      _ButtonKind.text => PeiLinkColors.brand,
    };
    final background = switch (kind) {
      _ButtonKind.primary => PeiLinkColors.brand,
      _ButtonKind.danger => PeiLinkColors.danger,
      _ButtonKind.secondary => Colors.white.withValues(alpha: 0.72),
      _ButtonKind.text => Colors.transparent,
    };
    return Semantics(
      button: true,
      enabled: enabled,
      child: AnimatedOpacity(
        opacity: enabled ? 1 : 0.5,
        duration: PeiLinkMotion.fast,
        child: SizedBox(
          height: 48,
          child: Material(
            color: background,
            borderRadius: BorderRadius.circular(PeiLinkRadius.input),
            child: InkWell(
              onTap: enabled ? onPressed : null,
              borderRadius: BorderRadius.circular(PeiLinkRadius.input),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: PeiLinkSpacing.lg,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (loading)
                      SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: foreground,
                        ),
                      )
                    else if (icon != null)
                      Icon(icon, size: 19, color: foreground),
                    if (loading || icon != null)
                      const SizedBox(width: PeiLinkSpacing.sm),
                    Flexible(
                      child: Text(
                        label,
                        overflow: TextOverflow.ellipsis,
                        style: PeiLinkTypography.button.copyWith(
                          color: foreground,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import 'peilink_tokens.dart';

class PeiLinkSectionHeader extends StatelessWidget {
  const PeiLinkSectionHeader({
    super.key,
    required this.title,
    this.description,
  });
  final String title;
  final String? description;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      PeiLinkSpacing.xs,
      0,
      PeiLinkSpacing.xs,
      PeiLinkSpacing.sm,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: PeiLinkTypography.sectionTitle),
        if (description != null) ...[
          const SizedBox(height: PeiLinkSpacing.xs),
          Text(description!, style: PeiLinkTypography.caption),
        ],
      ],
    ),
  );
}

class PeiLinkSettingsTile extends StatelessWidget {
  const PeiLinkSettingsTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.value,
    this.onTap,
    this.switchValue,
    this.onSwitchChanged,
    this.trailing,
    this.showArrow = true,
    this.danger = false,
    this.enabled = true,
    this.iconColor,
    this.iconBackground,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final String? value;
  final VoidCallback? onTap;
  final bool? switchValue;
  final ValueChanged<bool>? onSwitchChanged;
  final Widget? trailing;
  final bool showArrow;
  final bool danger;
  final bool enabled;
  final Color? iconColor;
  final Color? iconBackground;

  @override
  Widget build(BuildContext context) {
    final accent = danger
        ? PeiLinkColors.danger
        : (iconColor ?? PeiLinkColors.brand);
    Widget? end = trailing;
    if (end == null && switchValue != null) {
      end = Switch.adaptive(
        value: switchValue!,
        onChanged: enabled ? onSwitchChanged : null,
      );
    } else if (end == null && value != null) {
      end = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              value!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: PeiLinkTypography.secondary,
            ),
          ),
          if (showArrow) const SizedBox(width: PeiLinkSpacing.xs),
          if (showArrow)
            const Icon(
              Icons.chevron_right_rounded,
              color: PeiLinkColors.textTertiary,
            ),
        ],
      );
    } else if (end == null && showArrow) {
      end = const Icon(
        Icons.chevron_right_rounded,
        color: PeiLinkColors.textTertiary,
      );
    }

    return Semantics(
      enabled: enabled,
      button: onTap != null,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: PeiLinkSpacing.lg,
            vertical: PeiLinkSpacing.md,
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: iconBackground ?? accent.withValues(alpha: 0.11),
                  borderRadius: BorderRadius.circular(PeiLinkRadius.small),
                ),
                child: Icon(icon, color: accent, size: 21),
              ),
              const SizedBox(width: PeiLinkSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: PeiLinkTypography.cardTitle.copyWith(
                        color: danger ? PeiLinkColors.danger : null,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        subtitle!,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: PeiLinkTypography.secondary,
                      ),
                    ],
                  ],
                ),
              ),
              if (end != null) ...[
                const SizedBox(width: PeiLinkSpacing.sm),
                Flexible(child: end),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class PeiLinkSettingsDivider extends StatelessWidget {
  const PeiLinkSettingsDivider({super.key});
  @override
  Widget build(BuildContext context) => const Divider(
    height: 1,
    indent: 68,
    endIndent: PeiLinkSpacing.lg,
    color: PeiLinkColors.divider,
  );
}

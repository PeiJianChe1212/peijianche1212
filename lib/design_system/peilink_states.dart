import 'package:flutter/material.dart';

import 'peilink_buttons.dart';
import 'peilink_tokens.dart';

class PeiLinkEmptyState extends StatelessWidget {
  const PeiLinkEmptyState({
    super.key,
    required this.title,
    this.description,
    this.icon = Icons.auto_awesome_rounded,
    this.actionLabel,
    this.onAction,
    this.compact = false,
  });
  final String title;
  final String? description;
  final IconData icon;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool compact;
  @override
  Widget build(BuildContext context) => _PeiLinkState(
    icon: icon,
    title: title,
    description: description,
    actionLabel: actionLabel,
    onAction: onAction,
    compact: compact,
  );
}

class PeiLinkErrorState extends StatelessWidget {
  const PeiLinkErrorState({
    super.key,
    required this.title,
    this.description,
    this.onRetry,
    this.compact = false,
  });
  final String title;
  final String? description;
  final VoidCallback? onRetry;
  final bool compact;
  @override
  Widget build(BuildContext context) => _PeiLinkState(
    icon: Icons.error_outline_rounded,
    iconColor: PeiLinkColors.danger,
    title: title,
    description: description,
    actionLabel: onRetry == null ? null : '重试',
    onAction: onRetry,
    compact: compact,
  );
}

class PeiLinkLoadingState extends StatelessWidget {
  const PeiLinkLoadingState({
    super.key,
    this.label = '正在加载',
    this.compact = false,
  });
  final String label;
  final bool compact;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: EdgeInsets.all(
        compact ? PeiLinkSpacing.md : PeiLinkSpacing.section,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox.square(
            dimension: 26,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: PeiLinkColors.brand,
            ),
          ),
          const SizedBox(height: PeiLinkSpacing.md),
          Text(label, style: PeiLinkTypography.secondary),
        ],
      ),
    ),
  );
}

class _PeiLinkState extends StatelessWidget {
  const _PeiLinkState({
    required this.icon,
    this.iconColor = PeiLinkColors.brand,
    required this.title,
    this.description,
    this.actionLabel,
    this.onAction,
    required this.compact,
  });
  final IconData icon;
  final Color iconColor;
  final String title;
  final String? description;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool compact;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: EdgeInsets.all(
        compact ? PeiLinkSpacing.lg : PeiLinkSpacing.section,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: compact ? 48 : 64,
            height: compact ? 48 : 64,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: iconColor, size: compact ? 24 : 30),
          ),
          const SizedBox(height: PeiLinkSpacing.md),
          Text(
            title,
            textAlign: TextAlign.center,
            style: PeiLinkTypography.cardTitle,
          ),
          if (description != null) ...[
            const SizedBox(height: PeiLinkSpacing.sm),
            Text(
              description!,
              textAlign: TextAlign.center,
              style: PeiLinkTypography.secondary,
            ),
          ],
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: PeiLinkSpacing.lg),
            PeiLinkSecondaryButton(label: actionLabel!, onPressed: onAction),
          ],
        ],
      ),
    ),
  );
}

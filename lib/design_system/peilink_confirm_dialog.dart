import 'package:flutter/material.dart';

import 'peilink_buttons.dart';
import 'peilink_surface.dart';
import 'peilink_tokens.dart';

class PeiLinkConfirmDialog extends StatelessWidget {
  const PeiLinkConfirmDialog({
    super.key,
    required this.title,
    required this.description,
    this.confirmLabel = '确认',
    this.cancelLabel = '取消',
    this.danger = false,
    this.irreversibleWarning,
  });
  final String title;
  final String description;
  final String confirmLabel;
  final String cancelLabel;
  final bool danger;
  final String? irreversibleWarning;

  static Future<bool> show(
    BuildContext context, {
    required String title,
    required String description,
    String confirmLabel = '确认',
    String cancelLabel = '取消',
    bool danger = false,
    String? irreversibleWarning,
  }) async =>
      await showDialog<bool>(
        context: context,
        builder: (_) => PeiLinkConfirmDialog(
          title: title,
          description: description,
          confirmLabel: confirmLabel,
          cancelLabel: cancelLabel,
          danger: danger,
          irreversibleWarning: irreversibleWarning,
        ),
      ) ??
      false;

  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: Colors.transparent,
    insetPadding: const EdgeInsets.all(PeiLinkSpacing.xl),
    child: PeiLinkSurface(
      level: PeiLinkSurfaceLevel.elevated,
      borderRadius: BorderRadius.circular(PeiLinkRadius.sheet),
      padding: const EdgeInsets.all(PeiLinkSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: PeiLinkTypography.pageTitle),
          const SizedBox(height: PeiLinkSpacing.md),
          Text(description, style: PeiLinkTypography.body),
          if (irreversibleWarning != null) ...[
            const SizedBox(height: PeiLinkSpacing.sm),
            Text(
              irreversibleWarning!,
              style: PeiLinkTypography.secondary.copyWith(
                color: PeiLinkColors.danger,
              ),
            ),
          ],
          const SizedBox(height: PeiLinkSpacing.xl),
          Row(
            children: [
              Expanded(
                child: PeiLinkSecondaryButton(
                  label: cancelLabel,
                  onPressed: () => Navigator.pop(context, false),
                ),
              ),
              const SizedBox(width: PeiLinkSpacing.md),
              Expanded(
                child: danger
                    ? PeiLinkDangerButton(
                        label: confirmLabel,
                        onPressed: () => Navigator.pop(context, true),
                      )
                    : PeiLinkPrimaryButton(
                        label: confirmLabel,
                        onPressed: () => Navigator.pop(context, true),
                      ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

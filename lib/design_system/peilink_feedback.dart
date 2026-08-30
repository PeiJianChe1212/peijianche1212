import 'package:flutter/material.dart';

import 'peilink_tokens.dart';

enum PeiLinkFeedbackType { success, info, warning, error }

abstract final class PeiLinkFeedback {
  static void show(
    BuildContext context,
    String message, {
    PeiLinkFeedbackType type = PeiLinkFeedbackType.info,
  }) {
    final (icon, color) = switch (type) {
      PeiLinkFeedbackType.success => (
        Icons.check_circle_outline_rounded,
        PeiLinkColors.success,
      ),
      PeiLinkFeedbackType.info => (
        Icons.info_outline_rounded,
        PeiLinkColors.brand,
      ),
      PeiLinkFeedbackType.warning => (
        Icons.warning_amber_rounded,
        PeiLinkColors.warning,
      ),
      PeiLinkFeedbackType.error => (
        Icons.error_outline_rounded,
        PeiLinkColors.danger,
      ),
    };
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: PeiLinkColors.surfaceElevated,
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PeiLinkRadius.input),
        ),
        content: Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: PeiLinkSpacing.sm),
            Expanded(child: Text(message, style: PeiLinkTypography.body)),
          ],
        ),
      ),
    );
  }
}

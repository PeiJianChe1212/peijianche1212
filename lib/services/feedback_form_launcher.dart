import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../design_system/peilink_feedback.dart';

class FeedbackFormLauncher {
  const FeedbackFormLauncher._();

  static const MethodChannel channel = MethodChannel('peilink/external_url');
  static const String formUrl = 'https://my.feishu.cn/share/base/shrcnqI8zztnRpy423JaPUqtUid';

  static Future<void> open(BuildContext context) async {
    try {
      final opened = await channel.invokeMethod<bool>('open', formUrl);
      if (opened != true && context.mounted) {
        PeiLinkFeedback.show(
          context,
          '无法打开反馈问卷',
          type: PeiLinkFeedbackType.warning,
        );
      }
    } catch (error) {
      if (context.mounted) {
        PeiLinkFeedback.show(
          context,
          '打开失败：$error',
          type: PeiLinkFeedbackType.error,
        );
      }
    }
  }
}

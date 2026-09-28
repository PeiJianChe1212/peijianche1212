import 'dart:io';

import 'package:flutter/services.dart';

class FeedbackSubmissionService {
  static const MethodChannel _channel = MethodChannel('peilink/external_url');
  static const String formUrl = String.fromEnvironment(
    'PEILINK_FEEDBACK_FORM_URL',
    defaultValue: 'https://my.feishu.cn/share/base/shrcnqI8zztnRpy423JaPUqtUid',
  );
  static const String appVersion = String.fromEnvironment(
    'PEILINK_APP_VERSION',
    defaultValue: '0.6.7+17',
  );

  String systemSummary() {
    return '${Platform.operatingSystem} ${Platform.operatingSystemVersion}';
  }

  String deviceSummary() {
    return '${Platform.numberOfProcessors} 核 · ${Platform.localeName}';
  }

  String buildReport({
    required String category,
    required String title,
    required String content,
    required String contact,
    required bool hasScreenshot,
    DateTime? submittedAt,
  }) {
    final time = submittedAt ?? DateTime.now();
    return [
      '【类型】$category',
      '【标题】$title',
      '【内容】$content',
      if (contact.trim().isNotEmpty) '【联系方式】${contact.trim()}',
      '【截图】${hasScreenshot ? '已选择，请在问卷中上传' : '未选择'}',
      '【PeiLink版本】$appVersion',
      '【系统版本】${systemSummary()}',
      '【设备信息】${deviceSummary()}',
      '【提交时间】${time.toIso8601String()}',
    ].join('\n');
  }

  Future<void> copyAndOpen({required String report}) async {
    await Clipboard.setData(ClipboardData(text: report));
    final uri = Uri.parse(formUrl).replace(
      queryParameters: {
        ...Uri.parse(formUrl).queryParameters,
        'source': 'PeiLink',
        'version': appVersion,
      },
    );
    final opened = await _channel.invokeMethod<bool>('open', uri.toString());
    if (opened != true) throw StateError('无法打开外部反馈问卷。');
  }
}

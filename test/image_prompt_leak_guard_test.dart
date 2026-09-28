import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/models/chat_message.dart';
import 'package:peijianche_app/platform/storage/native_platform_storage.dart';
import 'package:peijianche_app/services/chat_image_task_manager.dart';
import 'package:peijianche_app/services/chat_storage_service.dart';
import 'package:peijianche_app/services/deepseek_service.dart';
import 'package:peijianche_app/services/internal_prompt_leak_guard.dart';

const internalPrompt = '''
【图片主体】
未明确要求人物出镜的自然生活分享。事实依据：哇塞这个我也想看看

【人物出镜】
画面中不出现人物。

【构图与视觉风格】
生活记录式构图，半写实 2.5D、高级 CG。
''';

void main() {
  test('direct and follow-up captions reject internal image prompts', () {
    expect(InternalPromptLeakGuard.looksInternal(internalPrompt), isTrue);
    for (final request in ['给我看看腹肌', '给我看看嘛', '哇塞这个我也想看看']) {
      expect(
        DeepSeekService.sanitizeImageCaption(
          internalPrompt,
          userRequest: request,
        ),
        '给你看。',
      );
    }
  });

  test('timeline only persists image result and safe visible caption', () {
    final messages = buildGeneratedImageTimelineMessages(
      imagePath: '/images/result.png',
      caption: internalPrompt,
      taskId: 'follow-up',
    );
    expect(messages, hasLength(1));
    expect(messages.single.content, isEmpty);
    expect(messages.single.metadata, isNot(contains('generationPrompt')));
    expect(messages.single.metadata, isNot(contains('internalPrompt')));
  });

  test(
    'persistence and reopen scrub legacy leaked text and metadata',
    () async {
      final root = await Directory.systemTemp.createTemp('prompt_leak_');
      addTearDown(() => root.delete(recursive: true));
      final storage = NativePlatformStorage(root.path);
      await storage.writeText(
        'characters/role-a/chat_history.json',
        jsonEncode([
          ChatMessage(
            role: 'assistant',
            content: internalPrompt,
            metadata: const {'generationPrompt': internalPrompt},
          ).toJson(),
        ]),
      );
      final service = ChatStorageService(
        characterId: 'role-a',
        storage: storage,
      );
      final reopened = await service.loadMessages();
      expect(reopened.single.content, '给你看。');
      expect(reopened.single.metadata, isNot(contains('generationPrompt')));
      await service.saveMessages(reopened);
      expect(
        await storage.readText('characters/role-a/chat_history.json'),
        isNot(contains('【图片主体】')),
      );
    },
  );
}

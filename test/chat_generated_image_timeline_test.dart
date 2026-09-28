import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/models/chat_message.dart';
import 'package:peijianche_app/platform/storage/native_platform_storage.dart';
import 'package:peijianche_app/services/chat_image_task_manager.dart';
import 'package:peijianche_app/services/chat_storage_service.dart';
import 'package:peijianche_app/services/deepseek_service.dart';

void main() {
  test('generated image and caption become two ordered ordinary messages', () {
    final messages = buildGeneratedImageTimelineMessages(
      imagePath: '/images/result.png',
      caption: '有点乱，别嫌弃。',
      taskId: 'task-1',
    );

    expect(messages, hasLength(2));
    expect(messages.first.type, MessageType.image);
    expect(messages.first.content, isEmpty);
    expect(messages.first.metadata['imagePath'], '/images/result.png');
    expect(messages.last.type, MessageType.text);
    expect(messages.last.role, 'assistant');
    expect(messages.last.content, '有点乱，别嫌弃。');
    expect(messages.map((message) => message.metadata['taskId']).toSet(), {
      'task-1',
    });
  });

  test('empty generated caption keeps image-only delivery', () {
    final messages = buildGeneratedImageTimelineMessages(
      imagePath: '/images/object.png',
      caption: '  ',
      taskId: 'task-2',
    );
    expect(messages, hasLength(1));
    expect(messages.single.type, MessageType.image);
  });

  test('background persistence remains bound to the task character', () async {
    final root = await Directory.systemTemp.createTemp(
      'peilink_generated_timeline_',
    );
    addTearDown(() => root.delete(recursive: true));
    final storage = NativePlatformStorage(root.path);

    await persistGeneratedImageTimeline(
      characterId: 'role-a',
      imagePath: '/images/character.png',
      caption: '看清楚了？',
      taskId: 'task-role-a',
      storage: storage,
    );

    final roleA = await ChatStorageService(
      characterId: 'role-a',
      storage: storage,
    ).loadMessages();
    final roleB = await ChatStorageService(
      characterId: 'role-b',
      storage: storage,
    ).loadMessages();
    expect(roleA.map((message) => message.type), [
      MessageType.image,
      MessageType.text,
    ]);
    expect(roleB, isEmpty);
  });

  test('image caption sanitizer preserves complete short replies', () {
    expect(
      DeepSeekService.sanitizeImageCaption('先等着，我给你看看。', userRequest: '给我看看腹肌'),
      '先等着，我给你看看。',
    );
    expect(
      DeepSeekService.sanitizeImageCaption(
        '（掀起衣摆）看清楚了吗？',
        userRequest: '给我看看腹肌',
      ),
      '（掀起衣摆）看清楚了吗？',
    );
    expect(
      DeepSeekService.sanitizeImageCaption('看吧。满意了吗？', userRequest: '给我看看你'),
      '看吧。满意了吗？',
    );
    const longerButComplete = '（把衣摆往上掀了掀）不是一直想看么，这下总该满意了吧？';
    expect(
      DeepSeekService.sanitizeImageCaption(
        longerButComplete,
        userRequest: '给我看看腹肌',
      ),
      longerButComplete,
    );
  });

  test('image caption sanitizer removes templated opening and full repeat', () {
    final detemplated = DeepSeekService.sanitizeImageCaption(
      '喏，刚拍的，你看看怎么样？',
      userRequest: '给我看看你',
    );
    expect(detemplated, isNot(startsWith('喏')));
    expect(detemplated, isNot(contains('刚拍的')));
    expect(detemplated, '给你看。');
    expect(
      DeepSeekService.sanitizeImageCaption('你要的腹肌。', userRequest: '给我看看腹肌'),
      '给你看。',
    );
    expect(
      DeepSeekService.sanitizeImageCaption('给我看看腹肌。', userRequest: '给我看看腹肌'),
      '给你看。',
    );
  });

  test('separate generation tasks retain their own caption and task id', () {
    final taskA = buildGeneratedImageTimelineMessages(
      imagePath: '/images/abs.png',
      caption: '先等着，我给你看看。',
      taskId: 'task-abs',
    );
    final taskB = buildGeneratedImageTimelineMessages(
      imagePath: '/images/person.png',
      caption: '看吧，这下满意了？',
      taskId: 'task-person',
    );

    expect(taskA.last.content, '先等着，我给你看看。');
    expect(
      taskA.every((message) => message.metadata['taskId'] == 'task-abs'),
      isTrue,
    );
    expect(taskB.last.content, '看吧，这下满意了？');
    expect(
      taskB.every((message) => message.metadata['taskId'] == 'task-person'),
      isTrue,
    );
  });
}

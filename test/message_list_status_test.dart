import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/models/activity_status.dart';
import 'package:peijianche_app/models/life_moment.dart';
import 'package:peijianche_app/models/message_list_status.dart';
import 'package:peijianche_app/services/activity_context_service.dart';
import 'package:peijianche_app/services/life_moment_storage_service.dart';
import 'package:peijianche_app/widgets/peilink/role_status_mark.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory documents;

  setUp(() async {
    documents = await Directory.systemTemp.createTemp('message_status_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => documents.path);
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    if (await documents.exists()) await documents.delete(recursive: true);
  });

  test('稳定 Activity id 映射为轻量列表状态', () {
    ActivityStatus activity(String id, {bool sleeping = false}) =>
        ActivityStatus(
          id: id,
          label: id,
          emoji: '',
          detail: '',
          promptGuidance: '',
          isSleeping: sleeping,
        );

    expect(
      MessageListStatus.fromActivity(activity('working_morning')).label,
      '忙碌中',
    );
    expect(MessageListStatus.fromActivity(activity('resting')).label, '休息中');
    expect(
      MessageListStatus.fromActivity(
        activity('sleeping', sleeping: true),
      ).label,
      '睡觉中',
    );
    expect(
      MessageListStatus.fromActivity(activity('life_outside')).label,
      '外出中',
    );
    expect(MessageListStatus.fromActivity(activity('life_music')).label, '听歌中');
    expect(MessageListStatus.fromActivity(activity('unknown')).label, '在线');
  });

  test('消息列表状态按 characterId 分别读取 Life Moment', () async {
    final now = DateTime(2026, 8, 22, 20);
    Future<void> add(String characterId, String event) =>
        LifeMomentStorageService(characterId: characterId).addItem(
          LifeMomentCandidate(
            id: 'moment_$characterId',
            scene: '',
            event: event,
            detail: '',
            feeling: '',
            shareHook: '',
            occurredAt: now.subtract(const Duration(minutes: 10)),
          ),
        );

    await add('role_work', '正在办公室处理项目文件');
    await add('role_music', '戴着耳机听音乐');

    final work = await const ActivityContextService(
      characterId: 'role_work',
    ).resolve(now: now);
    final music = await const ActivityContextService(
      characterId: 'role_music',
    ).resolve(now: now);

    expect(MessageListStatus.fromActivity(work).label, '忙碌中');
    expect(MessageListStatus.fromActivity(music).label, '听歌中');
  });

  testWidgets('消息列表与聊天页可复用同一状态组件', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: RoleStatusMark(
            status: MessageListStatus(MessageListStatusKind.music, '听歌中'),
          ),
        ),
      ),
    );

    expect(find.text('听歌中'), findsOneWidget);
    expect(find.byIcon(Icons.music_note_rounded), findsOneWidget);
    expect(find.textContaining('AI'), findsNothing);
  });
}

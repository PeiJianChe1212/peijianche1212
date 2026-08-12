import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/models/chat_message.dart';
import 'package:peijianche_app/models/echo_item.dart';
import 'package:peijianche_app/models/relationship_growth.dart';
import 'package:peijianche_app/services/relationship_growth_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory documentsDirectory;

  setUp(() async {
    documentsDirectory = await Directory.systemTemp.createTemp(
      'relationship_growth_test_',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'getApplicationDocumentsDirectory') {
            return documentsDirectory.path;
          }
          return null;
        });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await documentsDirectory.delete(recursive: true);
  });

  test(
    'standard configuration provides configurable stages for levels 1-100',
    () {
      const config = RelationshipGrowthConfig.standard;
      expect(config.stageFor(1), '相识');
      expect(config.stageFor(11), '熟悉');
      expect(config.stageFor(35), '信赖');
      expect(config.stageFor(100), '永恒');
      expect(config.stages, hasLength(10));
    },
  );

  test('legacy profile without growth fields remains readable', () {
    final profile = RelationshipGrowthProfile.fromJson({
      'characterId': 'legacy-role',
    });

    expect(profile.levelFor(), 1);
    expect(profile.currentExperienceFor(), 0);
    expect(profile.stageFor(), '相识');
    expect(profile.history, isEmpty);
    expect(profile.gifts, isEmpty);
  });

  test('old character initializes once with a real initial record', () async {
    final service = RelationshipGrowthService(characterId: 'old-role');
    final metAt = DateTime.utc(2025, 1, 2);

    final first = await service.loadOrCreate(metAt: metAt);
    final second = await service.loadOrCreate(metAt: metAt);

    expect(first.levelFor(), 1);
    expect(first.history.single.title, '初次认识');
    expect(first.history.single.occurredAt, metAt);
    expect(second.history, hasLength(1));
  });

  test('chat milestones and Echo interactions are idempotent', () async {
    final service = RelationshipGrowthService(characterId: 'friend-role');
    final messages = List.generate(
      20,
      (index) => ChatMessage(
        id: 'message-$index',
        role: index.isEven ? 'user' : 'assistant',
        content: 'message',
        createdAt: DateTime.utc(2026, 1, 1).add(Duration(minutes: index)),
      ),
    );
    final echoes = [
      EchoItem(
        id: 'echo-liked',
        characterId: 'friend-role',
        content: 'echo',
        createdAt: DateTime.utc(2026, 1, 2),
        sourceType: EchoSourceType.manual,
        isLiked: true,
      ),
    ];

    final first = await service.synchronize(messages: messages, echoes: echoes);
    final second = await service.synchronize(
      messages: messages,
      echoes: echoes,
    );

    expect(first.totalExperience, 28);
    expect(first.history.where((item) => item.experience > 0), hasLength(3));
    expect(second.totalExperience, first.totalExperience);
    expect(second.history, hasLength(first.history.length));
  });

  test('giving a gift persists record and experience', () async {
    final service = RelationshipGrowthService(characterId: 'family-role');

    final updated = await service.giveGift(
      RelationshipGiftType.letter,
      at: DateTime.utc(2026, 8, 9, 12),
    );
    final restored = await service.loadOrCreate();

    expect(updated.gifts.single.type, RelationshipGiftType.letter);
    expect(updated.totalExperience, RelationshipGiftType.letter.experience);
    expect(restored.gifts.single.type, RelationshipGiftType.letter);
    expect(restored.history.any((event) => event.title == '收到礼物：一封信'), isTrue);
  });
}

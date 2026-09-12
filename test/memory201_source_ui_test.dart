import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/models/character_settings.dart';
import 'package:peijianche_app/models/character_user_profile.dart';
import 'package:peijianche_app/models/chat_message.dart';
import 'package:peijianche_app/models/memory_summary.dart';
import 'package:peijianche_app/models/user_memory.dart';
import 'package:peijianche_app/pages/memory_page.dart';
import 'package:peijianche_app/pages/memory_reprocessing_page.dart';
import 'package:peijianche_app/services/auto_memory_extraction_service.dart';
import 'package:peijianche_app/services/memory_center_controller.dart';
import 'package:peijianche_app/services/memory_source_resolver.dart';
import 'package:peijianche_app/widgets/memory_source_sheet.dart';

class _Controller extends MemoryCenterController {
  _Controller() : super(characterId: 'c');
  int sourceReads = 0, calls = 0;
  List<String> requested = [];
  List<ResolvedMemorySource> sources = [];
  List<ChatMessage> messages = [
    ChatMessage(id: 'u', role: 'user', content: '我不吃香菜'),
  ];
  MemoryReprocessingOutcome outcome = MemoryReprocessingOutcome.empty;
  @override
  Future<MemoryCenterSnapshot> load({DateTime? now}) async =>
      MemoryCenterSnapshot(
        events: [],
        userMemories: [
          UserMemory(
            id: 'm',
            characterId: 'c',
            key: '忌口',
            value: '不吃香菜',
            sourceMessageIds: ['u'],
          ),
        ],
        summary: const MemorySummary(characterId: 'c'),
        characterUserProfile: const CharacterUserProfile(characterId: 'c'),
        settings: CharacterSettings.genericDefaults(),
        legacy: [],
      );
  @override
  Future<List<ResolvedMemorySource>> resolveSources(List<String> ids) async {
    sourceReads++;
    requested = ids;
    return sources;
  }

  @override
  Future<List<ChatMessage>> loadReprocessingMessages() async => messages;
  @override
  Future<MemoryReprocessingOutcome> reprocessMessages(List<String> ids) async {
    calls++;
    requested = ids;
    return outcome;
  }
}

void main() {
  testWidgets('User source lookup is lazy and accessible from Memory Center', (
    tester,
  ) async {
    final controller = _Controller()
      ..sources = [
        ResolvedMemorySource(
          messageId: 'u',
          createdAt: DateTime(2026, 9, 4),
          type: MessageType.text,
          preview: '用户原始短句',
        ),
      ];
    await tester.pumpWidget(
      MaterialApp(
        home: MemoryPage(characterId: 'c', controller: controller),
      ),
    );
    await tester.pumpAndSettle();
    expect(controller.sourceReads, 0);
    final tile = find.ancestor(
      of: find.text('忌口'),
      matching: find.byType(ListTile),
    );
    await tester.tap(
      find.descendant(of: tile, matching: find.byType(PopupMenuButton<String>)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('查看来源'));
    await tester.pumpAndSettle();
    expect(controller.sourceReads, 1);
    expect(controller.requested, ['u']);
    expect(find.text('用户原始短句'), findsOneWidget);
  });
  for (final legacy in [false, true]) {
    testWidgets(
      'no chat source displays ${legacy ? 'legacy' : 'manual'} explanation',
      (tester) async {
        final controller = _Controller();
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => showMemorySources(
                    context,
                    controller,
                    [],
                    legacySourceId: legacy ? 'not-a-chat-id' : null,
                  ),
                  child: const Text('来源'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('来源'));
        await tester.pumpAndSettle();
        expect(
          find.text(legacy ? '来源：旧版记忆（没有聊天来源）' : '这条记忆没有聊天来源'),
          findsOneWidget,
        );
        expect(controller.requested, isEmpty);
      },
    );
  }
  testWidgets(
    'missing original and missing image show safe separate fallback',
    (tester) async {
      final controller = _Controller()
        ..sources = [
          const ResolvedMemorySource(messageId: 'missing'),
          ResolvedMemorySource(
            messageId: 'pic',
            createdAt: DateTime(2026),
            type: MessageType.image,
            imageMissing: true,
            visionPreview: '一只猫',
          ),
        ];
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () =>
                    showMemorySources(context, controller, ['missing', 'pic']),
                child: const Text('来源'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('来源'));
      await tester.pumpAndSettle();
      expect(find.text('原始来源已不可用'), findsOneWidget);
      expect(find.text('原始图片已不可用'), findsOneWidget);
      expect(find.textContaining('AI 视觉描述（非用户自述）'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'management reprocessing requires selection and reports empty then permits retry',
    (tester) async {
      final controller = _Controller();
      await tester.pumpWidget(
        MaterialApp(home: MemoryReprocessingPage(controller: controller)),
      );
      await tester.pumpAndSettle();
      expect(controller.calls, 0);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, '确认整理选中的消息'),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.byKey(const ValueKey('reprocess-u')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认整理选中的消息'));
      await tester.pumpAndSettle();
      expect(controller.calls, 1);
      expect(controller.requested, ['u']);
      expect(find.text('这段聊天没有整理出新的记忆'), findsOneWidget);
      controller.outcome = MemoryReprocessingOutcome.failed;
      await tester.tap(find.text('确认整理选中的消息'));
      await tester.pumpAndSettle();
      expect(controller.calls, 2);
      expect(find.text('整理失败，请稍后主动重试'), findsOneWidget);
    },
  );
  testWidgets('oversized source disables confirmation instead of truncating', (
    tester,
  ) async {
    final controller = _Controller()
      ..messages = [
        ChatMessage(id: 'long', role: 'user', content: '文' * 12001),
      ];
    await tester.pumpWidget(
      MaterialApp(home: MemoryReprocessingPage(controller: controller)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('reprocess-long')));
    await tester.pumpAndSettle();
    expect(find.text('范围过大，请缩小范围'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '确认整理选中的消息'))
          .onPressed,
      isNull,
    );
    expect(controller.calls, 0);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/models/character_settings.dart';
import 'package:peijianche_app/models/character_user_profile.dart';
import 'package:peijianche_app/models/event_memory.dart';
import 'package:peijianche_app/models/memory_summary.dart';
import 'package:peijianche_app/models/user_memory.dart';
import 'package:peijianche_app/models/legacy_memory_view.dart';
import 'package:peijianche_app/pages/memory_page.dart';
import 'package:peijianche_app/services/memory_center_controller.dart';
import 'package:peijianche_app/services/memory_summary_generation_service.dart';
import 'package:peijianche_app/services/auto_memory_extraction_service.dart';

class _FakeController extends MemoryCenterController {
  _FakeController(this.snapshot) : super(characterId: 'role-a');
  MemoryCenterSnapshot snapshot;
  int loadCount = 0;
  int settingWrites = 0;
  int generatedWrites = 0;
  int retries = 0;
  @override
  Future<List<({String messageId, String content, String outcome})>>
  loadExplicitFailures() async => [
    (messageId: 'source', content: '你要记住我们的纪念日', outcome: 'empty'),
  ];
  @override
  Future<AutoMemoryExtractionOutcome> retryExplicit(String messageId) async {
    if (messageId != 'source') throw StateError('wrong source');
    retries++;
    return AutoMemoryExtractionOutcome.success;
  }

  @override
  Future<MemoryCenterSnapshot> load({DateTime? now}) async {
    loadCount++;
    return snapshot;
  }

  @override
  Future<void> setAutoMemoryEnabled(
    CharacterSettings current,
    bool enabled,
  ) async {
    settingWrites++;
    snapshot = MemoryCenterSnapshot(
      events: snapshot.events,
      userMemories: snapshot.userMemories,
      summary: snapshot.summary,
      characterUserProfile: snapshot.characterUserProfile,
      settings: current.copyWith(autoMemoryEnabled: enabled),
      legacy: snapshot.legacy,
    );
  }

  @override
  Future<void> saveGeneratedSummary(
    MemorySummary current,
    String text, {
    bool replaceUserEdit = false,
  }) async {
    generatedWrites++;
  }
}

class _FakeSummary implements MemorySummaryGenerationGateway {
  int calls = 0;
  @override
  Future<String> generate(MemorySummaryGenerationInput input) async {
    calls++;
    return '新的长期总结';
  }
}

MemoryCenterSnapshot _snapshot({MemorySummary? summary}) {
  final now = DateTime(2026, 1, 1);
  return MemoryCenterSnapshot(
    events: [
      EventMemory(
        id: 'a',
        characterId: 'role-a',
        content: '清晨一起散步',
        createdAt: now,
      ),
      EventMemory(
        id: 'f',
        characterId: 'role-a',
        content: '雨天一起喝咖啡',
        createdAt: now,
        status: EventMemoryStatus.fading,
      ),
      EventMemory(
        id: 'p',
        characterId: 'role-a',
        content: '看过一场电影',
        createdAt: now,
        status: EventMemoryStatus.pendingForget,
      ),
      EventMemory(
        id: 'x',
        characterId: 'role-a',
        content: '不应出现在主页',
        createdAt: now,
        status: EventMemoryStatus.forgotten,
      ),
    ],
    userMemories: [
      UserMemory(id: 'u', characterId: 'role-a', key: '喜欢的饮品', value: '拿铁'),
    ],
    summary: summary ?? const MemorySummary(characterId: 'role-a'),
    characterUserProfile: const CharacterUserProfile(
      characterId: 'role-a',
      userName: '小林',
    ),
    settings: CharacterSettings.defaults().copyWith(characterName: '裴简澈'),
    legacy: const [],
  );
}

void main() {
  testWidgets('management keeps legacy tools hidden when no old data exists', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MemoryPage(
          characterId: 'role-a',
          controller: _FakeController(_snapshot()),
          summaryGenerator: _FakeSummary(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('管理记忆'));
    await tester.pumpAndSettle();

    expect(find.text('记忆管理'), findsOneWidget);
    expect(find.text('重新整理聊天记录'), findsOneWidget);
    expect(find.text('用户记忆历史'), findsOneWidget);
    expect(find.text('未完成的保存请求'), findsOneWidget);
    expect(find.text('已遗忘的记忆'), findsOneWidget);
    expect(find.text('复制全部记忆'), findsOneWidget);
    expect(find.text('迁移旧版记忆'), findsNothing);
    expect(find.text('旧版记忆'), findsNothing);
    expect(find.text('旧版待审核'), findsNothing);
  });

  testWidgets('management reveals only applicable legacy operations', (
    tester,
  ) async {
    final base = _snapshot();
    final withLegacy = MemoryCenterSnapshot(
      events: base.events,
      userMemories: base.userMemories,
      summary: base.summary,
      characterUserProfile: base.characterUserProfile,
      settings: base.settings,
      legacyPendingCount: 1,
      legacy: [
        LegacyMemoryView(
          id: 'legacy-old',
          characterId: 'role-a',
          legacySourceId: 'old',
          kind: LegacyMemoryKind.user,
          content: '旧资料',
          category: '关于我',
          createdAt: DateTime(2025),
          isPinned: false,
          legacyArchived: false,
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: MemoryPage(
          characterId: 'role-a',
          controller: _FakeController(withLegacy),
          summaryGenerator: _FakeSummary(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('管理记忆'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('旧版待审核'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();

    expect(find.text('迁移旧版记忆'), findsOneWidget);
    expect(find.text('旧数据兼容'), findsOneWidget);
    expect(find.text('旧版记忆'), findsOneWidget);
    expect(find.text('旧版待审核'), findsOneWidget);
  });

  testWidgets(
    'confirmed labels and history management keep superseded out of main list',
    (tester) async {
      final base = _snapshot();
      final controller = _FakeController(
        MemoryCenterSnapshot(
          events: [],
          userMemories: [
            UserMemory(
              id: 'old',
              characterId: 'role-a',
              key: '饮品',
              value: '旧咖啡',
              status: UserMemoryStatus.superseded,
              supersededById: 'new',
              userConfirmed: true,
            ),
            UserMemory(
              id: 'new',
              characterId: 'role-a',
              key: '饮品',
              value: '现在茶',
              userConfirmed: true,
            ),
          ],
          summary: base.summary,
          characterUserProfile: base.characterUserProfile,
          settings: base.settings,
          legacy: [],
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: MemoryPage(
            characterId: 'role-a',
            controller: controller,
            summaryGenerator: _FakeSummary(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('已确认'), findsOneWidget);
      expect(find.textContaining('旧咖啡'), findsNothing);
      await tester.tap(find.byTooltip('管理记忆'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('用户记忆历史'));
      await tester.pumpAndSettle();
      expect(find.text('饮品：旧咖啡'), findsOneWidget);
      expect(find.textContaining('已被新事实替代'), findsOneWidget);
    },
  );
  testWidgets('failed explicit request can retry its source from management', (
    tester,
  ) async {
    final controller = _FakeController(_snapshot());
    await tester.pumpWidget(
      MaterialApp(
        home: MemoryPage(
          characterId: 'role-a',
          controller: controller,
          summaryGenerator: _FakeSummary(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('管理记忆'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('未完成的保存请求'));
    await tester.pumpAndSettle();
    expect(find.text('你要记住我们的纪念日'), findsOneWidget);
    await tester.tap(find.text('重新整理'));
    await tester.pumpAndSettle();
    expect(controller.retries, 1);
    expect(find.text('已形成受保护记忆'), findsOneWidget);
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, '重新整理'))
          .onPressed,
      isNull,
    );
  });
  testWidgets(
    'Memory center displays three layers and hides forgotten technical state',
    (tester) async {
      final controller = _FakeController(_snapshot());
      await tester.pumpWidget(
        MaterialApp(
          home: MemoryPage(
            characterId: 'role-a',
            controller: controller,
            summaryGenerator: _FakeSummary(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Ta 心中的我'), findsOneWidget);
      expect(find.text('我告诉 Ta 的我'), findsOneWidget);
      expect(find.text('Ta 逐渐了解到'), findsOneWidget);
      expect(find.text('喜欢的饮品'), findsOneWidget);
      expect(find.text('还没有整理长期记忆'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const Key('fading-divider')),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('以下记忆逐渐模糊'), findsOneWidget);
      expect(find.text('不应出现在主页'), findsNothing);
      expect(find.text('pendingForget'), findsNothing);
      expect(controller.loadCount, 1);
    },
  );

  testWidgets('manual summary update previews once and cancel does not save', (
    tester,
  ) async {
    final controller = _FakeController(
      _snapshot(
        summary: const MemorySummary(
          characterId: 'role-a',
          generatedText: '旧总结',
          userEditedText: '我的版本',
        ),
      ),
    );
    final gateway = _FakeSummary();
    await tester.pumpWidget(
      MaterialApp(
        home: MemoryPage(
          characterId: 'role-a',
          controller: controller,
          summaryGenerator: gateway,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('update-memory-summary')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.drag(find.byType(ListView).first, const Offset(0, 120));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('update-memory-summary')));
    await tester.pumpAndSettle();
    expect(gateway.calls, 1);
    expect(find.text('新的记忆汇总'), findsOneWidget);
    expect(find.textContaining('不会覆盖'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(controller.generatedWrites, 0);
  });
}

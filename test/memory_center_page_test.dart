import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/models/character_settings.dart';
import 'package:peijianche_app/models/character_user_profile.dart';
import 'package:peijianche_app/models/event_memory.dart';
import 'package:peijianche_app/models/memory_summary.dart';
import 'package:peijianche_app/models/user_memory.dart';
import 'package:peijianche_app/pages/memory_page.dart';
import 'package:peijianche_app/services/memory_center_controller.dart';
import 'package:peijianche_app/services/memory_summary_generation_service.dart';

class _FakeController extends MemoryCenterController {
  _FakeController(this.snapshot) : super(characterId: 'role-a');
  MemoryCenterSnapshot snapshot;
  int loadCount = 0;
  int settingWrites = 0;
  int generatedWrites = 0;

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

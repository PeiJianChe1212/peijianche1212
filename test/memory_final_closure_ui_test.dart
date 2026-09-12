import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/models/character_settings.dart';
import 'package:peijianche_app/models/character_user_profile.dart';
import 'package:peijianche_app/models/event_memory.dart';
import 'package:peijianche_app/models/memory_summary.dart';
import 'package:peijianche_app/models/user_memory.dart';
import 'package:peijianche_app/pages/memory_page.dart';
import 'package:peijianche_app/services/memory_center_controller.dart';

void main() {
  testWidgets('fading and pending events render documented opacity tiers', (
    tester,
  ) async {
    final controller = _UiController();
    await tester.pumpWidget(
      MaterialApp(
        home: MemoryPage(characterId: 'role', controller: controller),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('雨天一起喝咖啡'),
      400,
      scrollable: find.byType(Scrollable).first,
    );

    final fadingOpacity = tester.widget<Opacity>(
      find.ancestor(of: find.text('雨天一起喝咖啡'), matching: find.byType(Opacity)),
    );
    final pendingOpacity = tester.widget<Opacity>(
      find.ancestor(of: find.text('正在遗忘'), matching: find.byType(Opacity)),
    );
    expect(fadingOpacity.opacity, .78);
    expect(pendingOpacity.opacity, .62);
    expect(
      find.ancestor(of: find.text('今天一起散步'), matching: find.byType(Opacity)),
      findsNothing,
    );
    expect(find.byKey(const Key('fading-divider')), findsOneWidget);
    expect(find.text('以下记忆逐渐模糊'), findsOneWidget);
    expect(find.text('正在遗忘'), findsOneWidget);
    expect(find.text('永远隐藏'), findsNothing);
  });

  testWidgets('event menu can pin a memory and forgotten page restores it', (
    tester,
  ) async {
    final controller = _UiController();
    await tester.pumpWidget(
      MaterialApp(
        home: MemoryPage(characterId: 'role', controller: controller),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('今天一起散步'),
      400,
      scrollable: find.byType(Scrollable).first,
    );

    final eventTile = find.ancestor(
      of: find.text('今天一起散步'),
      matching: find.byType(ListTile),
    );
    await tester.tap(
      find.descendant(
        of: eventTile,
        matching: find.byType(PopupMenuButton<String>),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('不要忘记'));
    await tester.pumpAndSettle();
    expect(controller.pinCalls, 1);
    expect(find.byIcon(Icons.push_pin), findsWidgets);
    final pinnedTile = find.ancestor(
      of: find.text('今天一起散步'),
      matching: find.byType(ListTile),
    );
    await tester.tap(
      find.descendant(
        of: pinnedTile,
        matching: find.byType(PopupMenuButton<String>),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('取消固定'), findsOneWidget);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    await tester.pumpWidget(
      MaterialApp(home: ForgottenMemoriesPage(controller: controller)),
    );
    await tester.pumpAndSettle();
    expect(find.text('永远隐藏'), findsOneWidget);
    await tester.tap(find.byType(PopupMenuButton<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('恢复记忆'));
    await tester.pumpAndSettle();
    expect(controller.restoreCalls, 1);
    expect(find.text('永远隐藏'), findsNothing);
    await tester.pumpWidget(
      MaterialApp(
        home: MemoryPage(characterId: 'role', controller: controller),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('永远隐藏'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('永远隐藏'), findsOneWidget);
  });

  testWidgets('memory operation errors never expose internal details', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MemoryPage(
          characterId: 'role',
          controller: _FailingUiController(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('内部错误测试'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    final userTile = find.ancestor(
      of: find.text('内部错误测试'),
      matching: find.byType(ListTile),
    );
    await tester.tap(
      find.descendant(
        of: userTile,
        matching: find.byType(PopupMenuButton<String>),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('编辑').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('操作未完成，原始记忆仍保留，请检查存储后重试。'), findsOneWidget);
    expect(find.textContaining('INTERNAL_SENTINEL_9F2A'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

class _UiController extends MemoryCenterController {
  _UiController() : super(characterId: 'role');

  int pinCalls = 0;
  int restoreCalls = 0;
  bool activePinned = false;
  bool forgottenRestored = false;
  final now = DateTime.utc(2026, 1, 1);

  EventMemory get active => EventMemory(
    id: 'active',
    characterId: 'role',
    content: '今天一起散步',
    createdAt: now,
    isPinned: activePinned,
  );

  EventMemory get fading => EventMemory(
    id: 'fading',
    characterId: 'role',
    content: '雨天一起喝咖啡',
    createdAt: now,
    status: EventMemoryStatus.fading,
  );

  EventMemory get pending => EventMemory(
    id: 'pending',
    characterId: 'role',
    content: '正在遗忘',
    createdAt: now,
    status: EventMemoryStatus.pendingForget,
  );

  EventMemory get forgotten => EventMemory(
    id: 'forgotten',
    characterId: 'role',
    content: '永远隐藏',
    createdAt: now,
    status: forgottenRestored
        ? EventMemoryStatus.active
        : EventMemoryStatus.forgotten,
  );

  @override
  Future<MemoryCenterSnapshot> load({DateTime? now}) async =>
      MemoryCenterSnapshot(
        events: [active, fading, pending, forgotten],
        userMemories: const [],
        summary: const MemorySummary(characterId: 'role'),
        characterUserProfile: const CharacterUserProfile(characterId: 'role'),
        settings: CharacterSettings.genericDefaults().copyWith(
          characterName: '测试角色',
        ),
        legacy: const [],
      );

  @override
  Future<void> setEventPinned(EventMemory item, bool pinned) async {
    pinCalls++;
    activePinned = pinned;
  }

  @override
  Future<void> restoreEvent(EventMemory item) async {
    restoreCalls++;
    forgottenRestored = true;
  }
}

class _FailingUiController extends _UiController {
  @override
  Future<MemoryCenterSnapshot> load({DateTime? now}) async {
    final base = await super.load(now: now);
    return MemoryCenterSnapshot(
      events: base.events,
      userMemories: [
        UserMemory(
          id: 'internal',
          characterId: 'role',
          key: '内部错误测试',
          value: '纯虚构夹具',
        ),
      ],
      summary: base.summary,
      characterUserProfile: base.characterUserProfile,
      settings: base.settings,
      legacy: base.legacy,
    );
  }

  @override
  Future<void> updateUserMemory(
    UserMemory item, {
    required String key,
    required String value,
  }) async => throw StateError('INTERNAL_SENTINEL_9F2A');
}

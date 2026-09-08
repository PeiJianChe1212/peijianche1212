import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/models/character_settings.dart';
import 'package:peijianche_app/models/chat_message.dart';
import 'package:peijianche_app/models/character_user_profile.dart';
import 'package:peijianche_app/models/event_memory.dart';
import 'package:peijianche_app/models/memory_extraction_result.dart';
import 'package:peijianche_app/models/memory_source_type.dart';
import 'package:peijianche_app/models/memory_summary.dart';
import 'package:peijianche_app/models/user_memory.dart';
import 'package:peijianche_app/services/auto_memory_extraction_service.dart';
import 'package:peijianche_app/services/memory2_storage_service.dart';
import 'package:peijianche_app/services/memory_center_controller.dart';
import 'package:peijianche_app/services/memory_extraction_state_service.dart';
import 'package:peijianche_app/services/memory2_extractor.dart';
import 'package:peijianche_app/pages/memory_page.dart';
import 'package:flutter/material.dart';

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('memory9_safety_');
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  Future<File> fileFor(String id, String name) async {
    final file = File('${directory.path}/$id/$name');
    await file.parent.create(recursive: true);
    return file;
  }

  Memory2StorageService storage(String id) =>
      Memory2StorageService(characterId: id, fileProvider: fileFor);

  EventMemory event(String id, String text) => EventMemory(
    id: id,
    characterId: 'role',
    content: text,
    createdAt: DateTime.utc(2026, 1, 1),
    updatedAt: DateTime.utc(2026, 1, 1),
    sourceType: MemorySourceType.manual,
  );

  UserMemory user(String id, String value) => UserMemory(
    id: id,
    characterId: 'role',
    key: '偏好',
    value: value,
    createdAt: DateTime.utc(2026, 1, 1),
    updatedAt: DateTime.utc(2026, 1, 1),
  );

  test('corrupt Event/User files are never overwritten by save', () async {
    final s = storage('role');
    final eventFile = await fileFor(
      'role',
      Memory2StorageService.eventFileName,
    );
    final userFile = await fileFor('role', Memory2StorageService.userFileName);
    await eventFile.writeAsString('{broken event');
    await userFile.writeAsString('{broken user');

    await expectLater(
      s.saveEventMemories([event('e1', 'new')]),
      throwsFormatException,
    );
    await expectLater(
      s.saveUserMemories([user('u1', 'new')]),
      throwsFormatException,
    );
    expect(await eventFile.readAsString(), '{broken event');
    expect(await userFile.readAsString(), '{broken user');
  });

  test('corrupt Summary file is never overwritten by save', () async {
    final s = storage('role');
    final summaryFile = await fileFor(
      'role',
      Memory2StorageService.summaryFileName,
    );
    await summaryFile.writeAsString('{broken summary');
    expect(
      () => s.saveMemorySummary(
        const MemorySummary(characterId: 'role', generatedText: 'new'),
      ),
      throwsFormatException,
    );
    expect(await summaryFile.readAsString(), '{broken summary');
  });

  test(
    'corrupt extraction state prevents gateway, cursor advancement, and writes',
    () async {
      final stateFile = File(
        '${directory.path}/role/memory_extraction_state.json',
      );
      await stateFile.parent.create(recursive: true);
      await stateFile.writeAsString('{broken state');
      var calls = 0;
      final service = AutoMemoryExtractionService(
        characterId: 'role',
        gateway: _CountingGateway(() => calls++),
        storage: storage('role'),
        stateService: MemoryExtractionStateService(
          characterId: 'role',
          fileProvider: (_) async => stateFile,
        ),
        settingsLoader: () async => CharacterSettings.genericDefaults(),
        messagesLoader: () async => List.generate(
          8,
          (i) => ChatMessage(
            id: 'm$i',
            role: i.isEven ? 'user' : 'assistant',
            content: 'message $i',
            createdAt: DateTime.utc(2026, 1, 1, 0, i),
          ),
        ),
        userNameLoader: () async => 'user',
        legacyLoader: () async => const [],
      );

      expect(await service.maybeExtract(), AutoMemoryExtractionOutcome.failed);
      expect(calls, 0);
      expect(await stateFile.readAsString(), '{broken state');
    },
  );

  test('stale User pin request reads the latest edited value', () async {
    final s = storage('role');
    final controller = MemoryCenterController(characterId: 'role', storage: s);
    final original = user('u1', '旧值');
    await s.saveUserMemories([original]);
    await controller.updateUserMemory(original, key: '偏好', value: '最新值');
    await controller.setUserMemoryPinned(original, true);

    final versions = await s.loadUserMemories();
    final saved = versions.singleWhere(
      (m) => m.status == UserMemoryStatus.active,
    );
    expect(saved.value, '最新值');
    expect(saved.isPinned, isTrue);
    expect(versions.first.value, '旧值');
    expect(versions.first.status, UserMemoryStatus.superseded);
    expect(versions.first.isPinned, original.isPinned);
  });

  test('concurrent summary operations preserve the latest user edit', () async {
    final s = storage('role');
    final controller = MemoryCenterController(characterId: 'role', storage: s);
    final initial = MemorySummary(
      characterId: 'role',
      generatedText: '旧总结',
      sourceRevision: 1,
    );
    await s.saveMemorySummary(initial);
    await Future.wait([
      controller.saveGeneratedSummary(initial, '新生成'),
      controller.saveUserEditedSummary(initial, '用户编辑'),
    ]);
    final saved = await s.loadMemorySummaryStrict();
    expect(saved.effectiveText, '用户编辑');
    expect(saved.userEditedText, '用户编辑');
  });

  test('explicit generated replacement rejects a stale user edit', () async {
    final s = storage('role');
    final controller = MemoryCenterController(characterId: 'role', storage: s);
    final snapshot = MemorySummary(
      characterId: 'role',
      generatedText: '旧',
      userEditedText: '旧编辑',
      sourceRevision: 1,
    );
    await s.saveMemorySummary(snapshot);
    await controller.saveUserEditedSummary(snapshot, '更新编辑');
    await expectLater(
      controller.saveGeneratedSummary(snapshot, '覆盖', replaceUserEdit: true),
      throwsStateError,
    );
    expect((await s.loadMemorySummaryStrict()).effectiveText, '更新编辑');
  });

  test(
    'deleting a UserMemory does not resurrect it from a stale object',
    () async {
      final s = storage('role');
      final controller = MemoryCenterController(
        characterId: 'role',
        storage: s,
      );
      final item = user('u1', '待删除');
      await s.saveUserMemories([item]);
      await controller.deleteUserMemory(item);
      await controller.setUserMemoryPinned(item, true);
      expect(await s.loadUserMemories(), isEmpty);
    },
  );

  testWidgets('MemoryPage reports save failure without changing the view', (
    tester,
  ) async {
    final controller = _FailingSummaryController(storage('role'));
    await tester.pumpWidget(
      MaterialApp(
        home: MemoryPage(characterId: 'role', controller: controller),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('编辑'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('操作未完成，原始记忆仍保留，请检查存储后重试。'), findsOneWidget);
    expect(find.text('原始总结'), findsOneWidget);
    expect(controller.saveCalls, 1);
  });
}

class _FailingSummaryController extends MemoryCenterController {
  _FailingSummaryController(Memory2StorageService storage)
    : super(characterId: 'role', storage: storage);

  int saveCalls = 0;
  @override
  Future<MemoryCenterSnapshot> load({DateTime? now}) async =>
      MemoryCenterSnapshot(
        events: const [],
        userMemories: const [],
        summary: const MemorySummary(
          characterId: 'role',
          generatedText: '原始总结',
        ),
        characterUserProfile: const CharacterUserProfile(characterId: 'role'),
        settings: CharacterSettings.genericDefaults().copyWith(
          characterName: '测试角色',
        ),
        legacy: const [],
      );

  @override
  Future<void> saveUserEditedSummary(MemorySummary current, String text) async {
    saveCalls++;
    throw StateError('simulated save failure');
  }
}

class _CountingGateway implements Memory2ExtractionGateway {
  _CountingGateway(this.onCall);
  final void Function() onCall;

  @override
  Future<MemoryExtractionResult> extract(
    Memory2ExtractionRequest request,
  ) async {
    onCall();
    return const MemoryExtractionResult();
  }
}

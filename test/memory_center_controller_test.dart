import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/models/character_settings.dart';
import 'package:peijianche_app/models/character_user_profile.dart';
import 'package:peijianche_app/models/event_memory.dart';
import 'package:peijianche_app/models/memory_summary.dart';
import 'package:peijianche_app/models/user_memory.dart';
import 'package:peijianche_app/services/character_settings_storage_service.dart';
import 'package:peijianche_app/services/character_user_profile_storage_service.dart';
import 'package:peijianche_app/services/event_memory_lifecycle_service.dart';
import 'package:peijianche_app/services/legacy_memory_adapter.dart';
import 'package:peijianche_app/services/memory2_storage_service.dart';
import 'package:peijianche_app/services/memory_center_controller.dart';

class _FakeSettingsStorage extends CharacterSettingsStorageService {
  _FakeSettingsStorage(this.value);

  CharacterSettings value;
  @override
  Future<CharacterSettings> loadSettings() async => value;

  @override
  Future<void> saveSettings(CharacterSettings settings) async =>
      value = settings;
}

class _FakeProfileStorage extends CharacterUserProfileStorageService {
  _FakeProfileStorage(this.value) : super(characterId: 'test-character');

  CharacterUserProfile value;
  @override
  Future<CharacterUserProfile> load() async => value;
}

void main() {
  late Directory directory;
  late Memory2StorageService storage;
  late MemoryCenterController controller;
  final settings = CharacterSettings.genericDefaults();

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('peilink_memory_center_');
    storage = Memory2StorageService(
      characterId: 'test-character',
      fileProvider: (_, name) async => File('${directory.path}/$name'),
    );
    controller = MemoryCenterController(
      characterId: 'test-character',
      storage: storage,
      lifecycle: EventMemoryLifecycleService(
        characterId: 'test-character',
        storage: storage,
      ),
      profileStorage: _FakeProfileStorage(
        const CharacterUserProfile(characterId: 'test-character'),
      ),
      settingsStorage: _FakeSettingsStorage(settings),
      legacyAdapter: LegacyMemoryAdapter(
        characterId: 'test-character',
        loader: () async => const [],
      ),
    );
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test(
    'manual event add writes Memory2 and pin/unpin follows lifecycle',
    () async {
      await controller.addEvent('  一起看电影  ', isPinned: true);
      var events = await storage.loadEventMemories();
      expect(events, hasLength(1));
      expect(events.single.content, '一起看电影');
      expect(events.single.sourceType.name, 'manual');
      expect(events.single.isPinned, isTrue);
      expect(events.single.status, EventMemoryStatus.active);

      await controller.setEventPinned(events.single, false);
      events = await storage.loadEventMemories();
      expect(events.single.isPinned, isFalse);
      expect(events.single.status, EventMemoryStatus.active);
    },
  );

  test('restore and delete event operate on Memory2 storage', () async {
    final old = EventMemory(
      id: 'old',
      characterId: 'test-character',
      content: '旧经历',
      status: EventMemoryStatus.forgotten,
    );
    await storage.saveEventMemories([old]);
    await controller.restoreEvent(old);
    expect(
      (await storage.loadEventMemories()).single.status,
      EventMemoryStatus.active,
    );
    await controller.deleteEvent(old);
    expect(await storage.loadEventMemories(), isEmpty);
  });

  test('user add and edit mark userConfirmed, delete removes it', () async {
    await controller.addUserMemory('喜欢', '拿铁');
    var users = await storage.loadUserMemories();
    expect(users.single.displayText, '喜欢：拿铁');
    expect(users.single.userConfirmed, isTrue);
    await controller.updateUserMemory(users.single, key: '偏好饮品', value: '茶');
    users = await storage.loadUserMemories();
    expect(users.last.displayText, '偏好饮品：茶');
    expect(users.last.userConfirmed, isTrue);
    expect(users.first.status, UserMemoryStatus.superseded);
    expect(users.first.supersededById, users.last.id);
    await controller.deleteUserMemory(users.last);
    expect(
      (await storage.loadUserMemories()).single.status,
      UserMemoryStatus.superseded,
    );
  });

  test(
    'summary editing, fallback and generated replacement preserve user edit',
    () async {
      var current = const MemorySummary(
        characterId: 'test-character',
        generatedText: '原生成版',
        userEditedText: '我的版本',
      );
      await storage.saveMemorySummary(current);
      await controller.saveUserEditedSummary(current, '');
      current = await storage.loadMemorySummary();
      expect(current.effectiveText, '原生成版');

      await controller.saveGeneratedSummary(current, '新生成版');
      current = await storage.loadMemorySummary();
      expect(current.generatedText, '新生成版');
      expect(current.userEditedText, isEmpty);

      await controller.saveUserEditedSummary(current, '手动版');
      current = await storage.loadMemorySummary();
      await controller.saveGeneratedSummary(current, '再次生成');
      current = await storage.loadMemorySummary();
      expect(current.effectiveText, '手动版');
      await controller.saveGeneratedSummary(
        current,
        '替换版',
        replaceUserEdit: true,
      );
      current = await storage.loadMemorySummary();
      expect(current.effectiveText, '替换版');
      expect(current.userEditedText, isEmpty);
    },
  );

  test(
    'copy text is user-readable and excludes internal fields and forgotten',
    () {
      final snapshot = MemoryCenterSnapshot(
        events: [
          EventMemory(
            id: 'secret-event-id',
            characterId: 'test-character',
            content: '仍记得的事',
            status: EventMemoryStatus.active,
            recallCount: 8,
          ),
          EventMemory(
            id: 'forgotten-id',
            characterId: 'test-character',
            content: '已忘记的事',
            status: EventMemoryStatus.forgotten,
          ),
        ],
        userMemories: [
          UserMemory(
            id: 'secret-user-id',
            characterId: 'test-character',
            key: '爱好',
            value: '阅读',
          ),
        ],
        summary: const MemorySummary(
          characterId: 'test-character',
          generatedText: '长期总结',
        ),
        characterUserProfile: const CharacterUserProfile(
          characterId: 'test-character',
          userName: '念念',
        ),
        settings: settings,
        legacy: const [],
      );
      final text = controller.buildCopyText(snapshot);
      expect(text, contains('[Ta 心中的我]'));
      expect(text, contains('[记忆汇总]'));
      expect(text, contains('仍记得的事'));
      expect(text, isNot(contains('已忘记的事')));
      for (final internal in [
        'secret-event-id',
        'secret-user-id',
        'status',
        'recallCount',
      ]) {
        expect(text, isNot(contains(internal)));
      }
    },
  );

  test('auto memory setting persists through the settings boundary', () async {
    final fake = _FakeSettingsStorage(settings);
    final local = MemoryCenterController(
      characterId: 'test-character',
      storage: storage,
      lifecycle: EventMemoryLifecycleService(
        characterId: 'test-character',
        storage: storage,
      ),
      profileStorage: _FakeProfileStorage(
        const CharacterUserProfile(characterId: 'test-character'),
      ),
      settingsStorage: fake,
      legacyAdapter: LegacyMemoryAdapter(
        characterId: 'test-character',
        loader: () async => const [],
      ),
    );
    await local.setAutoMemoryEnabled(settings, false);
    expect(fake.value.autoMemoryEnabled, isFalse);
  });

  test(
    'load refreshes without creating recall and tolerates legacy empty view',
    () async {
      final event = EventMemory(
        id: 'stable',
        characterId: 'test-character',
        content: '稳定经历',
        recallCount: 2,
      );
      await storage.saveEventMemories([event]);
      final before = await storage.loadEventMemories();
      final snapshot = await controller.load(now: DateTime.now());
      final after = await storage.loadEventMemories();
      expect(snapshot.events, isNotEmpty);
      expect(after.single.recallCount, before.single.recallCount);
      expect(snapshot.legacy, isEmpty);
    },
  );
}

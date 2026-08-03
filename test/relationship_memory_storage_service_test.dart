import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/models/relationship_memory.dart';
import 'package:peijianche_app/services/relationship_memory_storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory documentsDirectory;

  setUp(() async {
    documentsDirectory = await Directory.systemTemp.createTemp(
      'relationship_memory_storage_test_',
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

  test('saves the first relationship memory when storage is empty', () async {
    final storage = RelationshipMemoryStorageService();
    final memory = _memory('a', 'b', 'first');

    await storage.save(memory);

    expect(await storage.loadAll(), [sameMemoryAs(memory)]);
  });

  test('appends a new relationship memory without replacing existing data',
      () async {
    final storage = RelationshipMemoryStorageService();
    final first = _memory('a', 'b', 'first');
    final second = _memory('a', 'c', 'second');

    await storage.save(first);
    await storage.save(second);

    final loaded = await storage.loadAll();
    expect(loaded.map((item) => item.id), [first.id, second.id]);
  });
}

RelationshipMemory _memory(String firstId, String secondId, String summary) {
  return RelationshipMemory(
    id: RelationshipMemory.buildId(firstId, secondId),
    characterIdA: firstId,
    characterIdB: secondId,
    summary: summary,
    recentMemories: const [],
    sharedPatterns: const [],
    generatedFromExperienceCount: 1,
    updatedAt: DateTime.utc(2026, 8, 1),
  );
}

Matcher sameMemoryAs(RelationshipMemory expected) => predicate(
      (value) =>
          value is RelationshipMemory &&
          value.id == expected.id &&
          value.summary == expected.summary,
      'matches relationship memory ${expected.id}',
    );

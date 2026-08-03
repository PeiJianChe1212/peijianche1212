import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/models/cooldown_state.dart';
import 'package:peijianche_app/services/relationship_cooldown_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory documentsDirectory;

  setUp(() async {
    documentsDirectory = await Directory.systemTemp.createTemp(
      'relationship_cooldown_test_',
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

  test('defaults to normal when no state has been saved', () async {
    final state = await _service('pei').loadState();

    expect(state.state, ChatRelationshipState.normal);
    expect(await _service('pei').isInCooldown(), isFalse);
  });

  test('enters cooldown with duration and optional reason', () async {
    final now = DateTime.utc(2026, 8, 3, 10);
    final state = await _service(
      'pei',
    ).enterCooldown(const Duration(hours: 2), reason: '需要独处', now: now);

    expect(state.state, ChatRelationshipState.cooldown);
    expect(state.startTime, now);
    expect(state.endTime, DateTime.utc(2026, 8, 3, 12));
    expect(state.reason, '需要独处');
    expect(
      await _service('pei').isInCooldown(now: DateTime.utc(2026, 8, 3, 11)),
      isTrue,
    );
  });

  test('saved cooldown is restored by a new service instance', () async {
    final now = DateTime.utc(2026, 8, 3, 10);
    await _service('pei').enterCooldown(const Duration(hours: 2), now: now);

    final restored = await _service('pei').loadState();

    expect(restored.state, ChatRelationshipState.cooldown);
    expect(restored.startTime, now);
    expect(restored.endTime, DateTime.utc(2026, 8, 3, 12));
  });

  test('clearCooldown restores and persists normal state', () async {
    final service = _service('pei');
    await service.enterCooldown(
      const Duration(hours: 2),
      now: DateTime.utc(2026, 8, 3, 10),
    );

    await service.clearCooldown();

    expect(
      (await _service('pei').loadState()).state,
      ChatRelationshipState.normal,
    );
    expect(await _service('pei').isInCooldown(), isFalse);
  });

  test('cooldown state is isolated for each character', () async {
    final now = DateTime.utc(2026, 8, 3, 10);
    await _service(
      'pei_jian_che',
    ).enterCooldown(const Duration(hours: 2), now: now);

    expect(
      await _service(
        'pei_jian_che',
      ).isInCooldown(now: DateTime.utc(2026, 8, 3, 11)),
      isTrue,
    );
    expect(
      await _service(
        'che_yun_qian',
      ).isInCooldown(now: DateTime.utc(2026, 8, 3, 11)),
      isFalse,
    );
  });

  test('legacy data without state field loads as normal', () async {
    final directory = Directory('${documentsDirectory.path}/characters/legacy');
    await directory.create(recursive: true);
    await File(
      '${directory.path}/relationship_cooldown.json',
    ).writeAsString(jsonEncode({'reason': '旧数据'}));

    final state = await _service('legacy').loadState();

    expect(state.state, ChatRelationshipState.normal);
    expect(state.startTime, isNull);
    expect(state.endTime, isNull);
    expect(state.reason, isNull);
  });

  test('expired cooldown is no longer active', () async {
    final service = _service('pei');
    await service.enterCooldown(
      const Duration(hours: 1),
      now: DateTime.utc(2026, 8, 3, 10),
    );

    expect(
      await service.isInCooldown(now: DateTime.utc(2026, 8, 3, 11)),
      isFalse,
    );
  });
}

RelationshipCooldownService _service(String characterId) {
  return RelationshipCooldownService(characterId: characterId);
}

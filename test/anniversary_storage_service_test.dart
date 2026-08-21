import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/models/anniversary_item.dart';
import 'package:peijianche_app/services/anniversary_storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory documents;

  AnniversaryItem item(
    String id, {
    bool pinned = false,
    String? characterId,
    AnniversaryRepeatType repeat = AnniversaryRepeatType.none,
    DateTime? date,
  }) => AnniversaryItem(
    id: id,
    title: '纪念日 $id',
    date: date ?? DateTime(2026, 1, 17),
    repeatType: repeat,
    relatedCharacterId: characterId,
    isPinned: pinned,
    createdAt: DateTime(2026, 1, 1),
  );

  setUp(() async {
    documents = await Directory.systemTemp.createTemp('anniversary_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'getApplicationDocumentsDirectory') {
            return documents.path;
          }
          return null;
        });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    if (await documents.exists()) await documents.delete(recursive: true);
  });

  test('全局文件支持新增、编辑、删除和角色 ID 兼容', () async {
    final storage = AnniversaryStorageService();
    await storage.upsert(item('one', characterId: 'deleted_character'));

    var loaded = await storage.loadAll();
    expect(loaded.single.relatedCharacterId, 'deleted_character');
    await storage.upsert(loaded.single.copyWith(title: '改名后'));
    expect((await storage.loadAll()).single.title, '改名后');

    await storage.delete('one');
    expect(await storage.loadAll(), isEmpty);
    expect(File('${documents.path}/anniversaries.json').existsSync(), isTrue);
  });

  test('置顶新项时自动取消原置顶', () async {
    final storage = AnniversaryStorageService();
    await storage.upsert(item('one', pinned: true));
    await storage.upsert(item('two', pinned: true));

    final loaded = await storage.loadAll();
    expect(loaded.where((value) => value.isPinned).map((value) => value.id), [
      'two',
    ]);
    expect((await storage.loadPinned())?.id, 'two');
  });

  test('日期计算区分过去、未来和每年重复', () {
    final now = DateTime(2026, 8, 22);
    expect(
      AnniversaryDayStatus.calculate(
        item('past', date: DateTime(2026, 8, 20)),
        now: now,
      ).displayText,
      '已经 2 天',
    );
    expect(
      AnniversaryDayStatus.calculate(
        item('future', date: DateTime(2026, 8, 25)),
        now: now,
      ).displayText,
      '还有 3 天',
    );
    expect(
      AnniversaryDayStatus.calculate(
        item(
          'yearly',
          repeat: AnniversaryRepeatType.yearly,
          date: DateTime(2020, 8, 20),
        ),
        now: now,
      ).displayText,
      '还有 363 天',
    );
  });
}

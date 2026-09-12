import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/platform/storage/native_platform_storage.dart';
import 'package:peijianche_app/services/character_registry_service.dart';

void main() {
  late Directory root;
  late NativePlatformStorage storage;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('native_storage_race_');
    storage = NativePlatformStorage(root.path);
  });
  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  Future<void> expectNoTemporaryFiles() async {
    expect(
      (await storage.list(
        '',
        recursive: true,
      )).where((entry) => entry.key.endsWith('.tmp')),
      isEmpty,
    );
  }

  test('single writes create and replace the same logical target', () async {
    await storage.writeText('nested/value', '旧内容');
    expect(await storage.readText('nested/value'), '旧内容');
    await storage.replaceTextSafely('nested/value', '新内容');
    expect(await storage.readText('nested/value'), '新内容');
    await storage.writeBytes('nested/value', Uint8List.fromList([0, 255, 4]));
    expect(await storage.readBytes('nested/value'), [0, 255, 4]);
    await expectNoTemporaryFiles();
  });

  test(
    'two writers use separate sibling staging files and complete values',
    () async {
      final created = <String>{};
      final watch = root.watch().listen((event) {
        if (event is FileSystemCreateEvent && event.path.endsWith('.tmp')) {
          created.add(event.path);
        }
      });
      try {
        final a = 'A' * (1024 * 1024);
        final b = 'B' * (1024 * 1024);
        await Future.wait([
          storage.writeText('value', a),
          NativePlatformStorage(root.path).writeText('value', b),
        ]);
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(created, hasLength(2));
        for (final path in created) {
          expect(File(path).parent.path, root.path);
          expect(path, isNot('${root.path}${Platform.pathSeparator}value.tmp'));
        }
        expect(await storage.readText('value'), isIn([a, b]));
        await expectNoTemporaryFiles();
      } finally {
        await watch.cancel();
      }
    },
  );

  test(
    'readers see complete old or new values during concurrent replacement',
    () async {
      final values = [for (var i = 0; i < 12; i++) '$i' * 100000];
      await storage.writeText('value', values.first);
      final writes = Future.wait([
        for (final value in values) storage.replaceTextSafely('value', value),
      ]);
      // Wait for both branches even if one fails, so teardown cannot delete
      // the directory out from under a still-running writer.
      await Future.wait([
        writes,
        () async {
          for (var i = 0; i < 20; i++) {
            expect(await storage.readText('value'), isIn(values));
          }
        }(),
      ]);
      expect(await storage.readText('value'), isIn(values));
      await expectNoTemporaryFiles();
    },
  );

  test(
    'rename failure cleans only its own staging file and preserves target',
    () async {
      final target = Directory('${root.path}/blocked');
      await target.create();
      final old = File('${target.path}/keep');
      await old.writeAsString('existing data');
      final foreign = File('${root.path}/blocked.other-writer.tmp');
      await foreign.writeAsString('other writer');
      await expectLater(
        storage.writeText('blocked', 'replacement'),
        throwsA(isA<FileSystemException>()),
      );
      expect(await old.readAsString(), 'existing data');
      expect(await foreign.readAsString(), 'other writer');
      expect(
        (await storage.list(
          '',
        )).where((e) => e.key.endsWith('.tmp')).map((e) => e.key),
        ['blocked.other-writer.tmp'],
      );
    },
  );

  test(
    'concurrent empty character registry initialization completes',
    () async {
      final results = await Future.wait([
        for (var i = 0; i < 20; i++)
          CharacterRegistryService(
            storage: NativePlatformStorage(root.path),
          ).loadAllCharacters(),
      ]);
      expect(results.every((characters) => characters.isEmpty), isTrue);
      expect(await storage.readText('character_registry.json'), '[]');
      await expectNoTemporaryFiles();
    },
  );

  test(
    'recursive delete removes scoped staging files without touching siblings',
    () async {
      await storage.writeText('group/value', 'value');
      await File('${root.path}/group/inflight.tmp').writeAsString('staging');
      await storage.writeText('other/value', 'keep');
      await storage.delete('group', recursive: true);
      expect(await Directory('${root.path}/group').exists(), isFalse);
      expect(await storage.readText('other/value'), 'keep');
      await expectNoTemporaryFiles();
    },
  );
}

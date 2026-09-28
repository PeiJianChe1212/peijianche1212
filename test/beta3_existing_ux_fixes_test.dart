import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/models/ai_character.dart';
import 'package:peijianche_app/platform/storage/native_platform_storage.dart';
import 'package:peijianche_app/services/avatar_image_cache.dart';
import 'package:peijianche_app/services/character_registry_service.dart';
import 'package:peijianche_app/widgets/group/group_avatar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('group avatar composition', () {
    test('four-person group includes user and three characters', () {
      final members = groupAvatarMembers(
        userAvatarPath: 'user.png',
        characters: [
          for (final id in ['a', 'b', 'c'])
            GroupAvatarMember(id: id, avatarPath: '$id.png', isUser: false),
        ],
      );
      expect(members, hasLength(4));
      expect(members.first.id, 'user');
      expect(members.where((item) => item.isUser), hasLength(1));
    });

    testWidgets('user without avatar uses safe fallback', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: GroupAvatar(
            members: groupAvatarMembers(
              userAvatarPath: '',
              characters: const [],
            ),
          ),
        ),
      );
      expect(find.byIcon(Icons.person_rounded), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('user with avatar uses the real file', (tester) async {
      final directory = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('group_avatar_'),
      ))!;
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/user.png');
      await tester.runAsync(
        () => file.writeAsBytes(
          base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
          ),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: GroupAvatar(
            members: groupAvatarMembers(
              userAvatarPath: file.path,
              characters: const [],
            ),
          ),
        ),
      );
      expect(find.byType(Image), findsOneWidget);
      expect(find.byIcon(Icons.person_rounded), findsNothing);
    });
  });

  testWidgets('same-path avatar cache is evicted without clearing other images', (
    tester,
  ) async {
    final directory = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('avatar_cache_'),
    ))!;
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/avatar.png');
    await tester.runAsync(
      () => file.writeAsBytes(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
        ),
      ),
    );
    await tester.pumpWidget(MaterialApp(home: Image.file(file)));
    await tester.pumpAndSettle();
    expect(AvatarImageCache.evictPath(file.path), isTrue);
    expect(AvatarImageCache.evictPath(''), isFalse);
  });

  test(
    'registry update preserves character ID and notifies listeners',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'registry_notify_',
      );
      addTearDown(() => directory.delete(recursive: true));
      final registry = CharacterRegistryService(
        storage: NativePlatformStorage(directory.path),
      );
      final original = AiCharacter(
        id: 'same-id',
        characterName: '角色',
        remark: '',
        avatarPath: 'old.png',
        createdAt: DateTime(2026),
      );
      await registry.saveAllCharacters([original]);
      var notifications = 0;
      void listener() => notifications++;
      CharacterRegistryService.changes.addListener(listener);
      addTearDown(
        () => CharacterRegistryService.changes.removeListener(listener),
      );

      await registry.updateCharacter(original.copyWith(avatarPath: 'new.png'));
      final updated = (await registry.loadAllCharactersStrict()).single;
      expect(updated.id, original.id);
      expect(updated.avatarPath, 'new.png');
      expect(notifications, 1);
    },
  );
}

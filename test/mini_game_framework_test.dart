import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/games/engines/game_engine.dart';
import 'package:peijianche_app/games/models/game_models.dart';
import 'package:peijianche_app/games/registry/mini_game_registry.dart';
import 'package:peijianche_app/games/services/game_participant_factory.dart';
import 'package:peijianche_app/games/storage/game_session_storage_service.dart';
import 'package:peijianche_app/models/ai_character.dart';
import 'package:peijianche_app/models/user_profile.dart';
import 'package:peijianche_app/pages/peilink/games/create_game_room_page.dart';
import 'package:peijianche_app/pages/peilink/games/game_room_page.dart';
import 'package:peijianche_app/pages/peilink/games/mini_game_lobby_page.dart';
import 'package:peijianche_app/platform/storage/native_platform_storage.dart';
import 'package:peijianche_app/services/peilink_theme_service.dart';
import 'package:peijianche_app/widgets/theme/peilink_theme_scope.dart';
import 'package:peijianche_app/widgets/theme/peilink_themed_avatar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final registry = MiniGameRegistry.instance;
  const userProfile = UserProfile(
    nickname: '测试用户',
    peiLinkId: 'user-1',
    avatarPath: '/user.png',
  );
  final character = AiCharacter(
    id: 'char-a',
    characterName: '角色 A',
    remark: '',
    avatarPath: '/char.png',
    createdAt: DateTime(2026),
  );
  final characterB = AiCharacter(
    id: 'char-b',
    characterName: '角色 B',
    remark: '',
    avatarPath: '/char-b.png',
    createdAt: DateTime(2026),
  );

  GameSession session({GameSessionStatus status = GameSessionStatus.ready}) {
    final now = DateTime(2026, 9, 20);
    return GameSession(
      sessionId: 'session-1',
      gameId: MiniGameRegistry.turtleSoupId,
      createdAt: now,
      updatedAt: now,
      status: status,
      host: const GameHost.character('char-a'),
      participants: [
        GameParticipantFactory.user(userProfile),
        GameParticipantFactory.character(character),
        GameParticipantFactory.character(character),
      ],
      gameState: const BaseGameState(
        phase: GamePhase(phaseId: 'setup', displayName: '准备', roundNumber: 0),
      ),
      messages: [
        GameMessage(
          id: 'public',
          sessionId: 'session-1',
          senderId: 'system',
          type: GameMessageType.system,
          content: '房间已建立',
        ),
        GameMessage(
          id: 'private',
          sessionId: 'session-1',
          senderId: 'system',
          type: GameMessageType.narration,
          content: '私密信息',
          visibility: GameMessageVisibility.privateToParticipant,
          visibleToParticipantId: 'character:char-a',
        ),
      ],
    );
  }

  test('registry contains stable definitions and unknown fallback', () {
    expect(registry.all.map((item) => item.id), [
      MiniGameRegistry.turtleSoupId,
      MiniGameRegistry.scriptMurderId,
      MiniGameRegistry.werewolfId,
    ]);
    expect(registry.definition('turtle_soup').displayName, '海龟汤');
    expect(registry.find('missing'), isNull);
    expect(registry.definition('missing').displayName, '未知游戏');
    expect(registry.definition('turtle_soup').isPlayable, isTrue);
    expect(registry.definition('turtle_soup').minPlayers, 1);
  });

  test('participants, host separation and duplicate prevention', () {
    final value = session();
    expect(value.participants, hasLength(2));
    expect(value.participants.first.type, GameParticipantType.user);
    expect(value.participants.last.characterId, 'char-a');
    expect(value.host.type, GameHostType.characterHost);
    expect(value.host.characterId, 'char-a');
    expect(const GameHost.system().type, GameHostType.systemHost);
  });

  test('state, phase, message visibility and action types are extensible', () {
    final value = session();
    expect((value.gameState as BaseGameState).phase.phaseId, 'setup');
    expect(value.messages.first.visibility, GameMessageVisibility.public);
    expect(
      value.messages.last.visibility,
      GameMessageVisibility.privateToParticipant,
    );
    expect(
      GameActionType.values,
      containsAll([
        GameActionType.textInput,
        GameActionType.ready,
        GameActionType.leave,
        GameActionType.pause,
        GameActionType.resume,
      ]),
    );
  });

  test('future game engine remains unavailable', () async {
    final result = await registry
        .definition('werewolf')
        .engineFactory()
        .startGame(session());
    expect(result.code, GameResultCode.engineUnavailable);
    expect(result.message, UnavailableGameEngine.message);
  });

  test('session serialization preserves schema, IDs and lifecycle', () {
    final original = session();
    final restored = GameSession.decode(original.encode());
    expect(restored.schemaVersion, GameSession.currentSchemaVersion);
    expect(restored.gameId, 'turtle_soup');
    expect(restored.participants.last.characterId, 'char-a');
    expect(restored.messages.last.visibleToParticipantId, 'character:char-a');
    expect(
      restored.copyWith(status: GameSessionStatus.playing).status,
      GameSessionStatus.playing,
    );
    expect(
      GameSessionStatus.values,
      containsAll([
        GameSessionStatus.draft,
        GameSessionStatus.ready,
        GameSessionStatus.playing,
        GameSessionStatus.paused,
        GameSessionStatus.finished,
        GameSessionStatus.abandoned,
      ]),
    );
  });

  test(
    'session storage restores and abandons inside isolated namespace',
    () async {
      final root = await Directory.systemTemp.createTemp('game_storage_');
      addTearDown(() => root.delete(recursive: true));
      final native = NativePlatformStorage(root.path);
      final storage = GameSessionStorageService(storage: native);
      expect((await storage.save(session())).isSuccess, isTrue);
      expect((await storage.load('session-1'))?.gameId, 'turtle_soup');
      expect(await storage.loadContinuable(), hasLength(1));
      expect((await storage.abandon('session-1')).isSuccess, isTrue);
      expect(await storage.loadContinuable(), isEmpty);
      final entries = await native.list('', recursive: true);
      expect(
        entries.where((item) => !item.isContainer).map((item) => item.key),
        ['games/sessions/index.json'],
      );
      expect(await native.exists('chat_history.json'), isFalse);
      expect(await native.exists('memory.json'), isFalse);
      expect(await native.exists('character_archive.json'), isFalse);
      expect(await native.exists('theme_selections.json'), isFalse);
    },
  );

  Future<void> pumpThemed(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      PeiLinkThemeScope(
        controller: PeiLinkThemeController(),
        child: MaterialApp(home: child),
      ),
    );
    for (var i = 0; i < 24; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('lobby shows empty state and three framework cards', (
    tester,
  ) async {
    final root = await tester.runAsync(
      () => Directory.systemTemp.createTemp('game_lobby_empty_'),
    );
    addTearDown(() => root!.delete(recursive: true));
    await pumpThemed(
      tester,
      MiniGameLobbyPage(
        storage: GameSessionStorageService(
          storage: NativePlatformStorage(root!.path),
        ),
        sessionsLoader: () async => [],
      ),
    );
    expect(
      find.byKey(const ValueKey('game-lobby-empty-state')),
      findsOneWidget,
    );
    expect(find.text('海龟汤'), findsOneWidget);
    expect(find.text('剧本杀'), findsOneWidget);
    expect(find.text('狼人杀'), findsOneWidget);
  });

  testWidgets('lobby restores a continuable session', (tester) async {
    final root = await tester.runAsync(
      () => Directory.systemTemp.createTemp('game_lobby_continue_'),
    );
    addTearDown(() => root!.delete(recursive: true));
    final storage = GameSessionStorageService(
      storage: NativePlatformStorage(root!.path),
    );
    await tester.runAsync(() => storage.save(session()));
    await pumpThemed(
      tester,
      MiniGameLobbyPage(
        storage: storage,
        sessionsLoader: () async => [session()],
      ),
    );
    expect(
      find.byKey(const ValueKey('game-session-session-1')),
      findsOneWidget,
    );
    expect(find.text('继续游戏'), findsOneWidget);
  });

  testWidgets(
    'turtle soup create room keeps user and exposes character participants',
    (tester) async {
      final root = await tester.runAsync(
        () => Directory.systemTemp.createTemp('game_create_'),
      );
      addTearDown(() => root!.delete(recursive: true));
      await pumpThemed(
        tester,
        CreateGameRoomPage(
          definition: registry.definition('turtle_soup'),
          storage: GameSessionStorageService(
            storage: NativePlatformStorage(root!.path),
          ),
          profileLoader: () async => userProfile,
          characterLoader: () async => [character],
        ),
      );
      expect(find.text('我 · 默认加入'), findsOneWidget);
      expect(find.byType(PeiLinkThemedAvatar), findsOneWidget);
      expect(
        find.byKey(const ValueKey('game-add-character-participant')),
        findsOneWidget,
      );
      final submit = tester.widget<FilledButton>(
        find.byKey(const ValueKey('create-game-room-submit')),
      );
      expect(submit.onPressed, isNotNull);
      expect(find.byKey(const ValueKey('game-character-char-a')), findsNothing);
      await tester.tap(
        find.byKey(const ValueKey('game-add-character-participant')),
      );
      await tester.pump();
      expect(
        find.byKey(const ValueKey('game-character-char-a')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('game-character-char-a')));
      await tester.pump();
      expect(find.byType(PeiLinkThemedAvatar), findsNWidgets(2));
      expect(
        find.byKey(const ValueKey('turtle-soup-puzzle-selector')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('game-host-character-selector')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'turtle soup persists multiple character participants without coupling host',
    (tester) async {
      final root = await tester.runAsync(
        () => Directory.systemTemp.createTemp('game_create_multi_'),
      );
      addTearDown(() => root!.delete(recursive: true));
      final storage = GameSessionStorageService(
        storage: NativePlatformStorage(root!.path),
      );
      await pumpThemed(
        tester,
        CreateGameRoomPage(
          definition: registry.definition('turtle_soup'),
          storage: storage,
          profileLoader: () async => userProfile,
          characterLoader: () async => [character, characterB],
        ),
      );
      await tester.tap(
        find.byKey(const ValueKey('game-add-character-participant')),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('game-character-char-a')));
      await tester.tap(find.byKey(const ValueKey('game-character-char-b')));
      await tester.pump();
      expect(find.byType(CheckboxListTile), findsNWidgets(3));

      await tester.tap(
        find.byKey(const ValueKey('game-host-character-selector')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('角色 A').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('game-character-char-a')));
      await tester.pump();
      final selectedB = tester.widget<CheckboxListTile>(
        find.descendant(
          of: find.byKey(const ValueKey('game-character-char-b')),
          matching: find.byType(CheckboxListTile),
        ),
      );
      expect(selectedB.value, isTrue);
      final createdSession = CreateGameRoomPage.buildSession(
        definition: registry.definition('turtle_soup'),
        profile: userProfile,
        characters: [character, characterB, characterB],
        selectedCharacterIds: {'char-b'},
        host: const GameHost.character('char-a'),
        now: DateTime(2026, 9, 20),
      );
      expect(createdSession.host.characterId, 'char-a');
      expect(
        createdSession.participants.map((item) => item.participantId),
        containsAll(['user', 'character:char-b']),
      );
      expect(
        createdSession.participants.where(
          (item) => item.participantId == 'character:char-b',
        ),
        hasLength(1),
      );
      expect(
        createdSession.participants.any(
          (item) => item.participantId == 'character:char-a',
        ),
        isFalse,
      );
    },
  );

  testWidgets('empty registry still exposes add-character empty state', (
    tester,
  ) async {
    final root = await tester.runAsync(
      () => Directory.systemTemp.createTemp('game_create_empty_chars_'),
    );
    addTearDown(() => root!.delete(recursive: true));
    await pumpThemed(
      tester,
      CreateGameRoomPage(
        definition: registry.definition('turtle_soup'),
        storage: GameSessionStorageService(
          storage: NativePlatformStorage(root!.path),
        ),
        profileLoader: () async => userProfile,
        characterLoader: () async => [],
      ),
    );
    expect(
      find.byKey(const ValueKey('game-add-character-participant')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey('game-add-character-participant')),
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey('game-character-participant-empty')),
      findsOneWidget,
    );
    expect(find.textContaining('还没有可加入的角色'), findsOneWidget);
  });

  testWidgets('room shell initializes playable turtle soup', (tester) async {
    final root = await tester.runAsync(
      () => Directory.systemTemp.createTemp('game_room_'),
    );
    addTearDown(() => root!.delete(recursive: true));
    await pumpThemed(
      tester,
      GameRoomPage(
        session: session(),
        storage: GameSessionStorageService(
          storage: NativePlatformStorage(root!.path),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('game-room-shell')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('turtle-soup-puzzle-card')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('game-room-start')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('turtle-soup-input')), findsOneWidget);
  });
}

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/games/models/game_models.dart';
import 'package:peijianche_app/games/participation/character_game_action.dart';
import 'package:peijianche_app/games/participation/character_participation_director.dart';
import 'package:peijianche_app/games/registry/mini_game_registry.dart';
import 'package:peijianche_app/games/services/game_room_draft_store.dart';
import 'package:peijianche_app/games/storage/game_session_storage_service.dart';
import 'package:peijianche_app/games/turtle_soup/turtle_soup_character_agent_view_builder.dart';
import 'package:peijianche_app/games/turtle_soup/turtle_soup_character_participation_adapter.dart';
import 'package:peijianche_app/games/turtle_soup/turtle_soup_engine.dart';
import 'package:peijianche_app/games/turtle_soup/turtle_soup_models.dart';
import 'package:peijianche_app/games/turtle_soup/turtle_soup_puzzle_registry.dart';
import 'package:peijianche_app/games/turtle_soup/turtle_soup_semantic_judge.dart';
import 'package:peijianche_app/pages/peilink/games/game_room_page.dart';
import 'package:peijianche_app/pages/peilink/games/game_room_presentation.dart';
import 'package:peijianche_app/platform/storage/native_platform_storage.dart';
import 'package:peijianche_app/platform/storage/platform_storage.dart';
import 'package:peijianche_app/services/peilink_theme_service.dart';
import 'package:peijianche_app/widgets/theme/peilink_theme_scope.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  MiniGameRegistry.instance;

  final alarm = TurtleSoupPuzzleRegistry.byId('silent_alarm');

  GameSession playingSession({
    required String sessionId,
    List<GameMessage> messages = const [],
    int questionCount = 0,
  }) {
    final state = TurtleSoupState(
      puzzleId: alarm.id,
      title: alarm.title,
      surface: alarm.surface,
      truth: alarm.truth,
      hints: alarm.hints,
      phase: TurtleSoupPhase.questioning,
      questionCount: questionCount,
    );
    return GameSession(
      sessionId: sessionId,
      gameId: MiniGameRegistry.turtleSoupId,
      createdAt: DateTime(2026, 9, 20),
      updatedAt: DateTime(2026, 9, 20),
      status: GameSessionStatus.playing,
      host: const GameHost.system(),
      participants: const [
        GameParticipant(
          participantId: 'user:1',
          type: GameParticipantType.user,
          displayName: '我',
        ),
      ],
      gameState: state,
      messages: messages,
    );
  }

  group('GameRoomDraftStore', () {
    late Directory root;
    late GameRoomDraftStore store;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('draft_store_');
      store = GameRoomDraftStore(storage: NativePlatformStorage(root.path));
    });

    test('save then load returns the same text', () async {
      await store.save('s1', '这个人是不是认识死者');
      expect(await store.load('s1'), '这个人是不是认识死者');
    });

    test('clear removes the draft', () async {
      await store.save('s1', '临时草稿');
      await store.clear('s1');
      expect(await store.load('s1'), isEmpty);
    });

    test('empty save acts as clear', () async {
      await store.save('s1', '旧内容');
      await store.save('s1', '   ');
      expect(await store.load('s1'), isEmpty);
    });

    test('drafts are isolated per session', () async {
      await store.save('sA', '草稿A');
      await store.save('sB', '草稿B');
      expect(await store.load('sA'), '草稿A');
      expect(await store.load('sB'), '草稿B');
    });

    test('unknown session returns empty string', () async {
      expect(await store.load('missing'), isEmpty);
    });
  });

  group('loadActiveSessionForGame', () {
    late Directory root;
    late GameSessionStorageService storage;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('active_query_');
      storage = GameSessionStorageService(
        storage: NativePlatformStorage(root.path),
      );
    });

    test('returns latest active session for the game', () async {
      final older = playingSession(
        sessionId: 'old',
      ).copyWith(updatedAt: DateTime(2026, 9, 19));
      final recent = playingSession(
        sessionId: 'recent',
      ).copyWith(updatedAt: DateTime(2026, 9, 20));
      await storage.save(older);
      await storage.save(recent);
      final active = await storage.loadActiveSessionForGame(
        MiniGameRegistry.turtleSoupId,
      );
      expect(active?.sessionId, 'recent');
    });

    test('finished session is not resumable', () async {
      final finished = playingSession(
        sessionId: 'done',
      ).copyWith(status: GameSessionStatus.finished);
      await storage.save(finished);
      expect(
        await storage.loadActiveSessionForGame(MiniGameRegistry.turtleSoupId),
        isNull,
      );
    });

    test('returns null when no active session exists', () async {
      expect(
        await storage.loadActiveSessionForGame(MiniGameRegistry.turtleSoupId),
        isNull,
      );
    });
  });

  group('TurtleSoupActionPanel draft persistence', () {
    late GameRoomDraftStore store;

    setUp(() async {
      store = GameRoomDraftStore(storage: _MemoryPlatformStorage());
    });

    Widget panelFor(String sessionId, {List<GameMessage> messages = const []}) {
      final session = playingSession(sessionId: sessionId, messages: messages);
      return PeiLinkThemeScope(
        controller: PeiLinkThemeController(),
        child: MaterialApp(
          home: Scaffold(
            body: TurtleSoupActionPanel(
              session: session,
              onStart: () async {},
              onAction: (_) async {},
              onPlayAgain: () async {},
              onViewRecord: () {},
              draftStore: store,
            ),
          ),
        ),
      );
    }

    testWidgets('re-entering the same session restores the unsent draft', (
      tester,
    ) async {
      await tester.pumpWidget(panelFor('draft-session'));
      await tester.pump();
      final input = find.byKey(const ValueKey('turtle-soup-input'));
      await tester.enterText(input, '这个人是不是认识死者');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      expect(await store.load('draft-session'), '这个人是不是认识死者');

      // Simulate dispose (leave the room) and re-enter the same session.
      await tester.pumpWidget(const SizedBox());
      await tester.pump();

      await tester.pumpWidget(panelFor('draft-session'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      expect(tester.widget<TextField>(input).controller?.text, '这个人是不是认识死者');
      expect(find.text('这个人是不是认识死者'), findsOneWidget);
    });

    testWidgets('draft from another session does not leak into this session', (
      tester,
    ) async {
      await store.save('other', '别的房间草稿');
      await tester.pumpWidget(panelFor('brand-new-session'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      expect(find.text('别的房间草稿'), findsNothing);
    });

    testWidgets('sending a question clears the persisted draft', (
      tester,
    ) async {
      await tester.pumpWidget(panelFor('send-clears'));
      await tester.pump();
      final input = find.byKey(const ValueKey('turtle-soup-input'));
      await tester.enterText(input, '要发送的问题');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      await tester.tap(find.byKey(const ValueKey('turtle-soup-send')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      expect(await store.load('send-clears'), isEmpty);
    });

    testWidgets('Play Again transition clears the previous round draft', (
      tester,
    ) async {
      const sessionId = 'play-again-clears';
      await store.save(sessionId, '上一局未发送内容');
      final previousMessage = GameMessage(
        sessionId: sessionId,
        senderId: 'user:1',
        type: GameMessageType.question,
        content: '上一局问题',
      );
      await tester.pumpWidget(panelFor(sessionId, messages: [previousMessage]));
      await tester.pump();

      await tester.pumpWidget(panelFor(sessionId));
      await tester.pump();
      expect(await store.load(sessionId), isEmpty);
    });
  });

  group('Active session resume has no side effects', () {
    late GameSessionStorageService storage;

    setUp(() async {
      storage = GameSessionStorageService(storage: _MemoryPlatformStorage());
    });

    testWidgets(
      'resume does not call judge, does not replay history as new bubbles',
      (tester) async {
        final history = [
          GameMessage(
            sessionId: 'resume-room',
            senderId: 'user:1',
            type: GameMessageType.question,
            content: '警报是不是通过视觉信号触发的？',
          ),
          GameMessage(
            sessionId: 'resume-room',
            senderId: 'host',
            type: GameMessageType.answer,
            content: '是的。',
          ),
        ];
        final persisted = playingSession(
          sessionId: 'resume-room',
          messages: history,
          questionCount: 3,
        );
        await storage.save(persisted);

        final judge = _RecordingJudge();
        await tester.pumpWidget(
          PeiLinkThemeScope(
            controller: PeiLinkThemeController(),
            child: MaterialApp(
              home: GameRoomPage(
                session: persisted,
                storage: storage,
                engine: TurtleSoupEngine(semanticJudge: judge),
                characterLoader: () async => const [],
                participationDirector: CharacterParticipationDirector(
                  agent: const DeterministicCharacterGameAgent(
                    actionType: CharacterGameActionType.pass,
                  ),
                  legality: const TurtleSoupCharacterParticipationAdapter(),
                  viewBuilder: const TurtleSoupCharacterAgentViewBuilder(),
                ),
                bubbleDuration: const Duration(milliseconds: 40),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 120));

        // Resume must not invoke the Semantic Judge.
        expect(judge.calls, 0);

        // History is rendered as timeline content.
        expect(find.text('警报是不是通过视觉信号触发的？'), findsOneWidget);
        expect(find.text('是的。'), findsOneWidget);
        // Stats preserved.
        expect(find.textContaining('提问 3'), findsOneWidget);

        expect(tester.takeException(), isNull);
      },
    );
  });
}

class _RecordingJudge implements TurtleSoupSemanticJudge {
  int calls = 0;

  @override
  Future<TurtleSoupJudgment?> judge(TurtleSoupJudgeRequest request) async {
    calls++;
    return TurtleSoupJudgment.yes;
  }
}

class _MemoryPlatformStorage implements PlatformStorage {
  final Map<String, Uint8List> _values = {};

  @override
  String reference(String key) => 'memory://draft-test/$key';

  @override
  Future<bool> exists(String key) async => _values.containsKey(key);

  @override
  Future<String> readText(String key) async =>
      utf8.decode(_values[key] ?? Uint8List(0));

  @override
  Future<Uint8List> readBytes(String key) async =>
      Uint8List.fromList(_values[key] ?? Uint8List(0));

  @override
  Future<void> writeText(String key, String value) async {
    _values[key] = Uint8List.fromList(utf8.encode(value));
  }

  @override
  Future<void> writeBytes(String key, Uint8List value) async {
    _values[key] = Uint8List.fromList(value);
  }

  @override
  Future<void> replaceTextSafely(String key, String value) =>
      writeText(key, value);

  @override
  Future<void> delete(String key, {bool recursive = false}) async {
    _values.remove(key);
  }

  @override
  Future<List<PlatformStorageEntry>> list(
    String key, {
    bool recursive = false,
  }) async => const [];
}

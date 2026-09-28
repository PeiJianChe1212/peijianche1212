import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/games/engines/game_engine.dart';
import 'package:peijianche_app/games/models/game_models.dart';
import 'package:peijianche_app/games/participation/character_game_action.dart';
import 'package:peijianche_app/games/participation/character_participation_director.dart';
import 'package:peijianche_app/games/presentation/game_timeline_sender_resolver.dart';
import 'package:peijianche_app/games/registry/mini_game_registry.dart';
import 'package:peijianche_app/games/services/game_room_visibility.dart';
import 'package:peijianche_app/games/storage/game_session_storage_service.dart';
import 'package:peijianche_app/games/turtle_soup/turtle_soup_character_agent_view_builder.dart';
import 'package:peijianche_app/games/turtle_soup/turtle_soup_character_participation_adapter.dart';
import 'package:peijianche_app/games/turtle_soup/turtle_soup_engine.dart';
import 'package:peijianche_app/games/turtle_soup/turtle_soup_models.dart';
import 'package:peijianche_app/games/turtle_soup/turtle_soup_public_summary.dart';
import 'package:peijianche_app/models/ai_character.dart';
import 'package:peijianche_app/pages/peilink/games/game_room_page.dart';
import 'package:peijianche_app/pages/peilink/games/game_room_shell.dart';
import 'package:peijianche_app/platform/storage/native_platform_storage.dart';
import 'package:peijianche_app/platform/storage/platform_storage.dart';
import 'package:peijianche_app/services/peilink_theme_service.dart';
import 'package:peijianche_app/widgets/theme/peilink_theme_scope.dart';
import 'package:peijianche_app/widgets/theme/peilink_themed_avatar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final definition = MiniGameRegistry.instance.definition('turtle_soup');

  GameParticipant character(int index) => GameParticipant(
    participantId: 'character:c$index',
    type: GameParticipantType.character,
    displayName: '角色$index',
    characterId: 'c$index',
  );

  TurtleSoupState state() => const TurtleSoupState(
    puzzleId: 'p1',
    title: '测试谜题',
    surface: '一句简短谜面。',
    truth: '完整真相。',
    hints: ['提示一', '提示二'],
  );

  GameSession session({
    GameSessionStatus status = GameSessionStatus.ready,
    GameHost host = const GameHost.system(),
    List<GameParticipant>? participants,
    List<GameMessage> messages = const [],
    TurtleSoupState? gameState,
  }) => GameSession(
    sessionId: 'room-shell-v2',
    gameId: MiniGameRegistry.turtleSoupId,
    createdAt: DateTime(2026, 9, 20),
    updatedAt: DateTime(2026, 9, 20),
    status: status,
    host: host,
    participants:
        participants ??
        [
          const GameParticipant(
            participantId: 'user',
            type: GameParticipantType.user,
            displayName: '我',
          ),
          character(1),
          character(2),
        ],
    gameState: gameState ?? state(),
    messages: messages,
  );

  Future<void> pumpThemed(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      PeiLinkThemeScope(
        controller: PeiLinkThemeController(),
        child: MaterialApp(home: child),
      ),
    );
    await tester.pump();
  }

  test('seat capacity derives from definition and excludes user', () {
    final value = session(
      participants: [
        const GameParticipant(
          participantId: 'user',
          type: GameParticipantType.user,
          displayName: '我',
        ),
        ...List.generate(7, (index) => character(index + 1)),
      ],
    );
    final assignment = GameSeatAssignment.from(
      session: value,
      definition: definition,
    );
    expect(assignment.left, hasLength(4));
    expect(assignment.right, hasLength(3));
    expect(assignment.left.map((item) => item.participant?.characterId), [
      'c1',
      'c3',
      'c5',
      'c7',
    ]);
    expect(assignment.right.map((item) => item.participant?.characterId), [
      'c2',
      'c4',
      'c6',
    ]);
    expect(
      [
        ...assignment.left,
        ...assignment.right,
      ].any((item) => item.participant?.type == GameParticipantType.user),
      isFalse,
    );
  });

  test('character host is centered and removed from stable side seats', () {
    final value = session(
      host: const GameHost.character('c1'),
      participants: [
        const GameParticipant(
          participantId: 'user',
          type: GameParticipantType.user,
          displayName: '我',
        ),
        character(1),
        character(2),
        character(3),
      ],
    );
    final first = GameSeatAssignment.from(
      session: value,
      definition: definition,
    );
    final second = GameSeatAssignment.from(
      session: value,
      definition: definition,
    );
    expect([...first.left, ...first.right], hasLength(6));
    expect(
      [
        ...first.left,
        ...first.right,
      ].any((item) => item.participant?.characterId == 'c1'),
      isFalse,
    );
    expect(
      first.left.map((item) => item.participant?.characterId),
      second.left.map((item) => item.participant?.characterId),
    );
  });

  test(
    'one visibility path filters private messages for timeline and bubbles',
    () {
      final value = session(
        messages: [
          GameMessage(
            sessionId: 'room-shell-v2',
            senderId: 'host',
            type: GameMessageType.answer,
            content: '公开',
          ),
          GameMessage(
            sessionId: 'room-shell-v2',
            senderId: 'character:c1',
            type: GameMessageType.participant,
            content: '给我',
            visibility: GameMessageVisibility.privateToParticipant,
            visibleToParticipantId: 'user',
          ),
          GameMessage(
            sessionId: 'room-shell-v2',
            senderId: 'character:c2',
            type: GameMessageType.participant,
            content: '不是给我',
            visibility: GameMessageVisibility.privateToParticipant,
            visibleToParticipantId: 'other',
          ),
        ],
      );
      final visible = GameRoomVisibility.visibleMessages(value);
      expect(visible.map((item) => item.content), ['公开', '给我']);
    },
  );

  test(
    'timeline resolves user, character, host and safe fallback identities',
    () {
      GameMessage message(String sender, GameMessageType type) => GameMessage(
        sessionId: 'room-shell-v2',
        senderId: sender,
        type: type,
        content: '内容',
      );
      final registryCharacter = AiCharacter(
        id: 'c1',
        characterName: '登记名称',
        remark: '老裴',
        createdAt: DateTime(2026, 9, 20),
      );
      final systemResolver = GameTimelineSenderResolver(
        session: session(),
        characters: [registryCharacter],
      );
      expect(
        systemResolver.labelFor(message('user', GameMessageType.question)),
        '我 · 提问',
      );
      expect(
        systemResolver.labelFor(message('character:c1', GameMessageType.guess)),
        '老裴 · 猜测',
      );
      expect(
        systemResolver.labelFor(
          message('character:c1', GameMessageType.participant),
        ),
        '老裴 · 回应',
      );
      expect(
        systemResolver.labelFor(message('host', GameMessageType.answer)),
        '主持 · 回答',
      );
      expect(
        systemResolver.labelFor(message('system', GameMessageType.narration)),
        '系统',
      );
      expect(
        systemResolver.labelFor(
          message('character:c2', GameMessageType.question),
        ),
        '角色2 · 提问',
      );

      final characterHostResolver = GameTimelineSenderResolver(
        session: session(host: const GameHost.character('c1')),
        characters: [registryCharacter],
      );
      expect(
        characterHostResolver.labelFor(message('host', GameMessageType.answer)),
        '老裴 · 主持',
      );
      final missingRegistryResolver = GameTimelineSenderResolver(
        session: session(host: const GameHost.character('c1')),
      );
      expect(
        missingRegistryResolver.labelFor(
          message('host', GameMessageType.answer),
        ),
        '角色1 · 主持',
      );
      expect(
        missingRegistryResolver.labelFor(
          message('character:c1', GameMessageType.question),
        ),
        isNot(contains('c1')),
      );
    },
  );

  testWidgets('shell renders game info, seats and recent conversation stage', (
    tester,
  ) async {
    await pumpThemed(
      tester,
      Scaffold(
        body: GameRoomShell(
          definition: definition,
          session: session(),
          host: const GameHostVisual(name: '系统主持人', isSystem: true),
          visibleMessages: const [],
          timelineSenderResolver: GameTimelineSenderResolver(
            session: session(),
          ),
          gameInfo: const SizedBox(key: ValueKey('test-game-info')),
          actionArea: const SizedBox(
            key: ValueKey('test-action-area'),
            height: 64,
          ),
          onBack: () {},
          onPauseChanged: (_) {},
          onInvite: () {},
        ),
      ),
    );
    expect(find.byKey(const ValueKey('game-room-header')), findsOneWidget);
    expect(find.byKey(const ValueKey('test-game-info')), findsOneWidget);
    expect(find.byKey(const ValueKey('game-host-seat')), findsOneWidget);
    expect(find.byKey(const ValueKey('game-seats-left')), findsOneWidget);
    expect(find.byKey(const ValueKey('game-seats-right')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('game-recent-conversation-stage')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('game-timeline-compact')), findsNothing);
    expect(find.byKey(const ValueKey('test-action-area')), findsOneWidget);
    expect(find.byType(PeiLinkThemedAvatar), findsNWidgets(3));
  });

  testWidgets('empty seats enable only before play', (tester) async {
    var invited = 0;
    Widget shell(GameSession value) => Scaffold(
      body: GameRoomShell(
        definition: definition,
        session: value,
        host: const GameHostVisual(name: '系统主持人', isSystem: true),
        visibleMessages: const [],
        timelineSenderResolver: GameTimelineSenderResolver(session: value),
        gameInfo: const SizedBox(),
        actionArea: const SizedBox(height: 50),
        onBack: () {},
        onPauseChanged: (_) {},
        onInvite: () => invited++,
      ),
    );
    await pumpThemed(tester, shell(session()));
    await tester.tap(find.byKey(const ValueKey('game-empty-seat-left')).first);
    expect(invited, 1);
    await pumpThemed(tester, shell(session(status: GameSessionStatus.playing)));
    await tester.tap(find.byKey(const ValueKey('game-empty-seat-left')).first);
    expect(invited, 1);
  });

  testWidgets(
    'seat bubble truncates and timeline expands with retained filter',
    (tester) async {
      const longText =
          '这是一段用于验证完整记录展示的长文本。它包含足够多的内容，确保紧凑时间线只显示合理的多行，而展开后的游戏记录不会截断正文。';
      final messages = List.generate(
        6,
        (index) => GameMessage(
          id: index == 4 ? 'timeline-long' : 'timeline-$index',
          sessionId: 'room-shell-v2',
          senderId: 'host',
          type: index.isEven
              ? GameMessageType.question
              : GameMessageType.answer,
          content: index == 4 ? longText : '消息$index',
        ),
      );
      await pumpThemed(
        tester,
        Scaffold(
          body: Column(
            children: [
              const GameSeatSpeechBubble(
                text: '这是一段很长很长很长很长很长很长很长很长很长的角色发言',
                side: GameSeatSide.left,
              ),
              Expanded(
                child: GameTimelinePanel(
                  messages: messages,
                  senderResolver: GameTimelineSenderResolver(
                    session: session(),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
      final bubbleText = tester.widget<Text>(
        find.descendant(
          of: find.byType(GameSeatSpeechBubble),
          matching: find.textContaining('这是一段很长'),
        ),
      );
      expect(bubbleText.maxLines, 3);
      expect(bubbleText.overflow, TextOverflow.ellipsis);
      await tester.tap(
        find.byKey(const ValueKey('game-timeline-filter-question')),
      );
      await tester.pump();
      expect(find.text(longText), findsOneWidget);
      expect(find.text('消息5'), findsNothing);
      final compactMessage = tester.widget<Text>(
        find.byKey(
          const ValueKey('game-timeline-message-compact-timeline-long'),
        ),
      );
      expect(compactMessage.maxLines, 3);
      expect(compactMessage.overflow, TextOverflow.ellipsis);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('game-timeline-compact')),
          matching: find.text('主持 · 提问'),
        ),
        findsWidgets,
      );
      await tester.tap(find.byKey(const ValueKey('game-timeline-expand')));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('game-timeline-expanded')),
        findsOneWidget,
      );
      expect(find.text('消息0'), findsWidgets);
      final expandedMessage = tester.widget<Text>(
        find.byKey(
          const ValueKey('game-timeline-message-expanded-timeline-long'),
        ),
      );
      expect(expandedMessage.maxLines, isNull);
      expect(expandedMessage.overflow, TextOverflow.visible);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('game-timeline-expanded')),
          matching: find.text('主持 · 提问'),
        ),
        findsWidgets,
      );
      tester.state<NavigatorState>(find.byType(Navigator).first).pop();
      await tester.pump();
      expect(
        find.byKey(const ValueKey('game-timeline-expanded')),
        findsNothing,
      );
    },
  );

  testWidgets(
    'new visible messages enter recent stage without duplicate bubbles',
    (tester) async {
      final root = await tester.runAsync(
        () => Directory.systemTemp.createTemp('room_shell_bubble_'),
      );
      addTearDown(() => root!.delete(recursive: true));
      final initial = session();
      final engine = _BubbleEngine([
        GameMessage(
          id: 'bubble-old',
          sessionId: initial.sessionId,
          senderId: 'character:c1',
          type: GameMessageType.participant,
          content: '旧发言',
        ),
        GameMessage(
          id: 'bubble-latest',
          sessionId: initial.sessionId,
          senderId: 'character:c1',
          type: GameMessageType.participant,
          content: '最新发言',
        ),
        GameMessage(
          id: 'bubble-host',
          sessionId: initial.sessionId,
          senderId: 'host',
          type: GameMessageType.answer,
          content: '主持回答',
        ),
        GameMessage(
          id: 'bubble-system',
          sessionId: initial.sessionId,
          senderId: 'system',
          type: GameMessageType.system,
          content: '系统事件',
        ),
        GameMessage(
          id: 'bubble-private',
          sessionId: initial.sessionId,
          senderId: 'character:c2',
          type: GameMessageType.participant,
          content: '不可见',
          visibility: GameMessageVisibility.privateToParticipant,
          visibleToParticipantId: 'other',
        ),
      ]);
      await pumpThemed(
        tester,
        GameRoomPage(
          session: initial,
          storage: GameSessionStorageService(
            storage: NativePlatformStorage(root!.path),
          ),
          engine: engine,
          characterLoader: () async => const <AiCharacter>[],
          bubbleDuration: const Duration(milliseconds: 80),
        ),
      );
      final stageBefore = tester.getRect(
        find.byKey(const ValueKey('game-stage')),
      );
      await tester.tap(find.byKey(const ValueKey('game-room-start')));
      await tester.pump();
      expect(
        tester.getRect(find.byKey(const ValueKey('game-stage'))),
        stageBefore,
      );
      final playStack = tester.widget<Stack>(
        find.byKey(const ValueKey('game-play-stack')),
      );
      expect(playStack.clipBehavior, Clip.none);
      expect(find.byType(GameSeatSpeechBubble), findsNothing);
      expect(
        find.descendant(
          of: find.byType(GameRecentConversationStage),
          matching: find.text('最新发言'),
        ),
        findsOneWidget,
      );
      expect(find.text('主持回答'), findsOneWidget);
      expect(find.text('不可见'), findsNothing);
    },
  );

  testWidgets(
    'restored history appears in recent stage and small screen fits',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final old = GameMessage(
        sessionId: 'room-shell-v2',
        senderId: 'character:c1',
        type: GameMessageType.participant,
        content: '历史发言不重播',
      );
      final root = await tester.runAsync(
        () => Directory.systemTemp.createTemp('room_shell_restore_'),
      );
      addTearDown(() => root!.delete(recursive: true));
      await pumpThemed(
        tester,
        GameRoomPage(
          session: session(messages: [old]),
          storage: GameSessionStorageService(
            storage: NativePlatformStorage(root!.path),
          ),
          engine: _BubbleEngine(const []),
          characterLoader: () async => const <AiCharacter>[],
        ),
      );
      expect(find.byKey(const ValueKey('game-room-shell')), findsOneWidget);
      expect(find.byType(GameSeatSpeechBubble), findsNothing);
      expect(find.text('历史发言不重播'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('character host uses registry profile and participant role', (
    tester,
  ) async {
    final root = await tester.runAsync(
      () => Directory.systemTemp.createTemp('room_shell_host_'),
    );
    addTearDown(() => root!.delete(recursive: true));
    await pumpThemed(
      tester,
      GameRoomPage(
        session: session(
          host: const GameHost.character('c1'),
          participants: [
            const GameParticipant(
              participantId: 'user',
              type: GameParticipantType.user,
              displayName: '我',
            ),
            character(1),
          ],
        ),
        storage: GameSessionStorageService(
          storage: NativePlatformStorage(root!.path),
        ),
        engine: const _BubbleEngine([]),
        characterLoader: () async => [
          AiCharacter(
            id: 'c1',
            characterName: '档案主持',
            remark: '',
            createdAt: DateTime(2026, 9, 20),
          ),
        ],
      ),
    );
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.text('档案主持'), findsOneWidget);
    expect(find.text('主持 / 玩家'), findsOneWidget);
    expect(find.text('角色1'), findsNothing);
  });

  testWidgets('missing host registry data falls back safely', (tester) async {
    final root = await tester.runAsync(
      () => Directory.systemTemp.createTemp('room_shell_host_fallback_'),
    );
    addTearDown(() => root!.delete(recursive: true));
    await pumpThemed(
      tester,
      GameRoomPage(
        session: session(host: const GameHost.character('missing')),
        storage: GameSessionStorageService(
          storage: NativePlatformStorage(root!.path),
        ),
        engine: const _BubbleEngine([]),
        characterLoader: () async => const <AiCharacter>[],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('角色主持人'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('keyboard overlays room, dismisses outside and keeps draft', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    final root = await tester.runAsync(
      () => Directory.systemTemp.createTemp('room_shell_keyboard_'),
    );
    addTearDown(() => root!.delete(recursive: true));
    GameAction? recordedAction;
    final engine = _BubbleEngine(
      const [],
      onUserAction: (action) => recordedAction = action,
    );
    await pumpThemed(
      tester,
      GameRoomPage(
        session: session(
          status: GameSessionStatus.playing,
          gameState: state().copyWith(phase: TurtleSoupPhase.questioning),
        ),
        storage: GameSessionStorageService(
          storage: NativePlatformStorage(root!.path),
        ),
        engine: engine,
        characterLoader: () async => const <AiCharacter>[],
      ),
    );
    await tester.pump();
    final input = find.byKey(const ValueKey('turtle-soup-input'));
    final stage = find.byKey(const ValueKey('game-stage'));
    bool inputHasFocus() => tester
        .widget<EditableText>(
          find.descendant(of: input, matching: find.byType(EditableText)),
        )
        .focusNode
        .hasFocus;
    final stageBefore = tester.getRect(stage);
    final inputBefore = tester.getRect(input);
    await tester.tap(input);
    await tester.enterText(input, '尚未发送的草稿');
    expect(inputHasFocus(), isTrue);
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    await tester.pump();
    expect(tester.getRect(stage), stageBefore);
    expect(tester.getRect(input).top, inputBefore.top - 280);
    expect(find.text('尚未发送的草稿'), findsOneWidget);

    await tester.tapAt(stageBefore.topLeft + const Offset(12, 12));
    await tester.pump();
    expect(inputHasFocus(), isFalse);
    expect(find.text('尚未发送的草稿'), findsOneWidget);

    await tester.tap(input);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('turtle-soup-hint')));
    await tester.pump();
    expect(recordedAction?.payload['kind'], 'hint');
    expect(inputHasFocus(), isFalse);

    tester.view.viewInsets = const FakeViewPadding();
    await tester.pump();
    expect(tester.getRect(stage), stageBefore);
    expect(tester.getRect(input), inputBefore);
    expect(find.text('尚未发送的草稿'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'user action runs one turn per character through engine and recent stage',
    (tester) async {
      tester.view.physicalSize = const Size(430, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final agent = _CountingAgent();
      final director = _RecordingDirector(
        agent: agent,
        legality: const _AlwaysCharacterLegality(),
        viewBuilder: const TurtleSoupCharacterAgentViewBuilder(),
        minimumInterval: Duration.zero,
      );
      final engine = _ParticipationEngine();
      await pumpThemed(
        tester,
        GameRoomPage(
          session: session(
            status: GameSessionStatus.playing,
            gameState: state().copyWith(phase: TurtleSoupPhase.questioning),
          ),
          storage: GameSessionStorageService(storage: _MemoryPlatformStorage()),
          engine: engine,
          participationDirector: director,
          characterLoader: () async => const <AiCharacter>[],
          bubbleDuration: const Duration(seconds: 4),
        ),
      );
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 250)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('turtle-soup-hint')));
      await tester.pump();
      for (
        var attempt = 0;
        attempt < 20 && director.offerCount < 2;
        attempt++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump();
      }
      expect(engine.userActionCount, 1);
      expect(director.offerCount, 2);
      expect(director.lastStatus, GameSessionStatus.playing);
      expect(director.lastCharacterCount, 2);
      expect(agent.callCount, 2);
      expect(engine.characterActionCount, 2);
      expect(find.text('角色只行动一次'), findsWidgets);
      expect(
        find.descendant(
          of: find.byType(GameRecentConversationStage),
          matching: find.text('角色只行动一次'),
        ),
        findsWidgets,
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(agent.callCount, 2);
    },
  );

  testWidgets(
    'AI failure cannot lose user action and disposed page drops result',
    (tester) async {
      final storage = GameSessionStorageService(
        storage: _MemoryPlatformStorage(),
      );
      final agent = _LifecycleAgent();
      final engine = _ParticipationEngine();
      final director = CharacterParticipationDirector(
        agent: agent,
        legality: const _AlwaysCharacterLegality(),
        viewBuilder: const TurtleSoupCharacterAgentViewBuilder(),
        minimumInterval: Duration.zero,
      );
      await pumpThemed(
        tester,
        GameRoomPage(
          session: session(
            status: GameSessionStatus.playing,
            gameState: state().copyWith(phase: TurtleSoupPhase.questioning),
          ),
          storage: storage,
          engine: engine,
          participationDirector: director,
          characterLoader: () async => const <AiCharacter>[],
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('turtle-soup-hint')));
      for (var attempt = 0; attempt < 20 && agent.callCount == 0; attempt++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump();
      }
      expect(agent.callCount, 1);
      final persisted = await tester.runAsync(
        () => storage.load('room-shell-v2'),
      );
      expect(
        persisted!.messages.map((message) => message.content),
        contains('用户动作已保存'),
      );

      await pumpThemed(tester, const SizedBox());
      agent.complete(
        const CharacterGameAction(
          actorParticipantId: 'character:c1',
          type: CharacterGameActionType.react,
          content: '页面退出后不得写入',
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
      expect(engine.characterActionCount, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('character finish ends the round before remaining turns', (
    tester,
  ) async {
    final agent = _CountingAgent();
    final engine = _FinishingParticipationEngine();
    await pumpThemed(
      tester,
      GameRoomPage(
        session: session(
          status: GameSessionStatus.playing,
          gameState: state().copyWith(phase: TurtleSoupPhase.questioning),
        ),
        storage: GameSessionStorageService(storage: _MemoryPlatformStorage()),
        engine: engine,
        participationDirector: CharacterParticipationDirector(
          agent: agent,
          legality: const _AlwaysCharacterLegality(),
          viewBuilder: const TurtleSoupCharacterAgentViewBuilder(),
        ),
        characterLoader: () async => const <AiCharacter>[],
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('turtle-soup-hint')));
    for (
      var attempt = 0;
      attempt < 20 && engine.characterActionCount == 0;
      attempt++
    ) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(agent.callCount, 1);
    expect(engine.characterActionCount, 1);
    expect(find.byKey(const ValueKey('turtle-soup-finished')), findsOneWidget);
  });

  testWidgets('new user action supersedes a running AI round without loss', (
    tester,
  ) async {
    final agent = _InterruptibleAgent();
    final engine = _ParticipationEngine();
    final storage = GameSessionStorageService(
      storage: _MemoryPlatformStorage(),
    );
    await pumpThemed(
      tester,
      GameRoomPage(
        session: session(
          status: GameSessionStatus.playing,
          gameState: state().copyWith(phase: TurtleSoupPhase.questioning),
        ),
        storage: storage,
        engine: engine,
        participationDirector: CharacterParticipationDirector(
          agent: agent,
          legality: const _AlwaysCharacterLegality(),
          viewBuilder: const TurtleSoupCharacterAgentViewBuilder(),
        ),
        characterLoader: () async => const <AiCharacter>[],
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('turtle-soup-hint')));
    for (var attempt = 0; attempt < 20 && agent.callCount == 0; attempt++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(
      find.byKey(const ValueKey('game-seat-thinking-character:c1')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('turtle-soup-hint')));
    await tester.pump();
    expect(find.text('正在思考…'), findsNothing);
    for (
      var attempt = 0;
      attempt < 20 && engine.userActionCount < 2;
      attempt++
    ) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(engine.userActionCount, 2);
    agent.releaseFirst();
    await tester.pumpAndSettle();
    expect(engine.characterActionCount, 0);
    final persisted = await storage.load('room-shell-v2');
    expect(
      persisted!.messages.where((message) => message.content == '用户动作已保存'),
      hasLength(2),
    );
  });

  testWidgets('thinking state follows real turns through pass and all-pass', (
    tester,
  ) async {
    final agent = _QueuedTurnAgent();
    await pumpThemed(
      tester,
      GameRoomPage(
        session: session(
          status: GameSessionStatus.playing,
          gameState: state().copyWith(phase: TurtleSoupPhase.questioning),
        ),
        storage: GameSessionStorageService(storage: _MemoryPlatformStorage()),
        engine: _ParticipationEngine(),
        participationDirector: CharacterParticipationDirector(
          agent: agent,
          legality: const _AllCharacterActionsLegality(),
          viewBuilder: const TurtleSoupCharacterAgentViewBuilder(),
        ),
        characterLoader: () async => const <AiCharacter>[],
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('turtle-soup-let-them-continue')),
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey('game-seat-thinking-character:c1')),
      findsOneWidget,
    );
    agent.completeNext(CharacterGameActionType.pass);
    await tester.pump();
    expect(
      find.byKey(const ValueKey('game-seat-thinking-character:c2')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('game-seat-thinking-character:c1')),
      findsNothing,
    );
    agent.completeNext(CharacterGameActionType.pass);
    await tester.pumpAndSettle();
    expect(find.text('正在思考…'), findsNothing);
    expect(find.text('大家暂时没有新的思路'), findsOneWidget);
  });

  testWidgets('agent failure clears thinking and completes the round', (
    tester,
  ) async {
    await pumpThemed(
      tester,
      GameRoomPage(
        session: session(
          status: GameSessionStatus.playing,
          gameState: state().copyWith(phase: TurtleSoupPhase.questioning),
        ),
        storage: GameSessionStorageService(storage: _MemoryPlatformStorage()),
        engine: _ParticipationEngine(),
        participationDirector: CharacterParticipationDirector(
          agent: _FailingTurnAgent(),
          legality: const _AllCharacterActionsLegality(),
          viewBuilder: const TurtleSoupCharacterAgentViewBuilder(),
        ),
        characterLoader: () async => const <AiCharacter>[],
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('turtle-soup-let-them-continue')),
    );
    await tester.pumpAndSettle();
    expect(find.text('正在思考…'), findsNothing);
    expect(find.text('大家暂时没有新的思路'), findsOneWidget);
    expect(find.text('让他们继续'), findsOneWidget);
  });

  testWidgets('host participant shows thinking in central host seat', (
    tester,
  ) async {
    final agent = _QueuedTurnAgent();
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpThemed(
      tester,
      GameRoomPage(
        session: session(
          status: GameSessionStatus.playing,
          host: const GameHost.character('c1'),
          gameState: state().copyWith(phase: TurtleSoupPhase.questioning),
        ),
        storage: GameSessionStorageService(storage: _MemoryPlatformStorage()),
        engine: _ParticipationEngine(),
        participationDirector: CharacterParticipationDirector(
          agent: agent,
          legality: const _AllCharacterActionsLegality(),
          viewBuilder: const TurtleSoupCharacterAgentViewBuilder(),
        ),
        characterLoader: () async => const <AiCharacter>[],
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('turtle-soup-let-them-continue')),
    );
    await tester.pump();
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('game-host-seat')),
        matching: find.byKey(const ValueKey('game-seat-thinking-character:c1')),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    agent.completeNext(CharacterGameActionType.pass);
    await tester.pump();
    agent.completeNext(CharacterGameActionType.pass);
    await tester.pumpAndSettle();
    expect(find.text('正在思考…'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'manual rounds restart after semantic duplicate, pass and valid actions',
    (tester) async {
      final agent = _MixedManualRoundAgent();
      final engine = _ParticipationEngine();
      await pumpThemed(
        tester,
        GameRoomPage(
          session: session(
            status: GameSessionStatus.playing,
            gameState: state().copyWith(phase: TurtleSoupPhase.questioning),
            messages: [
              GameMessage(
                sessionId: 'room-shell-v2',
                senderId: 'character:c1',
                type: GameMessageType.guess,
                content: '这是一段会被识别的重复猜测内容',
              ),
            ],
          ),
          storage: GameSessionStorageService(storage: _MemoryPlatformStorage()),
          engine: engine,
          participationDirector: CharacterParticipationDirector(
            agent: agent,
            legality: const _AllCharacterActionsLegality(),
            viewBuilder: const TurtleSoupCharacterAgentViewBuilder(),
            minimumInterval: Duration.zero,
          ),
          characterLoader: () async => const <AiCharacter>[],
        ),
      );
      await tester.pumpAndSettle();

      Future<void> runManualRound(int expectedCalls) async {
        await tester.tap(
          find.byKey(const ValueKey('turtle-soup-let-them-continue')),
        );
        await tester.pump();
        for (
          var attempt = 0;
          attempt < 30 && agent.callCount < expectedCalls;
          attempt++
        ) {
          await tester.pump(const Duration(milliseconds: 10));
        }
        await tester.pump();
        expect(agent.callCount, expectedCalls);
        expect(find.text('让他们继续'), findsOneWidget);
      }

      await runManualRound(2); // semantic duplicate + ordinary pass
      expect(engine.characterActionCount, 0);
      expect(find.text('大家暂时没有新的思路'), findsOneWidget);
      expect(find.text('让他们继续'), findsOneWidget);
      await runManualRound(4); // ordinary pass + valid action
      expect(engine.characterActionCount, 1);
      expect(find.text('大家暂时没有新的思路'), findsNothing);
      await runManualRound(6); // semantic duplicate + another valid action
      expect(engine.characterActionCount, 2);
      expect(find.text('大家暂时没有新的思路'), findsNothing);
    },
  );

  testWidgets('consecutive all-pass manual rounds reset feedback and timer', (
    tester,
  ) async {
    final agent = _BlockingManualPassAgent();
    await pumpThemed(
      tester,
      GameRoomPage(
        session: session(
          status: GameSessionStatus.playing,
          gameState: state().copyWith(phase: TurtleSoupPhase.questioning),
        ),
        storage: GameSessionStorageService(storage: _MemoryPlatformStorage()),
        engine: _ParticipationEngine(),
        participationDirector: CharacterParticipationDirector(
          agent: agent,
          legality: const _AllCharacterActionsLegality(),
          viewBuilder: const TurtleSoupCharacterAgentViewBuilder(),
        ),
        characterLoader: () async => const <AiCharacter>[],
      ),
    );
    await tester.pumpAndSettle();
    final button = find.byKey(const ValueKey('turtle-soup-let-them-continue'));
    await tester.tap(button);
    await tester.pump();
    expect(find.text('大家暂时没有新的思路'), findsOneWidget);

    await tester.tap(button);
    await tester.pump();
    expect(find.text('大家暂时没有新的思路'), findsNothing);
    expect(find.text('他们正在推理…'), findsOneWidget);
    agent.releaseBlockedTurn();
    await tester.pumpAndSettle();
    expect(find.text('大家暂时没有新的思路'), findsOneWidget);
    expect(find.text('让他们继续'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
    expect(tester.takeException(), isNull);
  });

  testWidgets('user-triggered all-pass round never shows manual feedback', (
    tester,
  ) async {
    await pumpThemed(
      tester,
      GameRoomPage(
        session: session(
          status: GameSessionStatus.playing,
          gameState: state().copyWith(phase: TurtleSoupPhase.questioning),
        ),
        storage: GameSessionStorageService(storage: _MemoryPlatformStorage()),
        engine: _ParticipationEngine(),
        participationDirector: CharacterParticipationDirector(
          agent: const DeterministicCharacterGameAgent(
            actionType: CharacterGameActionType.pass,
          ),
          legality: const _AllCharacterActionsLegality(),
          viewBuilder: const TurtleSoupCharacterAgentViewBuilder(),
        ),
        characterLoader: () async => const <AiCharacter>[],
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('turtle-soup-hint')));
    await tester.pumpAndSettle();
    expect(find.text('大家暂时没有新的思路'), findsNothing);
  });

  testWidgets('reveal and Play Again clear feedback timer safely', (
    tester,
  ) async {
    await pumpThemed(
      tester,
      GameRoomPage(
        session: session(
          status: GameSessionStatus.playing,
          gameState: state().copyWith(phase: TurtleSoupPhase.questioning),
        ),
        storage: GameSessionStorageService(storage: _MemoryPlatformStorage()),
        engine: const TurtleSoupEngine(),
        participationDirector: CharacterParticipationDirector(
          agent: const DeterministicCharacterGameAgent(
            actionType: CharacterGameActionType.pass,
          ),
          legality: const TurtleSoupCharacterParticipationAdapter(),
          viewBuilder: const TurtleSoupCharacterAgentViewBuilder(),
        ),
        characterLoader: () async => const <AiCharacter>[],
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('turtle-soup-let-them-continue')),
    );
    await tester.pumpAndSettle();
    expect(find.text('大家暂时没有新的思路'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('turtle-soup-reveal')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('揭晓谜底'));
    await tester.pumpAndSettle();
    expect(find.text('大家暂时没有新的思路'), findsNothing);
    expect(find.byKey(const ValueKey('turtle-soup-finished')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('turtle-soup-play-again')));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 3));
    expect(tester.takeException(), isNull);
  });

  testWidgets('public summary opens without actions, rounds or persistence', (
    tester,
  ) async {
    final gateway = _SummaryGateway(
      '{"confirmed":["警报不是依靠声音提醒"],"ruledOut":[],"unresolved":["闪光具体有什么作用"]}',
    );
    final engine = _ParticipationEngine();
    final storage = GameSessionStorageService(
      storage: _MemoryPlatformStorage(),
    );
    final initialMessages = [
      GameMessage(
        sessionId: 'room-shell-v2',
        senderId: 'user',
        type: GameMessageType.question,
        content: '警报通过声音提醒吗？',
      ),
      GameMessage(
        sessionId: 'room-shell-v2',
        senderId: 'host',
        type: GameMessageType.answer,
        content: '不是。',
      ),
      GameMessage(
        sessionId: 'room-shell-v2',
        senderId: 'character:c1',
        type: GameMessageType.question,
        content: '警报和闪光有关吗？',
      ),
    ];
    await pumpThemed(
      tester,
      GameRoomPage(
        session: session(
          status: GameSessionStatus.playing,
          gameState: state().copyWith(
            phase: TurtleSoupPhase.questioning,
            questionCount: 2,
          ),
          messages: initialMessages,
        ),
        storage: storage,
        engine: engine,
        participationDirector: CharacterParticipationDirector(
          agent: const DeterministicCharacterGameAgent(
            actionType: CharacterGameActionType.pass,
          ),
          legality: const _AllCharacterActionsLegality(),
          viewBuilder: const TurtleSoupCharacterAgentViewBuilder(),
        ),
        summaryService: TurtleSoupPublicSummaryService(gateway: gateway),
        characterLoader: () async => const <AiCharacter>[],
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('turtle-soup-summarize')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('turtle-soup-summary-sheet')),
      findsOneWidget,
    );
    expect(find.textContaining('警报不是依靠声音提醒'), findsOneWidget);
    expect(engine.userActionCount, 0);
    expect(engine.characterActionCount, 0);
    expect(gateway.calls, 1);
    final persisted = await storage.load('room-shell-v2');
    expect(persisted?.messages, hasLength(initialMessages.length));
    expect((persisted?.gameState as TurtleSoupState).questionCount, 2);
  });

  testWidgets('summary is disabled while a character round is running', (
    tester,
  ) async {
    final agent = _LifecycleAgent();
    await pumpThemed(
      tester,
      GameRoomPage(
        session: session(
          status: GameSessionStatus.playing,
          gameState: state().copyWith(phase: TurtleSoupPhase.questioning),
        ),
        storage: GameSessionStorageService(storage: _MemoryPlatformStorage()),
        engine: _ParticipationEngine(),
        participationDirector: CharacterParticipationDirector(
          agent: agent,
          legality: const _AlwaysCharacterLegality(),
          viewBuilder: const TurtleSoupCharacterAgentViewBuilder(),
        ),
        characterLoader: () async => const <AiCharacter>[],
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('turtle-soup-let-them-continue')),
    );
    await tester.pump();
    final summarize = tester.widget<TextButton>(
      find.byKey(const ValueKey('turtle-soup-summarize')),
    );
    expect(summarize.onPressed, isNull);
    agent.complete(
      const CharacterGameAction(
        actorParticipantId: 'character:c1',
        type: CharacterGameActionType.pass,
      ),
    );
    await tester.pumpAndSettle();
  });

  testWidgets('stale summary result is dropped after reveal and Play Again', (
    tester,
  ) async {
    final gateway = _BlockingSummaryGateway();
    final initialMessages = [
      GameMessage(
        sessionId: 'room-shell-v2',
        senderId: 'user',
        type: GameMessageType.question,
        content: '声音有关吗？',
      ),
      GameMessage(
        sessionId: 'room-shell-v2',
        senderId: 'character:c1',
        type: GameMessageType.question,
        content: '闪光有关吗？',
      ),
    ];
    await pumpThemed(
      tester,
      GameRoomPage(
        session: session(
          status: GameSessionStatus.playing,
          gameState: state().copyWith(phase: TurtleSoupPhase.questioning),
          messages: initialMessages,
        ),
        storage: GameSessionStorageService(storage: _MemoryPlatformStorage()),
        engine: const TurtleSoupEngine(),
        participationDirector: CharacterParticipationDirector(
          agent: const DeterministicCharacterGameAgent(
            actionType: CharacterGameActionType.pass,
          ),
          legality: const TurtleSoupCharacterParticipationAdapter(),
          viewBuilder: const TurtleSoupCharacterAgentViewBuilder(),
        ),
        summaryService: TurtleSoupPublicSummaryService(gateway: gateway),
        characterLoader: () async => const <AiCharacter>[],
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('turtle-soup-summarize')));
    await tester.pump();
    expect(find.text('正在整理…'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('turtle-soup-reveal')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('揭晓谜底'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('turtle-soup-play-again')));
    await tester.pumpAndSettle();
    gateway.release();
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('turtle-soup-summary-sheet')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });
}

class _CountingAgent implements CharacterGameAgent {
  int callCount = 0;

  @override
  Future<CharacterGameAction> decide(CharacterGameAgentRequest request) async {
    callCount++;
    return CharacterGameAction(
      actorParticipantId: request.actorParticipantId,
      type: CharacterGameActionType.react,
      content: '角色只行动一次',
    );
  }
}

class _MixedManualRoundAgent implements CharacterGameAgent {
  int callCount = 0;

  @override
  Future<CharacterGameAction> decide(CharacterGameAgentRequest request) async {
    callCount++;
    final (type, content) = switch (callCount) {
      1 => (CharacterGameActionType.makeGuess, '这是一段会被识别的重复猜测内容'),
      2 || 3 => (CharacterGameActionType.pass, ''),
      4 => (CharacterGameActionType.askQuestion, '第二轮提出了一个有效的新问题'),
      5 => (CharacterGameActionType.makeGuess, '这是一段会被识别的重复猜测内容'),
      _ => (CharacterGameActionType.makeGuess, '第三轮提出了一个全新的有效猜测'),
    };
    return CharacterGameAction(
      actorParticipantId: request.actorParticipantId,
      type: type,
      content: content,
    );
  }
}

class _BlockingManualPassAgent implements CharacterGameAgent {
  int _calls = 0;
  Completer<CharacterGameAction>? _blocked;

  @override
  Future<CharacterGameAction> decide(CharacterGameAgentRequest request) {
    _calls++;
    if (_calls == 3) {
      _blocked = Completer<CharacterGameAction>();
      return _blocked!.future;
    }
    return Future.value(
      CharacterGameAction(
        actorParticipantId: request.actorParticipantId,
        type: CharacterGameActionType.pass,
      ),
    );
  }

  void releaseBlockedTurn() {
    _blocked!.complete(
      const CharacterGameAction(
        actorParticipantId: 'character:c1',
        type: CharacterGameActionType.pass,
      ),
    );
  }
}

class _AllCharacterActionsLegality implements CharacterGameActionLegality {
  const _AllCharacterActionsLegality();

  @override
  Set<CharacterGameActionType> allowedActions(
    GameSession session,
    GameParticipant participant,
  ) => CharacterGameActionType.values.toSet();
}

class _SummaryGateway implements TurtleSoupSummaryModelGateway {
  _SummaryGateway(this.output);
  final String output;
  int calls = 0;

  @override
  Future<String> complete({
    required List<Map<String, dynamic>> messages,
  }) async {
    calls++;
    return output;
  }
}

class _BlockingSummaryGateway implements TurtleSoupSummaryModelGateway {
  final Completer<String> _completer = Completer<String>();

  @override
  Future<String> complete({required List<Map<String, dynamic>> messages}) =>
      _completer.future;

  void release() => _completer.complete(
    '{"confirmed":["声音有关"],"ruledOut":[],"unresolved":[]}',
  );
}

class _AlwaysCharacterLegality implements CharacterGameActionLegality {
  const _AlwaysCharacterLegality();

  @override
  Set<CharacterGameActionType> allowedActions(
    GameSession session,
    GameParticipant participant,
  ) => const {CharacterGameActionType.react, CharacterGameActionType.pass};
}

class _RecordingDirector extends CharacterParticipationDirector {
  _RecordingDirector({
    required super.agent,
    required super.legality,
    required super.viewBuilder,
    required super.minimumInterval,
  });

  int offerCount = 0;
  GameSessionStatus? lastStatus;
  int? lastCharacterCount;

  @override
  Future<CharacterParticipationDecision> offerTurn({
    required GameSession session,
    GameAction? trigger,
    required CharacterParticipationRound round,
  }) {
    offerCount++;
    lastStatus = session.status;
    lastCharacterCount = session.participants
        .where((item) => item.type == GameParticipantType.character)
        .length;
    return super.offerTurn(session: session, trigger: trigger, round: round);
  }
}

class _ParticipationEngine implements GameEngine<TurtleSoupState> {
  int userActionCount = 0;
  int characterActionCount = 0;

  @override
  Future<GameResult<GameSession>> initializeSession(
    GameSession session,
  ) async => GameResult.success(session);

  @override
  Future<GameResult<List<GameEvent>>> handleUserAction(
    GameSession session,
    GameAction action,
  ) async {
    userActionCount++;
    return GameResult.success([
      GameEvent(
        type: GameEventType.messageAdded,
        message: GameMessage(
          id: 'user-action-message-$userActionCount',
          sessionId: session.sessionId,
          senderId: 'user',
          type: GameMessageType.question,
          content: '用户动作已保存',
        ),
      ),
    ]);
  }

  @override
  Future<GameResult<List<GameEvent>>> handleCharacterAction(
    GameSession session,
    GameAction action,
  ) async {
    characterActionCount++;
    return GameResult.success([
      GameEvent(
        type: GameEventType.messageAdded,
        message: GameMessage(
          id: 'character-agent-message',
          sessionId: session.sessionId,
          senderId: action.actorParticipantId,
          type: GameMessageType.participant,
          content: action.payload['text']?.toString() ?? '',
        ),
      ),
    ]);
  }

  @override
  Future<GameResult<List<GameEvent>>> startGame(GameSession session) async =>
      GameResult.success(const []);
  @override
  Future<GameResult<List<GameEvent>>> advance(GameSession session) async =>
      GameResult.success(const []);
  @override
  Future<GameResult<List<GameEvent>>> pause(GameSession session) async =>
      GameResult.success(const []);
  @override
  Future<GameResult<List<GameEvent>>> resume(GameSession session) async =>
      GameResult.success(const []);
  @override
  Future<GameResult<List<GameEvent>>> finish(GameSession session) async =>
      GameResult.success(const []);
  @override
  Future<GameResult<GameSession>> restore(GameSession session) async =>
      GameResult.success(session);
}

class _FinishingParticipationEngine extends _ParticipationEngine {
  @override
  Future<GameResult<List<GameEvent>>> handleCharacterAction(
    GameSession session,
    GameAction action,
  ) async {
    characterActionCount++;
    final current = session.gameState as TurtleSoupState;
    return GameResult.success([
      GameEvent(
        type: GameEventType.messageAdded,
        message: GameMessage(
          sessionId: session.sessionId,
          senderId: action.actorParticipantId,
          type: GameMessageType.guess,
          content: '猜中真相',
        ),
      ),
      GameEvent(
        type: GameEventType.gameFinished,
        state: current.copyWith(
          phase: TurtleSoupPhase.finished,
          isSolved: true,
        ),
      ),
    ]);
  }
}

class _LifecycleAgent implements CharacterGameAgent {
  final Completer<CharacterGameAction> _completer = Completer();
  int callCount = 0;

  @override
  Future<CharacterGameAction> decide(CharacterGameAgentRequest request) {
    callCount++;
    return _completer.future;
  }

  void complete(CharacterGameAction action) => _completer.complete(action);
}

class _QueuedTurnAgent implements CharacterGameAgent {
  final List<Completer<CharacterGameAction>> _pending = [];
  final List<CharacterGameAgentRequest> _requests = [];

  @override
  Future<CharacterGameAction> decide(CharacterGameAgentRequest request) {
    _requests.add(request);
    final completer = Completer<CharacterGameAction>();
    _pending.add(completer);
    return completer.future;
  }

  void completeNext(CharacterGameActionType type) {
    final completer = _pending.removeAt(0);
    final request = _requests.removeAt(0);
    completer.complete(
      CharacterGameAction(
        actorParticipantId: request.actorParticipantId,
        type: type,
        content: type == CharacterGameActionType.pass ? '' : '有效推进',
      ),
    );
  }
}

class _FailingTurnAgent implements CharacterGameAgent {
  @override
  Future<CharacterGameAction> decide(CharacterGameAgentRequest request) =>
      Future.error(StateError('agent failed'));
}

class _InterruptibleAgent implements CharacterGameAgent {
  final Completer<CharacterGameAction> _first = Completer();
  int callCount = 0;

  @override
  Future<CharacterGameAction> decide(CharacterGameAgentRequest request) {
    callCount++;
    if (callCount == 1) return _first.future;
    return Future.value(
      CharacterGameAction(
        actorParticipantId: request.actorParticipantId,
        type: CharacterGameActionType.pass,
      ),
    );
  }

  void releaseFirst() {
    _first.complete(
      const CharacterGameAction(
        actorParticipantId: 'character:c1',
        type: CharacterGameActionType.react,
        content: '旧轮次结果',
      ),
    );
  }
}

class _MemoryPlatformStorage implements PlatformStorage {
  final Map<String, List<int>> _values = {};

  @override
  String reference(String key) => key;

  @override
  Future<bool> exists(String key) async => _values.containsKey(key);

  @override
  Future<String> readText(String key) async =>
      String.fromCharCodes(_values[key]!);

  @override
  Future<Uint8List> readBytes(String key) async =>
      Uint8List.fromList(_values[key]!);

  @override
  Future<void> writeText(String key, String value) async {
    _values[key] = value.codeUnits;
  }

  @override
  Future<void> writeBytes(String key, Uint8List value) async {
    _values[key] = value.toList();
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

class _BubbleEngine implements GameEngine<TurtleSoupState> {
  const _BubbleEngine(this.messages, {this.onUserAction});
  final List<GameMessage> messages;
  final void Function(GameAction action)? onUserAction;

  @override
  Future<GameResult<GameSession>> initializeSession(
    GameSession session,
  ) async => GameResult.success(session);

  @override
  Future<GameResult<List<GameEvent>>> startGame(GameSession session) async =>
      GameResult.success([
        GameEvent(type: GameEventType.sessionStarted, state: session.gameState),
        ...messages.map(
          (message) =>
              GameEvent(type: GameEventType.messageAdded, message: message),
        ),
      ]);

  @override
  Future<GameResult<List<GameEvent>>> handleUserAction(
    GameSession session,
    GameAction action,
  ) async {
    onUserAction?.call(action);
    return GameResult.success(const []);
  }

  @override
  Future<GameResult<List<GameEvent>>> handleCharacterAction(
    GameSession session,
    GameAction action,
  ) async => GameResult.success(const []);
  @override
  Future<GameResult<List<GameEvent>>> advance(GameSession session) async =>
      GameResult.success(const []);
  @override
  Future<GameResult<List<GameEvent>>> pause(GameSession session) async =>
      GameResult.success(const []);
  @override
  Future<GameResult<List<GameEvent>>> resume(GameSession session) async =>
      GameResult.success(const []);
  @override
  Future<GameResult<List<GameEvent>>> finish(GameSession session) async =>
      GameResult.success(const []);
  @override
  Future<GameResult<GameSession>> restore(GameSession session) async =>
      GameResult.success(session);
}

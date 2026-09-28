import 'dart:async';

import 'package:flutter/material.dart';
import '../../../services/usage_timer_service.dart';

import '../../../games/engines/game_engine.dart';
import '../../../games/hosting/character_host_agent.dart';
import '../../../games/hosting/real_character_host_response_renderer.dart';
import '../../../games/models/game_models.dart';
import '../../../games/participation/character_game_action.dart';
import '../../../games/participation/character_participation_director.dart';
import '../../../games/participation/real_character_game_agent.dart';
import '../../../games/presentation/game_timeline_sender_resolver.dart';
import '../../../games/registry/mini_game_registry.dart';
import '../../../games/services/game_action_pipeline.dart';
import '../../../games/services/game_room_visibility.dart';
import '../../../games/services/game_participant_factory.dart';
import '../../../games/storage/game_session_storage_service.dart';
import '../../../games/turtle_soup/turtle_soup_engine.dart';
import '../../../games/turtle_soup/turtle_soup_models.dart';
import '../../../games/turtle_soup/turtle_soup_character_agent_view_builder.dart';
import '../../../games/turtle_soup/turtle_soup_character_participation_adapter.dart';
import '../../../games/turtle_soup/turtle_soup_semantic_judge.dart';
import '../../../games/turtle_soup/turtle_soup_public_summary.dart';
import '../../../models/ai_character.dart';
import '../../../services/character_registry_service.dart';
import '../../../widgets/theme/peilink_theme_chrome.dart';
import 'game_room_presentation.dart';
import 'game_room_shell.dart';

class GameRoomPage extends StatefulWidget {
  const GameRoomPage({
    super.key,
    required this.session,
    required this.storage,
    this.hostRenderer,
    this.hostIdentityLoader,
    this.characterLoader,
    this.engine,
    this.participationDirector,
    this.semanticJudge,
    this.summaryService,
    this.bubbleDuration = const Duration(seconds: 4),
  });
  final GameSession session;
  final GameSessionStorageService storage;
  final CharacterHostResponseRenderer? hostRenderer;
  final CharacterHostIdentityLoader? hostIdentityLoader;
  final Future<List<AiCharacter>> Function()? characterLoader;
  final GameEngine<dynamic>? engine;
  final CharacterParticipationDirector? participationDirector;
  final TurtleSoupSemanticJudge? semanticJudge;
  final TurtleSoupPublicSummaryService? summaryService;
  final Duration bubbleDuration;

  @override
  State<GameRoomPage> createState() => _GameRoomPageState();
}

class _GameRoomPageState extends State<GameRoomPage> with RouteAware {
  late GameSession _session = widget.session;
  late final GameDefinition _definition = MiniGameRegistry.instance.definition(
    _session.gameId,
  );
  late final GameEngine<dynamic> _engine =
      widget.engine ??
      (_session.gameId == MiniGameRegistry.turtleSoupId
          ? TurtleSoupEngine(
              hostRenderer:
                  widget.hostRenderer ??
                  (_session.host.type == GameHostType.characterHost
                      ? DeferredCharacterHostResponseRenderer(
                          delegate: createProductionCharacterHostRenderer(
                            identityLoader: widget.hostIdentityLoader,
                          ),
                          onRendered: _applyDeferredHostResponse,
                          epochProvider: () => _actions.epoch,
                        )
                      : null),
              hostIdentityLoader:
                  widget.hostIdentityLoader ??
                  const SafeCharacterHostIdentityLoader().call,
              semanticJudge:
                  widget.semanticJudge ?? ModelTurtleSoupSemanticJudge(),
            )
          : _definition.engineFactory());
  late final GameRoomPresentation? _presentation =
      GameRoomPresentationRegistry.resolve(_session.gameId);
  late final CharacterParticipationDirector? _participationDirector =
      widget.participationDirector ?? _createProductionDirector();
  late final TurtleSoupPublicSummaryService _summaryService =
      widget.summaryService ?? TurtleSoupPublicSummaryService();
  List<AiCharacter> _characters = const [];
  GameHostVisual _hostVisual = const GameHostVisual(
    name: '系统主持人',
    isSystem: true,
  );
  bool _loading = true;
  final GameActionPipeline _actions = GameActionPipeline();
  int _activeRounds = 0;
  String? _currentThinkingParticipantId;
  String? _manualRoundFeedback;
  Timer? _manualRoundFeedbackTimer;
  bool _summaryLoading = false;
  int _summaryRequestEpoch = 0;
  final Completer<void> _initialSaveDone = Completer<void>();
  final GlobalKey<GameTimelinePanelState> _timelineKey = GlobalKey();
  Future<void> _saveTail = Future<void>.value();

  @override
  void initState() {
    super.initState();
    // Route visibility handled by RouteAware
    _initialize();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final route = ModalRoute.of(context);
      if (route != null) {
        UsageTimerService.instance.routeObserver.subscribe(this, route);
      }
    });
  }

  @override
  void didUpdateWidget(GameRoomPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session.sessionId != widget.session.sessionId) {
      _clearThinkingParticipant(notify: false);
      _invalidateSummaryRequest(notify: false);
      _clearManualRoundFeedback(notify: false);
    }
  }

  @override
  @override
  void didPush() => UsageTimerService.instance.onInteractiveRouteVisible();

  @override
  void didPopNext() => UsageTimerService.instance.onInteractiveRouteVisible();

  @override
  void didPushNext() => UsageTimerService.instance.onInteractiveRouteHidden();

  @override
  void didPop() => UsageTimerService.instance.onInteractiveRouteHidden();

  @override
  void dispose() {
    _actions.dispose();
    _summaryRequestEpoch++;
    _manualRoundFeedbackTimer?.cancel();
    // Route visibility handled by RouteAware
    super.dispose();
  }

  Future<void> _initialize() async {
    final result = await _engine.initializeSession(_session);
    if (result.isSuccess && result.value != null) {
      _session = result.value!;
    }
    _hostVisual = _resolveHostVisual();
    if (mounted) setState(() => _loading = false);
    try {
      await _loadCharacters();
      await _persistSession();
    } finally {
      if (!_initialSaveDone.isCompleted) _initialSaveDone.complete();
    }
  }

  Future<void> _loadCharacters() async {
    try {
      _characters =
          await (widget.characterLoader?.call() ??
              CharacterRegistryService().loadCharacters());
    } catch (_) {
      _characters = const [];
    }
    _hostVisual = _resolveHostVisual();
    if (mounted) setState(() {});
  }

  GameHostVisual _resolveHostVisual() {
    if (_session.host.type == GameHostType.systemHost) {
      return const GameHostVisual(name: '系统主持人', isSystem: true);
    }
    final id = _session.host.characterId;
    final participant = _session.participants
        .where((item) => item.characterId == id)
        .firstOrNull;
    final character = _characters.where((item) => item.id == id).firstOrNull;
    return GameHostVisual(
      name: character?.displayName ?? participant?.displayName ?? '角色主持人',
      avatarPath:
          character?.effectiveSocialAvatarPath ??
          participant?.avatarReference ??
          '',
      isParticipant: participant != null,
      participantId: participant?.participantId,
    );
  }

  String _resolveParticipantName(String participantId) {
    final participant = _session.participants
        .where((item) => item.participantId == participantId)
        .firstOrNull;
    if (participant?.type == GameParticipantType.user) return '我';
    final character = _characters
        .where((item) => item.id == participant?.characterId)
        .firstOrNull;
    return character?.displayName ?? participant?.displayName ?? '角色玩家';
  }

  Future<bool> _apply(
    GameResult<List<GameEvent>> result, {
    bool persist = true,
  }) async {
    if (!result.isSuccess) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.message.isEmpty ? '操作没有完成。' : result.message),
          ),
        );
      }
      return false;
    }
    var state = _session.gameState;
    var status = _session.status;
    final messages = [..._session.messages];
    for (final event in result.value ?? const <GameEvent>[]) {
      if (event.state != null) state = event.state!;
      if (event.message != null) {
        messages.add(event.message!);
      }
      if (event.type == GameEventType.sessionStarted) {
        status = GameSessionStatus.playing;
      }
      if (event.type == GameEventType.gameFinished) {
        status = GameSessionStatus.finished;
      }
    }
    _session = _session.copyWith(
      status: status,
      gameState: state,
      messages: messages,
    );
    if (status == GameSessionStatus.finished ||
        messages.any((message) => message.type == GameMessageType.reveal)) {
      _clearManualRoundFeedback(notify: false);
      _clearThinkingParticipant(notify: false);
    }
    if (mounted) setState(() {});
    if (persist) await _persistSession();
    return true;
  }

  Future<void> _persistSession() {
    final snapshot = _session;
    _saveTail = _saveTail
        .catchError((_) {})
        .then((_) async => widget.storage.save(snapshot));
    return _saveTail;
  }

  Future<void> _applyDeferredHostResponse(
    CharacterHostRenderRequest request,
    String text,
    int epoch,
  ) async {
    if (!mounted ||
        request.sessionId != _session.sessionId ||
        !_actions.accepts(epoch)) {
      return;
    }
    if (_session.status == GameSessionStatus.finished &&
        !{
          GameHostSemanticType.guessCorrect,
          GameHostSemanticType.reveal,
        }.contains(request.view.semanticResult.type)) {
      return;
    }
    final index = _session.messages.indexWhere(
      (message) => message.id == request.responseMessageId,
    );
    if (index < 0) return;
    final original = _session.messages[index];
    final replacement = GameMessage(
      id: original.id,
      sessionId: original.sessionId,
      senderId: original.senderId,
      type: original.type,
      content: text,
      createdAt: original.createdAt,
      visibility: original.visibility,
      visibleToParticipantId: original.visibleToParticipantId,
    );
    final messages = [..._session.messages]..[index] = replacement;
    _session = _session.copyWith(messages: messages);
    setState(() {});
    await _persistSession();
  }

  /// User Action 与 Character Round 共用同一条串行 Action pipeline：
  /// Judge 引入了异步 Engine 路径，Action 必须保持提交顺序，旧 epoch 的结果
  /// 不能在换题或离开房间后写回。
  Future<void> _handleUserAction(GameAction action) {
    _actions.invalidate();
    _clearThinkingParticipant();
    _invalidateSummaryRequest();
    _clearManualRoundFeedback();
    final sessionId = _session.sessionId;
    return _actions.enqueue(() async {
      if (!mounted || _session.sessionId != sessionId) return;
      final epoch = _actions.begin();
      final result = await _engine.handleUserAction(_session, action);
      if (!mounted ||
          _session.sessionId != sessionId ||
          !_actions.accepts(epoch)) {
        return;
      }
      final applied = await _apply(result, persist: false);
      if (!applied) return;
      await _initialSaveDone.future;
      await _persistSession();
      final director = _participationDirector;
      if (director == null || !_actions.accepts(epoch)) return;
      unawaited(_runParticipationRound(director, action, sessionId, epoch));
    });
  }

  Future<void> _handlePlayAgain() async {
    _clearThinkingParticipant();
    final engine = _engine;
    if (engine is! TurtleSoupEngine) return;
    final result = await engine.playAgain(_session);
    if (!result.isSuccess || result.value == null || !mounted) return;
    _invalidateSummaryRequest(notify: false);
    _clearManualRoundFeedback(notify: false);
    _actions.invalidate();
    _session = result.value!;
    setState(() {});
    await _persistSession();
  }

  Future<void> _runParticipationRound(
    CharacterParticipationDirector director,
    GameAction? trigger,
    String sessionId,
    int epoch, {
    bool manual = false,
  }) async {
    setState(() => _activeRounds++);
    var completed = false;
    var submittedCharacterAction = false;
    try {
      var round = director.startRound(_session);
      while (!round.isComplete) {
        if (!_acceptParticipationResult(sessionId, epoch) ||
            _characterRoundShouldStop) {
          return;
        }
        final participantId = round.currentParticipantId;
        if (participantId == null) break;
        _setThinkingParticipant(participantId);
        CharacterParticipationDecision decision;
        try {
          decision = await director.offerTurn(
            session: _session,
            trigger: trigger,
            round: round,
          );
        } finally {
          _clearThinkingParticipant(participantId: participantId);
        }
        round = round.advance();
        if (!_acceptParticipationResult(sessionId, epoch)) return;
        final characterAction = decision.action;
        if (characterAction == null ||
            characterAction.type == CharacterGameActionType.pass) {
          continue;
        }
        final result = await _engine.handleCharacterAction(
          _session,
          characterAction.toEngineAction(),
        );
        if (!_acceptParticipationResult(sessionId, epoch)) return;
        if (!result.isSuccess) continue;
        final applied = await _apply(result);
        if (applied) submittedCharacterAction = true;
        if (!_acceptParticipationResult(sessionId, epoch) ||
            _characterRoundShouldStop) {
          return;
        }
      }
      completed = true;
    } catch (_) {
      // User action was already applied and persisted. AI failure is a pass.
    } finally {
      if (mounted) {
        _clearThinkingParticipant(notify: false);
        setState(() => _activeRounds--);
        if (manual && completed && !submittedCharacterAction) {
          _showManualRoundFeedback();
        }
      }
    }
  }

  /// 「让他们继续」：User 本轮不提交 Question/Guess，只触发一次现有 Character Round。
  /// 不增加 questionCount/guessCount/hintCount，不写 User Timeline，不调 Judge/Host。
  /// 一轮结束后停止，重新等待 User；User 可再次点击启动新的一轮。
  Future<void> _onLetThemContinue() async {
    final director = _participationDirector;
    if (director == null) return;
    if (_session.status != GameSessionStatus.playing) return;
    if (_session.gameState is! TurtleSoupState) return;
    final state = _session.gameState as TurtleSoupState;
    if (state.phase != TurtleSoupPhase.questioning) return;
    if (_activeRounds > 0) return;
    _invalidateSummaryRequest();
    _clearManualRoundFeedback();
    final sessionId = _session.sessionId;
    await _actions.enqueue(() async {
      if (!mounted || _session.sessionId != sessionId) return;
      final epoch = _actions.begin();
      // 明确的"无 User Action 触发"路径：不构造 fake/custom GameAction，
      // trigger 传 null。Director 当前不读取 trigger，此处仅作语义占位。
      unawaited(
        _runParticipationRound(director, null, sessionId, epoch, manual: true),
      );
    });
  }

  void _showManualRoundFeedback() {
    _manualRoundFeedbackTimer?.cancel();
    if (!mounted || _characterRoundShouldStop) return;
    setState(() => _manualRoundFeedback = '大家暂时没有新的思路');
    _manualRoundFeedbackTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      setState(() => _manualRoundFeedback = null);
    });
  }

  void _clearManualRoundFeedback({bool notify = true}) {
    _manualRoundFeedbackTimer?.cancel();
    _manualRoundFeedbackTimer = null;
    if (_manualRoundFeedback == null) return;
    _manualRoundFeedback = null;
    if (notify && mounted) setState(() {});
  }

  void _setThinkingParticipant(String participantId) {
    if (!mounted || _currentThinkingParticipantId == participantId) return;
    setState(() => _currentThinkingParticipantId = participantId);
  }

  void _clearThinkingParticipant({String? participantId, bool notify = true}) {
    if (_currentThinkingParticipantId == null ||
        (participantId != null &&
            _currentThinkingParticipantId != participantId)) {
      return;
    }
    _currentThinkingParticipantId = null;
    if (notify && mounted) setState(() {});
  }

  Future<void> _onSummarizePublicKnowledge() async {
    if (_summaryLoading || _activeRounds > 0) return;
    if (_session.status != GameSessionStatus.playing ||
        _session.gameState is! TurtleSoupState) {
      return;
    }
    final state = _session.gameState as TurtleSoupState;
    if (state.phase != TurtleSoupPhase.questioning) return;
    final sessionId = _session.sessionId;
    final requestEpoch = ++_summaryRequestEpoch;
    final view = const TurtleSoupPublicSummaryViewBuilder().build(_session);
    setState(() => _summaryLoading = true);
    final summary = await _summaryService.summarize(view);
    if (!mounted ||
        _session.sessionId != sessionId ||
        requestEpoch != _summaryRequestEpoch) {
      return;
    }
    setState(() => _summaryLoading = false);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => TurtleSoupPublicSummarySheet(summary: summary),
    );
  }

  void _invalidateSummaryRequest({bool notify = true}) {
    _summaryRequestEpoch++;
    if (!_summaryLoading) return;
    _summaryLoading = false;
    if (notify && mounted) setState(() {});
  }

  bool _acceptParticipationResult(String sessionId, int epoch) =>
      mounted && _session.sessionId == sessionId && _actions.accepts(epoch);

  bool get _characterRoundShouldStop =>
      _session.status != GameSessionStatus.playing ||
      _session.messages.any(
        (message) => message.type == GameMessageType.reveal,
      );

  CharacterParticipationDirector? _createProductionDirector() {
    if (_session.gameId != MiniGameRegistry.turtleSoupId) return null;
    return CharacterParticipationDirector(
      agent: RealCharacterGameAgent(),
      legality: const TurtleSoupCharacterParticipationAdapter(),
      viewBuilder: const TurtleSoupCharacterAgentViewBuilder(),
    );
  }

  Future<void> _setPaused(bool paused) async {
    final result = paused
        ? await _engine.pause(_session)
        : await _engine.resume(_session);
    if (!result.isSuccess) return;
    _session = _session.copyWith(
      status: paused ? GameSessionStatus.paused : GameSessionStatus.playing,
    );
    if (mounted) setState(() {});
    await widget.storage.save(_session);
  }

  Future<void> _manageParticipants() async {
    if (!{
      GameSessionStatus.draft,
      GameSessionStatus.ready,
    }.contains(_session.status)) {
      return;
    }
    final selected = _session.participants
        .where((item) => item.type == GameParticipantType.character)
        .map((item) => item.characterId)
        .whereType<String>()
        .toSet();
    final userCount = _session.participants
        .where((item) => item.type == GameParticipantType.user)
        .length;
    final capacity = _definition.maxPlayers > userCount
        ? _definition.maxPlayers - userCount
        : 0;
    final result = await showDialog<Set<String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('邀请角色'),
          content: SizedBox(
            width: double.maxFinite,
            child: _characters.isEmpty
                ? const Text('还没有可加入的角色，先创建一个角色吧。')
                : ListView(
                    shrinkWrap: true,
                    children: _characters.map((character) {
                      final checked = selected.contains(character.id);
                      return CheckboxListTile(
                        value: checked,
                        title: Text(character.displayName),
                        onChanged: (value) => setDialogState(() {
                          if (value == true && selected.length < capacity) {
                            selected.add(character.id);
                          } else if (value != true) {
                            selected.remove(character.id);
                          }
                        }),
                      );
                    }).toList(),
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, selected),
              child: const Text('完成'),
            ),
          ],
        ),
      ),
    );
    if (result == null) return;
    final retained = _session.participants.where(
      (item) => item.type != GameParticipantType.character,
    );
    _session = _session.copyWith(
      participants: [
        ...retained,
        ..._characters
            .where((item) => result.contains(item.id))
            .map(GameParticipantFactory.character),
      ],
    );
    _hostVisual = _resolveHostVisual();
    if (mounted) setState(() {});
    await widget.storage.save(_session);
  }

  void _dismissKeyboardOutsideFocus(PointerDownEvent event) {
    final focus = FocusManager.instance.primaryFocus;
    if (focus == null || !focus.hasFocus) return;
    final renderObject = focus.context?.findRenderObject();
    if (renderObject is RenderBox && renderObject.attached) {
      final localPosition = renderObject.globalToLocal(event.position);
      if ((Offset.zero & renderObject.size).contains(localPosition)) return;
    }
    focus.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return PeiLinkThemeScaffold(
        body: const Scaffold(
          backgroundColor: Colors.transparent,
          body: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    final presentation = _presentation;
    if (presentation == null) {
      return PeiLinkThemeScaffold(
        body: Scaffold(
          backgroundColor: Colors.transparent,
          body: const Center(child: Text('游戏展示模块还在准备中。')),
        ),
      );
    }
    final visibleMessages = GameRoomVisibility.visibleMessages(_session);
    final paused = _session.status == GameSessionStatus.paused;
    return PeiLinkThemeScaffold(
      body: Scaffold(
        key: const ValueKey('game-room-shell'),
        backgroundColor: Colors.transparent,
        resizeToAvoidBottomInset: false,
        body: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: _dismissKeyboardOutsideFocus,
          child: GameRoomShell(
            definition: _definition,
            session: _session,
            host: _hostVisual,
            visibleMessages: visibleMessages,
            timelineSenderResolver: GameTimelineSenderResolver(
              session: _session,
              characters: _characters,
            ),
            timelineKey: _timelineKey,
            onBack: () => Navigator.pop(context),
            onPauseChanged: _setPaused,
            onInvite: _manageParticipants,
            thinkingParticipantId: _currentThinkingParticipantId,
            gameInfo: paused
                ? Center(
                    child: FilledButton.icon(
                      key: const ValueKey('game-room-resume'),
                      onPressed: () => _setPaused(false),
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text('继续游戏'),
                    ),
                  )
                : presentation.buildGameInfo(
                    context,
                    _session,
                    participantNameResolver: _resolveParticipantName,
                  ),
            actionArea: paused
                ? const SizedBox(height: 10)
                : presentation.buildActionArea(
                    context,
                    _session,
                    onStart: () async {
                      await _apply(await _engine.startGame(_session));
                    },
                    onAction: _handleUserAction,
                    onPlayAgain: _handlePlayAgain,
                    onViewRecord: () =>
                        _timelineKey.currentState?.openExpanded(),
                    onLetThemContinue: _onLetThemContinue,
                    characterRoundRunning: _activeRounds > 0,
                    manualRoundFeedback: _manualRoundFeedback,
                    onSummarize: _onSummarizePublicKnowledge,
                    summaryLoading: _summaryLoading,
                  ),
          ),
        ),
      ),
    );
  }
}

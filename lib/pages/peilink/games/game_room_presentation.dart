import 'dart:async';

import 'package:flutter/material.dart';

import '../../../games/models/game_models.dart';
import '../../../games/registry/mini_game_registry.dart';
import '../../../games/services/game_room_draft_store.dart';
import '../../../games/turtle_soup/turtle_soup_models.dart';
import '../../../games/turtle_soup/turtle_soup_puzzle_registry.dart';
import '../../../games/turtle_soup/turtle_soup_public_summary.dart';
import '../../../services/api_settings_storage_service.dart';
import '../../../services/third_party_consent_service.dart';

typedef GameStartCallback = Future<void> Function();
typedef GameActionCallback = Future<void> Function(GameAction action);
typedef GameFlowCallback = Future<void> Function();

abstract interface class GameRoomPresentation {
  /// Builds the compact, game-specific information displayed below the
  /// generic room header. The shared shell owns the conversation stage.
  Widget buildGameInfo(
    BuildContext context,
    GameSession session, {
    String Function(String participantId)? participantNameResolver,
  });
  Widget buildActionArea(
    BuildContext context,
    GameSession session, {
    required GameStartCallback onStart,
    required GameActionCallback onAction,
    required GameFlowCallback onPlayAgain,
    required VoidCallback onViewRecord,
    VoidCallback? onLetThemContinue,
    bool characterRoundRunning = false,
    String? manualRoundFeedback,
    Future<void> Function()? onSummarize,
    bool summaryLoading = false,
  });
}

class GameRoomPresentationRegistry {
  const GameRoomPresentationRegistry._();

  static GameRoomPresentation? resolve(String gameId) => switch (gameId) {
    MiniGameRegistry.turtleSoupId => const TurtleSoupRoomPresentation(),
    _ => null,
  };
}

class TurtleSoupRoomPresentation implements GameRoomPresentation {
  const TurtleSoupRoomPresentation();

  @override
  Widget buildGameInfo(
    BuildContext context,
    GameSession session, {
    String Function(String participantId)? participantNameResolver,
  }) => TurtleSoupGameInfoCard(
    session: session,
    participantNameResolver: participantNameResolver,
  );

  @override
  Widget buildActionArea(
    BuildContext context,
    GameSession session, {
    required GameStartCallback onStart,
    required GameActionCallback onAction,
    required GameFlowCallback onPlayAgain,
    required VoidCallback onViewRecord,
    VoidCallback? onLetThemContinue,
    bool characterRoundRunning = false,
    String? manualRoundFeedback,
    Future<void> Function()? onSummarize,
    bool summaryLoading = false,
  }) => TurtleSoupActionPanel(
    session: session,
    onStart: onStart,
    onAction: onAction,
    onPlayAgain: onPlayAgain,
    onViewRecord: onViewRecord,
    onLetThemContinue: onLetThemContinue,
    characterRoundRunning: characterRoundRunning,
    manualRoundFeedback: manualRoundFeedback,
    onSummarize: onSummarize,
    summaryLoading: summaryLoading,
  );
}

class TurtleSoupGameInfoCard extends StatelessWidget {
  const TurtleSoupGameInfoCard({
    super.key,
    required this.session,
    this.participantNameResolver,
  });
  final GameSession session;
  final String Function(String participantId)? participantNameResolver;

  @override
  Widget build(BuildContext context) {
    final state = session.gameState as TurtleSoupState;
    final ended = {
      TurtleSoupPhase.revealed,
      TurtleSoupPhase.finished,
    }.contains(state.phase);
    final puzzle = TurtleSoupPuzzleRegistry.byId(state.puzzleId);
    final difficulty = _difficultyLabel(puzzle.difficulty);
    final solver = state.solvedByParticipantId == null
        ? null
        : session.participants
              .where(
                (participant) =>
                    participant.participantId == state.solvedByParticipantId,
              )
              .firstOrNull;
    final resolvedSolverName = state.solvedByParticipantId == null
        ? null
        : participantNameResolver?.call(state.solvedByParticipantId!);
    final solverName = solver?.type == GameParticipantType.user
        ? '我'
        : (resolvedSolverName?.trim().isNotEmpty ?? false)
        ? resolvedSolverName!
        : (solver?.displayName.trim().isNotEmpty ?? false)
        ? solver!.displayName
        : '角色玩家';
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
      child: Material(
        key: const ValueKey('game-info-card'),
        color: Colors.white.withValues(alpha: .82),
        borderRadius: BorderRadius.circular(16),
        child: ExpansionTile(
          key: const ValueKey('game-info-expand'),
          tilePadding: const EdgeInsets.fromLTRB(14, 4, 8, 4),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  state.title,
                  key: const ValueKey('turtle-soup-puzzle-title'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                difficulty,
                style: const TextStyle(fontSize: 11, color: Color(0xFF6E6880)),
              ),
            ],
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),
              Text(
                state.surface,
                key: const ValueKey('turtle-soup-puzzle-card'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12.5, height: 1.35),
              ),
              const SizedBox(height: 5),
              Text(
                '提问 ${state.questionCount}   猜测 ${state.guessCount}   提示 ${state.usedHintCount}/${state.hints.length}',
                key: const ValueKey('turtle-soup-stats'),
                style: const TextStyle(
                  fontSize: 10.5,
                  color: Color(0xFF68758A),
                ),
              ),
            ],
          ),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                state.surface,
                style: const TextStyle(fontSize: 13.5, height: 1.5),
              ),
            ),
            if (ended) ...[
              const Divider(height: 20),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '${state.isSolved ? '破汤成功' : '主动揭晓'}：${state.truth}',
                  key: const ValueKey('turtle-soup-truth'),
                  style: const TextStyle(
                    fontSize: 13.5,
                    height: 1.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (state.isSolved)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '破汤者：$solverName',
                    key: const ValueKey('turtle-soup-solver'),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  static String _difficultyLabel(TurtleSoupDifficulty difficulty) =>
      switch (difficulty) {
        TurtleSoupDifficulty.easy => '简单',
        TurtleSoupDifficulty.normal => '普通',
        TurtleSoupDifficulty.hard => '困难',
      };
}

class TurtleSoupActionPanel extends StatefulWidget {
  const TurtleSoupActionPanel({
    super.key,
    required this.session,
    required this.onStart,
    required this.onAction,
    required this.onPlayAgain,
    required this.onViewRecord,
    this.onLetThemContinue,
    this.characterRoundRunning = false,
    this.manualRoundFeedback,
    this.onSummarize,
    this.summaryLoading = false,
    this.draftStore,
  });
  final GameSession session;
  final GameStartCallback onStart;
  final GameActionCallback onAction;
  final GameFlowCallback onPlayAgain;
  final VoidCallback onViewRecord;

  /// User 主动跳过本轮、只触发一次现有 Character Round；null 表示不展示按钮。
  final VoidCallback? onLetThemContinue;

  /// 是否有 Character Round 正在运行（按钮 disabled）。
  final bool characterRoundRunning;

  /// 当前页面生命周期内的 Manual Round 轻量反馈；不进入任何游戏数据。
  final String? manualRoundFeedback;
  final Future<void> Function()? onSummarize;
  final bool summaryLoading;

  /// 未发送输入框草稿的持久化存储；测试可注入。
  final GameRoomDraftStore? draftStore;

  @override
  State<TurtleSoupActionPanel> createState() => _TurtleSoupActionPanelState();
}

class _TurtleSoupActionPanelState extends State<TurtleSoupActionPanel> {
  final _controller = TextEditingController();
  bool _guessMode = false;
  bool _sending = false;
  late final GameRoomDraftStore _draftStore =
      widget.draftStore ?? GameRoomDraftStore();

  TurtleSoupState get _state => widget.session.gameState as TurtleSoupState;
  String get _actor => widget.session.participants
      .firstWhere((item) => item.type == GameParticipantType.user)
      .participantId;

  @override
  void initState() {
    super.initState();
    _restoreDraft();
  }

  @override
  void didUpdateWidget(TurtleSoupActionPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Play Again / 换题：messages 被清空，视为新局开始，清掉上一局草稿。
    final wasPlaying = oldWidget.session.messages.isNotEmpty;
    final isNewRound = widget.session.messages.isEmpty;
    if (wasPlaying &&
        isNewRound &&
        widget.session.sessionId == oldWidget.session.sessionId) {
      _controller.clear();
      unawaited(_draftStore.clear(widget.session.sessionId));
    }
  }

  Future<void> _restoreDraft() async {
    final draft = await _draftStore.load(widget.session.sessionId);
    if (!mounted || draft.isEmpty) return;
    _controller
      ..text = draft
      ..selection = TextSelection.collapsed(offset: draft.length);
  }

  Future<void> _persistDraft(String text) =>
      _draftStore.save(widget.session.sessionId, text);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send(String kind, {String? text}) async {
    if (_sending) return;
    setState(() => _sending = true);
    final payload = <String, dynamic>{'kind': kind};
    // Third-party consent for game AI
    final apiSettings = await ApiSettingsStorageService().loadSettings();
    if (!mounted) return;
    final agreed = await ThirdPartyConsentService.instance.requestConsentIfNeeded(
      context,
      apiSettings.provider,
      apiSettings.baseUrl,
      ConsentPurpose.chat,
    );
    if (!agreed) {
      if (mounted) setState(() => _sending = false);
      return;
    }
    if (text != null) payload['text'] = text;
    await widget.onAction(
      GameAction(
        type: GameActionType.custom,
        actorParticipantId: _actor,
        payload: payload,
      ),
    );
    if (kind == 'question' || kind == 'guess') {
      _controller.clear();
      unawaited(_draftStore.clear(widget.session.sessionId));
    }
    if (mounted) setState(() => _sending = false);
  }

  @override
  Widget build(BuildContext context) {
    final ended = {
      TurtleSoupPhase.revealed,
      TurtleSoupPhase.finished,
    }.contains(_state.phase);
    if (_state.phase == TurtleSoupPhase.ready) {
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: const ValueKey('game-room-start'),
              onPressed: widget.onStart,
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('开始推理'),
            ),
          ),
        ),
      );
    }
    if (ended) {
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            key: const ValueKey('turtle-soup-finished'),
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  key: const ValueKey('turtle-soup-view-record'),
                  onPressed: widget.onViewRecord,
                  icon: const Icon(Icons.receipt_long_outlined),
                  label: const Text('查看游戏记录'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  key: const ValueKey('turtle-soup-play-again'),
                  onPressed: widget.onPlayAgain,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('再来一局'),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return SafeArea(
      top: false,
      child: Container(
        key: const ValueKey('game-action-area'),
        padding: const EdgeInsets.fromLTRB(10, 7, 10, 9),
        color: Colors.white.withValues(alpha: .72),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 4,
              runSpacing: 0,
              children: [
                ChoiceChip(
                  label: const Text('提问'),
                  selected: !_guessMode,
                  onSelected: (_) => setState(() => _guessMode = false),
                  visualDensity: VisualDensity.compact,
                ),
                ChoiceChip(
                  key: const ValueKey('turtle-soup-guess-mode'),
                  label: const Text('猜真相'),
                  selected: _guessMode,
                  onSelected: (_) => setState(() => _guessMode = true),
                  visualDensity: VisualDensity.compact,
                ),
                if (widget.onLetThemContinue != null) ...[
                  TextButton.icon(
                    key: const ValueKey('turtle-soup-let-them-continue'),
                    onPressed: widget.characterRoundRunning
                        ? null
                        : widget.onLetThemContinue,
                    icon: Icon(
                      widget.characterRoundRunning
                          ? Icons.hourglass_bottom_outlined
                          : Icons.groups_outlined,
                      size: 18,
                    ),
                    label: Text(
                      widget.characterRoundRunning ? '他们正在推理…' : '让他们继续',
                    ),
                  ),
                ],
                TextButton.icon(
                  key: const ValueKey('turtle-soup-summarize'),
                  onPressed:
                      widget.summaryLoading || widget.characterRoundRunning
                      ? null
                      : widget.onSummarize,
                  icon: Icon(
                    widget.summaryLoading
                        ? Icons.hourglass_top_rounded
                        : Icons.format_list_bulleted_rounded,
                    size: 18,
                  ),
                  label: Text(widget.summaryLoading ? '正在整理…' : '帮我捋捋'),
                ),
                TextButton.icon(
                  key: const ValueKey('turtle-soup-hint'),
                  onPressed:
                      _state.usedHintCount < _state.hints.length && !_sending
                      ? () => _send('hint')
                      : null,
                  icon: const Icon(Icons.lightbulb_outline, size: 18),
                  label: const Text('提示'),
                ),
                TextButton(
                  key: const ValueKey('turtle-soup-reveal'),
                  onPressed: _sending ? null : _confirmReveal,
                  child: const Text('揭晓'),
                ),
              ],
            ),
            if (widget.manualRoundFeedback != null)
              Container(
                key: const ValueKey('manual-round-feedback'),
                margin: const EdgeInsets.only(bottom: 4),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFEDEAF8),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  widget.manualRoundFeedback!,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF69627B),
                  ),
                ),
              ),
            Row(
              children: [
                TextButton.icon(
                  key: const ValueKey('turtle-soup-view-record'),
                  onPressed: widget.onViewRecord,
                  icon: const Icon(Icons.receipt_long_outlined, size: 17),
                  label: const Text('对局记录'),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: TextField(
                    key: const ValueKey('turtle-soup-input'),
                    controller: _controller,
                    maxLines: 2,
                    minLines: 1,
                    textInputAction: TextInputAction.send,
                    onChanged: _persistDraft,
                    onSubmitted: (_) => _send(
                      _guessMode ? 'guess' : 'question',
                      text: _controller.text,
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: _guessMode ? '说出完整推理…' : '输入问题…',
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: .86),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 7),
                IconButton.filled(
                  key: const ValueKey('turtle-soup-send'),
                  onPressed: _sending
                      ? null
                      : () => _send(
                          _guessMode ? 'guess' : 'question',
                          text: _controller.text,
                        ),
                  icon: const Icon(Icons.send_rounded),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmReveal() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确定要揭晓汤底吗？'),
        content: const Text('揭晓后本局将结束。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('继续游戏'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('揭晓谜底'),
          ),
        ],
      ),
    );
    if (confirmed == true) await _send('reveal');
  }
}

class TurtleSoupPublicSummarySheet extends StatelessWidget {
  const TurtleSoupPublicSummarySheet({super.key, required this.summary});

  final TurtleSoupPublicSummary summary;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Container(
      key: const ValueKey('turtle-soup-summary-sheet'),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .72,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFFF7F8FC),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFBBC2CE),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Center(
              child: Text(
                '帮我捋捋',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(height: 14),
            if (summary.fallbackMessage != null)
              Text(
                summary.fallbackMessage!,
                key: const ValueKey('turtle-soup-summary-fallback'),
                style: const TextStyle(fontSize: 14, height: 1.5),
              )
            else ...[
              _SummarySection(title: '目前已确认', items: summary.confirmed),
              _SummarySection(title: '目前已排除', items: summary.ruledOut),
              _SummarySection(title: '还没搞清楚', items: summary.unresolved),
            ],
          ],
        ),
      ),
    ),
  );
}

class _SummarySection extends StatelessWidget {
  const _SummarySection({required this.title, required this.items});

  final String title;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 5),
          ...items.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text('• $item', style: const TextStyle(height: 1.4)),
            ),
          ),
        ],
      ),
    );
  }
}

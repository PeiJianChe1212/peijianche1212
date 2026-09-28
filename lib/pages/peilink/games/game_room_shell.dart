import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../../widgets/ai_identity_badge.dart';

import '../../../games/models/game_models.dart';
import '../../../games/presentation/game_timeline_sender_resolver.dart';
import '../../../games/registry/mini_game_registry.dart';
import '../../../widgets/theme/peilink_theme_scope.dart';
import '../../../widgets/theme/peilink_themed_avatar.dart';

class GameHostVisual {
  const GameHostVisual({
    required this.name,
    this.avatarPath = '',
    this.isSystem = false,
    this.isParticipant = false,
    this.participantId,
  });
  final String name;
  final String avatarPath;
  final bool isSystem;
  final bool isParticipant;
  final String? participantId;
}

enum GameSeatSide { left, right }

class GameSeatSlot {
  const GameSeatSlot({
    required this.side,
    required this.index,
    this.participant,
  });
  final GameSeatSide side;
  final int index;
  final GameParticipant? participant;
}

class GameSeatAssignment {
  const GameSeatAssignment({required this.left, required this.right});
  final List<GameSeatSlot> left;
  final List<GameSeatSlot> right;

  static GameSeatAssignment from({
    required GameSession session,
    required GameDefinition definition,
  }) {
    final userCount = session.participants
        .where((item) => item.type == GameParticipantType.user)
        .length;
    final hostCharacterId = session.host.characterId;
    final hostIsParticipant =
        hostCharacterId != null &&
        session.participants.any((item) => item.characterId == hostCharacterId);
    final rawCapacity = math.max(0, definition.maxPlayers - userCount);
    final sideCapacity = math.max(0, rawCapacity - (hostIsParticipant ? 1 : 0));
    final characters = session.participants
        .where((item) => item.type == GameParticipantType.character)
        .where((item) => item.characterId != hostCharacterId)
        .take(sideCapacity)
        .toList(growable: false);
    final leftCapacity = (sideCapacity + 1) ~/ 2;
    final rightCapacity = sideCapacity ~/ 2;
    final leftCharacters = <GameParticipant>[];
    final rightCharacters = <GameParticipant>[];
    for (var index = 0; index < characters.length; index++) {
      (index.isEven ? leftCharacters : rightCharacters).add(characters[index]);
    }
    return GameSeatAssignment(
      left: List.generate(
        leftCapacity,
        (index) => GameSeatSlot(
          side: GameSeatSide.left,
          index: index,
          participant: index < leftCharacters.length
              ? leftCharacters[index]
              : null,
        ),
      ),
      right: List.generate(
        rightCapacity,
        (index) => GameSeatSlot(
          side: GameSeatSide.right,
          index: index,
          participant: index < rightCharacters.length
              ? rightCharacters[index]
              : null,
        ),
      ),
    );
  }
}

class GameRoomShell extends StatelessWidget {
  const GameRoomShell({
    super.key,
    required this.definition,
    required this.session,
    required this.host,
    required this.visibleMessages,
    required this.timelineSenderResolver,
    required this.gameInfo,
    required this.actionArea,
    required this.onBack,
    required this.onPauseChanged,
    this.onInvite,
    this.timelineKey,
    this.thinkingParticipantId,
  });

  final GameDefinition definition;
  final GameSession session;
  final GameHostVisual host;
  final List<GameMessage> visibleMessages;
  final GameTimelineSenderResolver timelineSenderResolver;
  final Widget gameInfo;
  final Widget actionArea;
  final VoidCallback onBack;
  final ValueChanged<bool> onPauseChanged;
  final VoidCallback? onInvite;
  final GlobalKey<GameTimelinePanelState>? timelineKey;
  final String? thinkingParticipantId;

  @override
  Widget build(BuildContext context) {
    final seats = GameSeatAssignment.from(
      session: session,
      definition: definition,
    );
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Column(
            children: [
              GameRoomHeader(
                definition: definition,
                session: session,
                onBack: onBack,
                onPauseChanged: onPauseChanged,
              ),
              gameInfo,
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
                  child: Stack(
                    key: const ValueKey('game-play-stack'),
                    clipBehavior: Clip.none,
                    children: [
                      Positioned.fill(
                        left: 78,
                        right: 78,
                        top: 86,
                        child: KeyedSubtree(
                          key: const ValueKey('game-stage'),
                          child: GameRecentConversationStage(
                            session: session,
                            seats: seats,
                            messages: visibleMessages,
                            senderResolver: timelineSenderResolver,
                          ),
                        ),
                      ),
                      Row(
                        key: const ValueKey('game-seat-overlay'),
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _SeatColumn(
                            key: const ValueKey('game-seats-left'),
                            slots: seats.left,
                            inviteEnabled: _inviteEnabled,
                            onInvite: onInvite,
                            thinkingParticipantId: thinkingParticipantId,
                          ),
                          const Spacer(),
                          _SeatColumn(
                            key: const ValueKey('game-seats-right'),
                            slots: seats.right,
                            inviteEnabled: _inviteEnabled,
                            onInvite: onInvite,
                            thinkingParticipantId: thinkingParticipantId,
                          ),
                        ],
                      ),
                      Align(
                        key: const ValueKey('game-host-overlay'),
                        alignment: Alignment.topCenter,
                        child: GameHostSeat(
                          host: host,
                          isThinking:
                              host.isParticipant &&
                              host.participantId == thinkingParticipantId,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              GameTimelinePanel(
                key: timelineKey,
                messages: visibleMessages,
                senderResolver: timelineSenderResolver,
                compactVisible: false,
              ),
              Transform.translate(
                key: const ValueKey('game-action-keyboard-overlay'),
                offset: Offset(0, -keyboardInset),
                child: actionArea,
              ),
            ],
          );
        },
      ),
    );
  }

  bool get _inviteEnabled =>
      {
        GameSessionStatus.draft,
        GameSessionStatus.ready,
      }.contains(session.status) &&
      onInvite != null;
}

class GameRoomHeader extends StatelessWidget {
  const GameRoomHeader({
    super.key,
    required this.definition,
    required this.session,
    required this.onBack,
    required this.onPauseChanged,
  });
  final GameDefinition definition;
  final GameSession session;
  final VoidCallback onBack;
  final ValueChanged<bool> onPauseChanged;

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('game-room-header'),
    margin: const EdgeInsets.fromLTRB(8, 6, 8, 0),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .78),
      borderRadius: BorderRadius.circular(18),
    ),
    child: Row(
      children: [
        IconButton(
          onPressed: onBack,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        CircleAvatar(radius: 19, child: Icon(definition.icon, size: 21)),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                definition.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                '房间 ${_shortId(session.sessionId)} · ${_statusText(session.status)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: Color(0xFF657084)),
              ),
              const SizedBox(height: 3),
              const AiIdentityBadge.compact(),
            ],
          ),
        ),
        _HeaderPill(
          icon: Icons.group_outlined,
          text: '${session.participants.length}/${definition.maxPlayers}',
        ),
        PopupMenuButton<String>(
          key: const ValueKey('game-room-more'),
          onSelected: (value) {
            if (value == 'pause') onPauseChanged(true);
            if (value == 'resume') onPauseChanged(false);
          },
          itemBuilder: (_) => [
            if (session.status == GameSessionStatus.playing)
              const PopupMenuItem(value: 'pause', child: Text('暂停游戏')),
            if (session.status == GameSessionStatus.paused)
              const PopupMenuItem(value: 'resume', child: Text('继续游戏')),
          ],
        ),
      ],
    ),
  );

  static String _shortId(String value) {
    if (value.length <= 6) return value;
    return value.substring(value.length - 6).toUpperCase();
  }

  static String _statusText(GameSessionStatus status) => switch (status) {
    GameSessionStatus.draft => '配置中',
    GameSessionStatus.ready => '等待开始',
    GameSessionStatus.playing => '游戏进行中',
    GameSessionStatus.paused => '已暂停',
    GameSessionStatus.finished => '已结束',
    GameSessionStatus.abandoned => '已放弃',
  };
}

class _HeaderPill extends StatelessWidget {
  const _HeaderPill({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
    decoration: BoxDecoration(
      color: const Color(0xFFEEF1F7),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      children: [Icon(icon, size: 17), const SizedBox(width: 4), Text(text)],
    ),
  );
}

class GameHostSeat extends StatelessWidget {
  const GameHostSeat({
    super.key,
    required this.host,
    this.bubble,
    this.isThinking = false,
  });
  final GameHostVisual host;
  final String? bubble;
  final bool isThinking;

  @override
  Widget build(BuildContext context) {
    final frames = PeiLinkThemeScope.of(context).avatarFrameTheme;
    return Column(
      key: const ValueKey('game-host-seat'),
      mainAxisSize: MainAxisSize.min,
      children: [
        PeiLinkThemedAvatar(
          size: 52,
          role: PeiLinkAvatarRole.character,
          imagePath: host.avatarPath,
          frame: frames.character,
          fallback: Icon(
            host.isSystem
                ? Icons.smart_toy_outlined
                : Icons.auto_awesome_rounded,
            color: const Color(0xFF61768E),
          ),
        ),
        const SizedBox(height: 3),
        Text(
          host.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
        ),
        Text(
          host.isParticipant ? '主持 / 玩家' : '主持人',
          style: const TextStyle(fontSize: 10, color: Color(0xFF68758A)),
        ),
        SizedBox(
          height: 13,
          child: isThinking
              ? Text(
                  '正在思考…',
                  key: ValueKey('game-seat-thinking-${host.participantId}'),
                  style: const TextStyle(fontSize: 9, color: Color(0xFF7868C8)),
                )
              : null,
        ),
        if (bubble != null)
          GameSeatSpeechBubble(
            key: const ValueKey('game-host-bubble'),
            text: bubble!,
            side: null,
          ),
      ],
    );
  }
}

class _SeatColumn extends StatelessWidget {
  const _SeatColumn({
    super.key,
    required this.slots,
    required this.inviteEnabled,
    required this.thinkingParticipantId,
    this.onInvite,
  });
  final List<GameSeatSlot> slots;
  final bool inviteEnabled;
  final String? thinkingParticipantId;
  final VoidCallback? onInvite;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 76,
    child: Column(
      children: [
        const SizedBox(height: 84),
        ...slots.map((slot) {
          final participant = slot.participant;
          return Expanded(
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: participant == null
                    ? GameEmptySeat(
                        side: slot.side,
                        enabled: inviteEnabled,
                        onTap: onInvite,
                      )
                    : GameParticipantSeat(
                        participant: participant,
                        side: slot.side,
                        isThinking:
                            participant.participantId == thinkingParticipantId,
                      ),
              ),
            ),
          );
        }),
      ],
    ),
  );
}

class GameParticipantSeat extends StatelessWidget {
  const GameParticipantSeat({
    super.key,
    required this.participant,
    required this.side,
    this.bubble,
    this.isThinking = false,
  });
  final GameParticipant participant;
  final GameSeatSide side;
  final String? bubble;
  final bool isThinking;

  @override
  Widget build(BuildContext context) {
    final frames = PeiLinkThemeScope.of(context).avatarFrameTheme;
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PeiLinkThemedAvatar(
              size: 48,
              role: PeiLinkAvatarRole.character,
              imagePath: participant.avatarReference,
              frame: frames.character,
            ),
            const SizedBox(height: 3),
            SizedBox(
              width: 72,
              child: Text(
                participant.displayName,
                maxLines: 1,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            SizedBox(
              height: 13,
              child: isThinking
                  ? Text(
                      '正在思考…',
                      key: ValueKey(
                        'game-seat-thinking-${participant.participantId}',
                      ),
                      style: const TextStyle(
                        fontSize: 9,
                        color: Color(0xFF7868C8),
                      ),
                    )
                  : null,
            ),
          ],
        ),
        if (bubble != null)
          Positioned(
            left: side == GameSeatSide.left ? 58 : null,
            right: side == GameSeatSide.right ? 58 : null,
            top: 0,
            child: GameSeatSpeechBubble(text: bubble!, side: side),
          ),
      ],
    );
  }
}

class GameSeatSpeechBubble extends StatelessWidget {
  const GameSeatSpeechBubble({
    super.key,
    required this.text,
    required this.side,
  });
  final String text;
  final GameSeatSide? side;

  @override
  Widget build(BuildContext context) => AnimatedOpacity(
    duration: const Duration(milliseconds: 180),
    opacity: 1,
    child: Container(
      constraints: const BoxConstraints(maxWidth: 132),
      margin: const EdgeInsets.only(top: 3),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .94),
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1F26334C),
            blurRadius: 8,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Text(
        text,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 11.5, height: 1.25),
      ),
    ),
  );
}

class GameEmptySeat extends StatelessWidget {
  const GameEmptySeat({
    super.key,
    required this.side,
    required this.enabled,
    this.onTap,
  });
  final GameSeatSide side;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    key: ValueKey('game-empty-seat-${side.name}'),
    onTap: enabled ? onTap : null,
    borderRadius: BorderRadius.circular(28),
    child: Opacity(
      opacity: enabled ? 1 : .45,
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(radius: 22, child: Icon(Icons.add_rounded)),
          SizedBox(height: 3),
          Text('邀请角色', style: TextStyle(fontSize: 10)),
        ],
      ),
    ),
  );
}

class GameRecentConversationStage extends StatelessWidget {
  const GameRecentConversationStage({
    super.key,
    required this.session,
    required this.seats,
    required this.messages,
    required this.senderResolver,
  });

  final GameSession session;
  final GameSeatAssignment seats;
  final List<GameMessage> messages;
  final GameTimelineSenderResolver senderResolver;

  @override
  Widget build(BuildContext context) {
    final recent = messages
        .where(
          (message) => {
            GameMessageType.question,
            GameMessageType.answer,
            GameMessageType.guess,
            GameMessageType.participant,
            GameMessageType.host,
            GameMessageType.hint,
          }.contains(message.type),
        )
        .toList(growable: false)
        .reversed
        .take(5)
        .toList(growable: false)
        .reversed
        .toList(growable: false);
    return Container(
      key: const ValueKey('game-recent-conversation-stage'),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .52),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: .66)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
      child: recent.isEmpty
          ? const Center(
              child: Text(
                '最近的推理会出现在这里',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: Color(0xFF7A8494)),
              ),
            )
          : ListView.builder(
              key: const ValueKey('game-recent-conversation-list'),
              physics: const NeverScrollableScrollPhysics(),
              itemCount: recent.length,
              itemBuilder: (context, index) => _RecentConversationMessage(
                message: recent[index],
                placement: _placementFor(recent[index]),
                label: senderResolver.labelFor(recent[index]),
              ),
            ),
    );
  }

  _RecentMessagePlacement _placementFor(GameMessage message) {
    if (message.senderId == 'host' ||
        {GameMessageType.host, GameMessageType.answer}.contains(message.type)) {
      return _RecentMessagePlacement.host;
    }
    final userId = session.participants
        .where((item) => item.type == GameParticipantType.user)
        .map((item) => item.participantId)
        .firstOrNull;
    if (message.senderId == userId) return _RecentMessagePlacement.user;
    if (seats.left.any(
      (slot) => slot.participant?.participantId == message.senderId,
    )) {
      return _RecentMessagePlacement.left;
    }
    if (seats.right.any(
      (slot) => slot.participant?.participantId == message.senderId,
    )) {
      return _RecentMessagePlacement.right;
    }
    return _RecentMessagePlacement.center;
  }
}

enum _RecentMessagePlacement { host, left, right, user, center }

class _RecentConversationMessage extends StatelessWidget {
  const _RecentConversationMessage({
    required this.message,
    required this.placement,
    required this.label,
  });

  final GameMessage message;
  final _RecentMessagePlacement placement;
  final String label;

  @override
  Widget build(BuildContext context) {
    final alignment = switch (placement) {
      _RecentMessagePlacement.host ||
      _RecentMessagePlacement.center => Alignment.center,
      _RecentMessagePlacement.left => Alignment.centerLeft,
      _RecentMessagePlacement.right ||
      _RecentMessagePlacement.user => Alignment.centerRight,
    };
    final color = switch (placement) {
      _RecentMessagePlacement.host => const Color(0xFFFFF0D9),
      _RecentMessagePlacement.user => const Color(0xFFE8E3FF),
      _ => Colors.white.withValues(alpha: .92),
    };
    return Align(
      alignment: alignment,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 230),
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(11),
        ),
        child: Column(
          crossAxisAlignment:
              placement == _RecentMessagePlacement.right ||
                  placement == _RecentMessagePlacement.user
              ? CrossAxisAlignment.end
              : placement == _RecentMessagePlacement.host ||
                    placement == _RecentMessagePlacement.center
              ? CrossAxisAlignment.center
              : CrossAxisAlignment.start,
          children: [
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 9.5,
                color: Color(0xFF6C7280),
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              message.content,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: placement == _RecentMessagePlacement.host
                  ? TextAlign.center
                  : TextAlign.start,
              style: const TextStyle(fontSize: 11.5, height: 1.25),
            ),
          ],
        ),
      ),
    );
  }
}

enum GameTimelineFilter { all, question, answer, guess, hint, system }

class GameTimelinePanel extends StatefulWidget {
  const GameTimelinePanel({
    super.key,
    required this.messages,
    required this.senderResolver,
    this.compactVisible = true,
  });
  final List<GameMessage> messages;
  final GameTimelineSenderResolver senderResolver;
  final bool compactVisible;
  @override
  State<GameTimelinePanel> createState() => GameTimelinePanelState();
}

class GameTimelinePanelState extends State<GameTimelinePanel> {
  GameTimelineFilter _filter = GameTimelineFilter.all;

  List<GameMessage> get _filtered => widget.messages
      .where((message) => _matches(message, _filter))
      .toList(growable: false);

  @override
  Widget build(BuildContext context) {
    if (!widget.compactVisible) return const SizedBox.shrink();
    final recent = _filtered.reversed.take(3).toList().reversed.toList();
    return Container(
      key: const ValueKey('game-timeline-compact'),
      margin: const EdgeInsets.symmetric(horizontal: 8),
      padding: const EdgeInsets.fromLTRB(10, 7, 10, 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .8),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 30,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: GameTimelineFilter.values
                        .map(
                          (filter) => Padding(
                            padding: const EdgeInsets.only(right: 5),
                            child: ChoiceChip(
                              key: ValueKey(
                                'game-timeline-filter-${filter.name}',
                              ),
                              label: Text(_filterLabel(filter)),
                              selected: _filter == filter,
                              onSelected: (_) =>
                                  setState(() => _filter = filter),
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ),
              IconButton(
                key: const ValueKey('game-timeline-expand'),
                onPressed: openExpanded,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.expand_less_rounded),
              ),
            ],
          ),
          Expanded(
            child: recent.isEmpty
                ? const Center(
                    child: Text('暂无记录', style: TextStyle(fontSize: 11)),
                  )
                : ListView(
                    physics: const NeverScrollableScrollPhysics(),
                    children: recent
                        .map(
                          (message) => _TimelineRow(
                            message,
                            compact: true,
                            senderLabel: widget.senderResolver.labelFor(
                              message,
                            ),
                          ),
                        )
                        .toList(),
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> openExpanded() async {
    var sheetFilter = _filter;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          final messages = widget.messages
              .where((message) => _matches(message, sheetFilter))
              .toList(growable: false);
          return FractionallySizedBox(
            heightFactor: .72,
            child: Material(
              key: const ValueKey('game-timeline-expanded'),
              color: const Color(0xFFF7F8FC),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  children: [
                    const SizedBox(height: 8),
                    Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                        color: const Color(0xFFBBC2CE),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: Text(
                        '游戏记录',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Wrap(
                      spacing: 5,
                      children: GameTimelineFilter.values
                          .map(
                            (filter) => ChoiceChip(
                              label: Text(_filterLabel(filter)),
                              selected: sheetFilter == filter,
                              onSelected: (_) {
                                setSheetState(() => sheetFilter = filter);
                                setState(() => _filter = filter);
                              },
                            ),
                          )
                          .toList(),
                    ),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.all(12),
                        children: messages
                            .map(
                              (message) => _TimelineRow(
                                message,
                                compact: false,
                                senderLabel: widget.senderResolver.labelFor(
                                  message,
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  static bool _matches(GameMessage message, GameTimelineFilter filter) =>
      switch (filter) {
        GameTimelineFilter.all => true,
        GameTimelineFilter.question => message.type == GameMessageType.question,
        GameTimelineFilter.answer =>
          message.type == GameMessageType.answer ||
              message.type == GameMessageType.host,
        GameTimelineFilter.guess => message.type == GameMessageType.guess,
        GameTimelineFilter.hint => message.type == GameMessageType.hint,
        GameTimelineFilter.system => {
          GameMessageType.system,
          GameMessageType.narration,
          GameMessageType.puzzle,
          GameMessageType.reveal,
        }.contains(message.type),
      };

  static String _filterLabel(GameTimelineFilter filter) => switch (filter) {
    GameTimelineFilter.all => '全部',
    GameTimelineFilter.question => '提问',
    GameTimelineFilter.answer => '回答',
    GameTimelineFilter.guess => '猜测',
    GameTimelineFilter.hint => '提示',
    GameTimelineFilter.system => '系统',
  };
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow(
    this.message, {
    required this.compact,
    required this.senderLabel,
  });
  final GameMessage message;
  final bool compact;
  final String senderLabel;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: compact
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 86,
                child: Text(
                  senderLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xFF69758B),
                  ),
                ),
              ),
              Expanded(child: _messageText),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                senderLabel,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF69758B),
                ),
              ),
              const SizedBox(height: 2),
              _messageText,
            ],
          ),
  );

  Widget get _messageText => Text(
    key: ValueKey(
      'game-timeline-message-${compact ? 'compact' : 'expanded'}-${message.id}',
    ),
    message.content,
    maxLines: compact ? 3 : null,
    overflow: compact ? TextOverflow.ellipsis : TextOverflow.visible,
    style: const TextStyle(fontSize: 11.5),
  );
}

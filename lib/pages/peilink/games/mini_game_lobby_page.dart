import 'package:flutter/material.dart';

import '../../../games/models/game_models.dart';
import '../../../games/registry/mini_game_registry.dart';
import '../../../games/storage/game_session_storage_service.dart';
import '../../../widgets/theme/peilink_theme_chrome.dart';
import 'create_game_room_page.dart';
import 'game_room_page.dart';

class MiniGameLobbyPage extends StatefulWidget {
  const MiniGameLobbyPage({super.key, this.storage, this.sessionsLoader});
  final GameSessionStorageService? storage;
  final Future<List<GameSession>> Function()? sessionsLoader;

  @override
  State<MiniGameLobbyPage> createState() => _MiniGameLobbyPageState();
}

class _MiniGameLobbyPageState extends State<MiniGameLobbyPage> {
  late final GameSessionStorageService _storage =
      widget.storage ?? GameSessionStorageService();
  List<GameSession> _sessions = const [];
  List<GameSession> _finished = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final all =
        await (widget.sessionsLoader?.call() ?? _storage.loadSessions());
    final sessions = all
        .where(
          (item) => !{
            GameSessionStatus.finished,
            GameSessionStatus.abandoned,
          }.contains(item.status),
        )
        .toList();
    final finished = all
        .where((item) => item.status == GameSessionStatus.finished)
        .take(5)
        .toList();
    if (mounted) {
      setState(() {
        _sessions = sessions;
        _finished = finished;
        _loading = false;
      });
    }
  }

  Future<void> _create(GameDefinition definition) async {
    // 入口短路：存在进行中的同游戏 session 时优先恢复，不静默新建房间。
    // Finished / Abandoned 已被 loadActiveSessionForGame 排除，不会阻塞新建。
    final active = await _storage.loadActiveSessionForGame(definition.id);
    if (!mounted) return;
    if (active != null) {
      await _open(active);
      await _load();
      return;
    }
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            CreateGameRoomPage(definition: definition, storage: _storage),
      ),
    );
    await _load();
  }

  Future<void> _open(GameSession session) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => GameRoomPage(session: session, storage: _storage),
      ),
    );
    await _load();
  }

  Future<void> _abandon(GameSession session) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('放弃房间？'),
        content: const Text('放弃后，这个房间将不再出现在“继续游戏”中。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('放弃'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _storage.abandon(session.sessionId);
      await _load();
    }
  }

  Future<void> _deleteSession(GameSession session) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除游戏记录？'),
        content: const Text('该游戏会话的消息、时间线和问答记录将被永久删除，无法恢复。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('删除')),
        ],
      ),
    );
    if (confirmed == true) {
      await _storage.delete(session.sessionId);
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) => PeiLinkThemeScaffold(
    body: Scaffold(
      backgroundColor: Colors.transparent,
      appBar: const PeiLinkThemeTopBar(title: Text('小游戏')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              key: const ValueKey('mini-game-lobby'),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              children: [
                if (_sessions.isNotEmpty) ...[
                  const _SectionTitle('继续游戏'),
                  for (final session in _sessions)
                    _SessionCard(
                      session: session,
                      onContinue: () => _open(session),
                      onAbandon: () => _abandon(session),
                      onDelete: () => _deleteSession(session),
                    ),
                  const SizedBox(height: 18),
                ] else
                  const _EmptyContinueState(),
                if (_finished.isNotEmpty) ...[
                  const _SectionTitle('最近完成'),
                  for (final session in _finished)
                    _FinishedSessionCard(session: session),
                  const SizedBox(height: 18),
                ],
                const _SectionTitle('开始新游戏'),
                for (final definition in MiniGameRegistry.instance.all)
                  _GameCard(
                    definition: definition,
                    onCreate: () => _create(definition),
                  ),
              ],
            ),
    ),
  );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(
      text,
      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
    ),
  );
}

class _EmptyContinueState extends StatelessWidget {
  const _EmptyContinueState();
  @override
  Widget build(BuildContext context) => const Padding(
    key: ValueKey('game-lobby-empty-state'),
    padding: EdgeInsets.only(bottom: 20),
    child: Text('还没有进行中的房间', style: TextStyle(color: Color(0xFF7A8493))),
  );
}

class _GameCard extends StatelessWidget {
  const _GameCard({required this.definition, required this.onCreate});
  final GameDefinition definition;
  final VoidCallback onCreate;
  @override
  Widget build(BuildContext context) => Card(
    key: ValueKey('game-card-${definition.id}'),
    color: Colors.white.withValues(alpha: .86),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          CircleAvatar(child: Icon(definition.icon)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  definition.displayName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
                Text(definition.description),
                Text(
                  definition.isPlayable
                      ? '${definition.minPlayers}–${definition.maxPlayers} 位玩家 · 可游玩'
                      : '${definition.minPlayers}–${definition.maxPlayers} 人 · 即将开放',
                  style: const TextStyle(
                    color: Color(0xFF728098),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: definition.isPlayable ? onCreate : null,
            child: Text(definition.isPlayable ? '创建房间' : '敬请期待'),
          ),
        ],
      ),
    ),
  );
}

class _FinishedSessionCard extends StatelessWidget {
  const _FinishedSessionCard({required this.session});
  final GameSession session;
  @override
  Widget build(BuildContext context) {
    final game = MiniGameRegistry.instance.definition(session.gameId);
    return Card(
      key: ValueKey('finished-game-session-${session.sessionId}'),
      child: ListTile(
        leading: Icon(game.icon),
        title: Text(game.displayName),
        subtitle: const Text('已完成'),
        trailing: const Icon(Icons.check_circle_outline),
      ),
    );
  }
}

class _SessionCard extends StatelessWidget {
  const _SessionCard({
    required this.session,
    required this.onContinue,
    required this.onAbandon,
    required this.onDelete,
  });
  final GameSession session;
  final VoidCallback onContinue;
  final VoidCallback onAbandon;
  final VoidCallback onDelete;
  @override
  Widget build(BuildContext context) {
    final game = MiniGameRegistry.instance.definition(session.gameId);
    return Card(
      key: ValueKey('game-session-${session.sessionId}'),
      child: ListTile(
        leading: Icon(game.icon),
        title: Text(game.displayName),
        subtitle: Text(
          '${session.participants.length} 位参与者 · ${session.status.name}',
        ),
        onTap: onContinue,
        trailing: PopupMenuButton<String>(
          onSelected: (value) {
            if (value == 'abandon') onAbandon();
            if (value == 'delete') onDelete();
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'abandon', child: Text('放弃房间')),
            PopupMenuItem(value: 'delete', child: Text('删除记录')),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../../games/models/game_models.dart';
import '../../../games/registry/mini_game_registry.dart';
import '../../../games/services/game_participant_factory.dart';
import '../../../games/storage/game_session_storage_service.dart';
import '../../../games/turtle_soup/turtle_soup_puzzle_registry.dart';
import '../../../models/ai_character.dart';
import '../../../models/user_profile.dart';
import '../../../services/character_registry_service.dart';
import '../../../services/user_profile_storage_service.dart';
import '../../../widgets/theme/peilink_theme_chrome.dart';
import '../../../widgets/theme/peilink_theme_scope.dart';
import '../../../widgets/theme/peilink_themed_avatar.dart';
import 'game_room_page.dart';

class CreateGameRoomPage extends StatefulWidget {
  const CreateGameRoomPage({
    super.key,
    required this.definition,
    required this.storage,
    this.profileLoader,
    this.characterLoader,
  });
  final GameDefinition definition;
  final GameSessionStorageService storage;
  final Future<UserProfile> Function()? profileLoader;
  final Future<List<AiCharacter>> Function()? characterLoader;

  static GameSession buildSession({
    required GameDefinition definition,
    required UserProfile profile,
    required List<AiCharacter> characters,
    required Set<String> selectedCharacterIds,
    required GameHost host,
    required DateTime now,
    String? puzzleId,
  }) => GameSession(
    sessionId: 'game_${now.microsecondsSinceEpoch}',
    gameId: definition.id,
    createdAt: now,
    updatedAt: now,
    status: GameSessionStatus.ready,
    host: host,
    participants: [
      GameParticipantFactory.user(profile),
      ...characters
          .where((item) => selectedCharacterIds.contains(item.id))
          .map(GameParticipantFactory.character),
    ],
    gameState: BaseGameState(
      participantState: puzzleId == null ? const {} : {'puzzleId': puzzleId},
    ),
  );

  @override
  State<CreateGameRoomPage> createState() => _CreateGameRoomPageState();
}

class _CreateGameRoomPageState extends State<CreateGameRoomPage> {
  UserProfile _profile = const UserProfile();
  List<AiCharacter> _characters = const [];
  final Set<String> _selectedCharacterIds = {};
  GameHost _host = const GameHost.system();
  bool _loading = true;
  bool _showCharacterParticipants = false;
  String? _puzzleId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final values = await Future.wait<Object>([
      widget.profileLoader?.call() ?? UserProfileStorageService().loadProfile(),
      widget.characterLoader?.call() ??
          CharacterRegistryService().loadCharacters(),
    ]);
    if (!mounted) return;
    setState(() {
      _profile = values[0] as UserProfile;
      _characters = values[1] as List<AiCharacter>;
      _loading = false;
    });
  }

  bool get _isTurtleSoup =>
      widget.definition.id == MiniGameRegistry.turtleSoupId;
  int get _playerCount => 1 + _selectedCharacterIds.length;
  bool get _valid => widget.definition.acceptsPlayerCount(_playerCount);
  String get _validationText {
    if (_playerCount < widget.definition.minPlayers) {
      return '还需要 ${widget.definition.minPlayers - _playerCount} 位参与者';
    }
    if (_playerCount > widget.definition.maxPlayers) return '参与者超过上限';
    return '房间配置已就绪';
  }

  Future<void> _create() async {
    if (!_valid) return;
    final now = DateTime.now();
    final session = CreateGameRoomPage.buildSession(
      definition: widget.definition,
      profile: _profile,
      characters: _characters,
      selectedCharacterIds: _selectedCharacterIds,
      host: _host,
      now: now,
      puzzleId: _puzzleId,
    );
    final result = await widget.storage.save(session);
    if (!mounted) return;
    if (!result.isSuccess) {
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(content: Text(result.message)),
      );
      return;
    }
    await Navigator.pushReplacement<void, void>(
      context,
      MaterialPageRoute(
        builder: (_) => GameRoomPage(session: session, storage: widget.storage),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => PeiLinkThemeScaffold(
    body: Scaffold(
      backgroundColor: Colors.transparent,
      appBar: PeiLinkThemeTopBar(
        title: Text('创建·${widget.definition.displayName}'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              key: const ValueKey('create-game-room'),
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  '参与者',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                ),
                _ParticipantTile(
                  name: _profile.nickname,
                  avatarPath: _profile.avatarPath,
                  role: PeiLinkAvatarRole.user,
                  selected: true,
                  enabled: false,
                ),
                if (_isTurtleSoup) ...[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      key: const ValueKey('game-add-character-participant'),
                      onPressed: () => setState(
                        () => _showCharacterParticipants =
                            !_showCharacterParticipants,
                      ),
                      icon: Icon(
                        _showCharacterParticipants
                            ? Icons.expand_less
                            : Icons.add,
                      ),
                      label: const Text('添加角色'),
                    ),
                  ),
                  if (_showCharacterParticipants && _characters.isEmpty)
                    const Padding(
                      key: ValueKey('game-character-participant-empty'),
                      padding: EdgeInsets.fromLTRB(12, 4, 12, 12),
                      child: Text('还没有可加入的角色，先创建一个角色吧。'),
                    ),
                ],
                if (!_isTurtleSoup || _showCharacterParticipants)
                  for (final character in _characters)
                    _ParticipantTile(
                      key: ValueKey('game-character-${character.id}'),
                      name: character.displayName,
                      avatarPath: character.effectiveSocialAvatarPath,
                      role: PeiLinkAvatarRole.character,
                      selected: _selectedCharacterIds.contains(character.id),
                      enabled: true,
                      onChanged: (selected) => setState(() {
                        if (selected) {
                          _selectedCharacterIds.add(character.id);
                        } else {
                          _selectedCharacterIds.remove(character.id);
                        }
                      }),
                    ),
                if (_isTurtleSoup) ...[
                  const SizedBox(height: 18),
                  const Text(
                    '谜题',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                  ),
                  DropdownButtonFormField<String>(
                    key: const ValueKey('turtle-soup-puzzle-selector'),
                    initialValue: _puzzleId,
                    decoration: const InputDecoration(labelText: '随机或指定谜题'),
                    items: [
                      const DropdownMenuItem<String>(
                        value: null,
                        child: Text('随机谜题'),
                      ),
                      ...TurtleSoupPuzzleRegistry.puzzles.map(
                        (item) => DropdownMenuItem(
                          value: item.id,
                          child: Text(item.title),
                        ),
                      ),
                    ],
                    onChanged: (value) => setState(() => _puzzleId = value),
                  ),
                ],
                const SizedBox(height: 18),
                const Text(
                  '主持人',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                ),
                RadioGroup<GameHostType>(
                  groupValue: _host.type,
                  onChanged: (type) {
                    if (type == GameHostType.systemHost) {
                      setState(() => _host = const GameHost.system());
                    }
                  },
                  child: const RadioListTile<GameHostType>(
                    value: GameHostType.systemHost,
                    title: Text('系统主持人'),
                  ),
                ),
                if (widget.definition.supportsCharacterHost)
                  DropdownButtonFormField<String>(
                    key: const ValueKey('game-host-character-selector'),
                    initialValue: _host.characterId,
                    decoration: const InputDecoration(labelText: '或选择角色主持'),
                    items: _characters
                        .map(
                          (item) => DropdownMenuItem(
                            value: item.id,
                            child: Text(item.displayName),
                          ),
                        )
                        .toList(),
                    onChanged: (id) => setState(() {
                      _host = id == null
                          ? const GameHost.system()
                          : GameHost.character(id);
                    }),
                  ),
                const SizedBox(height: 20),
                Text(
                  _validationText,
                  key: const ValueKey('game-player-validation'),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  key: const ValueKey('create-game-room-submit'),
                  onPressed: _valid ? _create : null,
                  child: const Text('创建房间'),
                ),
              ],
            ),
    ),
  );
}

class _ParticipantTile extends StatelessWidget {
  const _ParticipantTile({
    super.key,
    required this.name,
    required this.avatarPath,
    required this.role,
    required this.selected,
    required this.enabled,
    this.onChanged,
  });
  final String name;
  final String avatarPath;
  final PeiLinkAvatarRole role;
  final bool selected;
  final bool enabled;
  final ValueChanged<bool>? onChanged;
  @override
  Widget build(BuildContext context) {
    final frames = PeiLinkThemeScope.of(context).avatarFrameTheme;
    return CheckboxListTile(
      value: selected,
      onChanged: enabled ? (value) => onChanged?.call(value == true) : null,
      secondary: PeiLinkThemedAvatar(
        size: 42,
        role: role,
        imagePath: avatarPath,
        frame: role == PeiLinkAvatarRole.user ? frames.user : frames.character,
      ),
      title: Text(name.trim().isEmpty ? '未设置' : name),
      subtitle: Text(
        role == PeiLinkAvatarRole.user ? '我 · 默认加入' : 'AI Character',
      ),
    );
  }
}

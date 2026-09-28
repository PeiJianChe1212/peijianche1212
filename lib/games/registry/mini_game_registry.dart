import 'package:flutter/material.dart';

import '../engines/game_engine.dart';
import '../models/game_models.dart';
import '../turtle_soup/turtle_soup_engine.dart';
import '../turtle_soup/turtle_soup_models.dart';

typedef GameEngineFactory = GameEngine<dynamic> Function();

class GameDefinition {
  const GameDefinition({
    required this.id,
    required this.displayName,
    required this.description,
    required this.icon,
    required this.minPlayers,
    required this.maxPlayers,
    required this.supportsCharacterHost,
    required this.supportsSystemHost,
    required this.allowHostAsParticipant,
    required this.status,
    required this.engineFactory,
  });
  final String id;
  final String displayName;
  final String description;
  final IconData icon;
  final int minPlayers;
  final int maxPlayers;
  final bool supportsCharacterHost;
  final bool supportsSystemHost;
  final bool allowHostAsParticipant;
  final GameAvailability status;
  final GameEngineFactory engineFactory;
  bool get isPlayable => status == GameAvailability.available;
  bool acceptsPlayerCount(int count) =>
      count >= minPlayers && count <= maxPlayers;
}

class MiniGameRegistry {
  MiniGameRegistry._() {
    registerTurtleSoupStateCodec();
  }
  static final instance = MiniGameRegistry._();

  static const turtleSoupId = 'turtle_soup';
  static const scriptMurderId = 'script_murder';
  static const werewolfId = 'werewolf';

  late final Map<String, GameDefinition> _definitions = {
    for (final item in <GameDefinition>[
      GameDefinition(
        id: turtleSoupId,
        displayName: '海龟汤',
        description: '推理谜面背后的完整故事',
        icon: Icons.psychology_alt_outlined,
        minPlayers: 1,
        maxPlayers: 8,
        supportsCharacterHost: true,
        supportsSystemHost: true,
        allowHostAsParticipant: true,
        status: GameAvailability.available,
        engineFactory: TurtleSoupEngine.new,
      ),
      GameDefinition(
        id: scriptMurderId,
        displayName: '剧本杀',
        description: '角色扮演与剧情推理',
        icon: Icons.theater_comedy_outlined,
        minPlayers: 3,
        maxPlayers: 8,
        supportsCharacterHost: true,
        supportsSystemHost: true,
        allowHostAsParticipant: true,
        status: GameAvailability.comingSoon,
        engineFactory: _unavailable,
      ),
      GameDefinition(
        id: werewolfId,
        displayName: '狼人杀',
        description: '身份、发言、投票与阵营博弈',
        icon: Icons.nightlight_round,
        minPlayers: 5,
        maxPlayers: 12,
        supportsCharacterHost: true,
        supportsSystemHost: true,
        allowHostAsParticipant: true,
        status: GameAvailability.comingSoon,
        engineFactory: _unavailable,
      ),
    ])
      item.id: item,
  };

  static GameEngine<dynamic> _unavailable() => const UnavailableGameEngine();
  List<GameDefinition> get all => List.unmodifiable(_definitions.values);
  GameDefinition? find(String id) => _definitions[id];
  GameDefinition definition(String id) =>
      find(id) ??
      GameDefinition(
        id: id,
        displayName: '未知游戏',
        description: '该游戏定义不存在',
        icon: Icons.help_outline_rounded,
        minPlayers: 1,
        maxPlayers: 1,
        supportsCharacterHost: false,
        supportsSystemHost: true,
        allowHostAsParticipant: false,
        status: GameAvailability.comingSoon,
        engineFactory: _unavailable,
      );
}

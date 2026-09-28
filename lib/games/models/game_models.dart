import 'dart:convert';

enum GameAvailability { frameworkOnly, comingSoon, available }

enum GameParticipantType { user, character, remotePlayer }

enum GameHostType { systemHost, characterHost }

enum GameSessionStatus { draft, ready, playing, paused, finished, abandoned }

enum GameMessageType {
  system,
  host,
  participant,
  narration,
  puzzle,
  question,
  answer,
  hint,
  guess,
  reveal,
}

enum GameMessageVisibility { public, privateToParticipant }

enum GameActionType { textInput, ready, leave, pause, resume, custom }

enum GameEventType {
  sessionStarted,
  roundStarted,
  messageAdded,
  participantJoined,
  participantLeft,
  stateChanged,
  gamePaused,
  gameFinished,
  error,
}

enum GameResultCode {
  success,
  invalidAction,
  invalidState,
  engineUnavailable,
  storageFailure,
}

class GameParticipant {
  const GameParticipant({
    required this.participantId,
    required this.type,
    required this.displayName,
    this.avatarReference = '',
    this.characterId,
    this.userIdentityReference,
  });
  final String participantId;
  final GameParticipantType type;
  final String displayName;
  final String avatarReference;
  final String? characterId;
  final String? userIdentityReference;

  Map<String, dynamic> toJson() => {
    'participantId': participantId,
    'type': type.name,
    'displayName': displayName,
    'avatarReference': avatarReference,
    if (characterId != null) 'characterId': characterId,
    if (userIdentityReference != null)
      'userIdentityReference': userIdentityReference,
  };
  factory GameParticipant.fromJson(Map<dynamic, dynamic> json) =>
      GameParticipant(
        participantId: json['participantId']?.toString() ?? '',
        type: GameParticipantType.values.firstWhere(
          (item) => item.name == json['type'],
          orElse: () => GameParticipantType.user,
        ),
        displayName: json['displayName']?.toString() ?? '',
        avatarReference: json['avatarReference']?.toString() ?? '',
        characterId: json['characterId']?.toString(),
        userIdentityReference: json['userIdentityReference']?.toString(),
      );
}

class GameHost {
  const GameHost._(this.type, this.characterId);
  const GameHost.system() : this._(GameHostType.systemHost, null);
  const GameHost.character(String characterId)
    : this._(GameHostType.characterHost, characterId);
  final GameHostType type;
  final String? characterId;
  Map<String, dynamic> toJson() => {
    'type': type.name,
    if (characterId != null) 'characterId': characterId,
  };
  factory GameHost.fromJson(Map<dynamic, dynamic> json) =>
      json['type'] == GameHostType.characterHost.name &&
          (json['characterId']?.toString().isNotEmpty ?? false)
      ? GameHost.character(json['characterId'].toString())
      : const GameHost.system();
}

class GamePhase {
  const GamePhase({
    required this.phaseId,
    required this.displayName,
    this.roundNumber = 0,
  });
  final String phaseId;
  final String displayName;
  final int roundNumber;
  Map<String, dynamic> toJson() => {
    'phaseId': phaseId,
    'displayName': displayName,
    'roundNumber': roundNumber,
  };
  factory GamePhase.fromJson(Map<dynamic, dynamic> json) => GamePhase(
    phaseId: json['phaseId']?.toString() ?? 'setup',
    displayName: json['displayName']?.toString() ?? '准备',
    roundNumber: (json['roundNumber'] as num?)?.toInt() ?? 0,
  );
}

abstract class GameStateSnapshot {
  const GameStateSnapshot();
  String get stateType;
  Map<String, dynamic> toJson();
}

typedef GameStateDecoder = GameStateSnapshot Function(Map<dynamic, dynamic>);

class GameStateSnapshotCodec {
  GameStateSnapshotCodec._();
  static final Map<String, GameStateDecoder> _decoders = {
    'base': BaseGameState.fromJson,
  };

  static void register(String stateType, GameStateDecoder decoder) {
    _decoders[stateType] = decoder;
  }

  static GameStateSnapshot decode(Map<dynamic, dynamic> json) {
    final type = json['stateType']?.toString() ?? 'base';
    return (_decoders[type] ?? BaseGameState.fromJson)(json);
  }
}

class BaseGameState extends GameStateSnapshot {
  const BaseGameState({
    this.phase = const GamePhase(phaseId: 'setup', displayName: '准备'),
    this.participantState = const {},
  });
  final GamePhase phase;
  final Map<String, dynamic> participantState;
  @override
  String get stateType => 'base';
  @override
  Map<String, dynamic> toJson() => {
    'stateType': stateType,
    'phase': phase.toJson(),
    'participantState': participantState,
  };
  factory BaseGameState.fromJson(Map<dynamic, dynamic> json) => BaseGameState(
    phase: json['phase'] is Map
        ? GamePhase.fromJson(json['phase'] as Map)
        : const GamePhase(phaseId: 'setup', displayName: '准备'),
    participantState: json['participantState'] is Map
        ? Map<String, dynamic>.from(json['participantState'] as Map)
        : const {},
  );
}

class GameMessage {
  GameMessage({
    required this.sessionId,
    required this.senderId,
    required this.type,
    required this.content,
    this.visibility = GameMessageVisibility.public,
    this.visibleToParticipantId,
    String? id,
    DateTime? createdAt,
  }) : id = id ?? DateTime.now().microsecondsSinceEpoch.toString(),
       createdAt = createdAt ?? DateTime.now();
  final String id;
  final String sessionId;
  final String senderId;
  final GameMessageType type;
  final String content;
  final DateTime createdAt;
  final GameMessageVisibility visibility;
  final String? visibleToParticipantId;
  Map<String, dynamic> toJson() => {
    'id': id,
    'sessionId': sessionId,
    'senderId': senderId,
    'type': type.name,
    'content': content,
    'createdAt': createdAt.toIso8601String(),
    'visibility': visibility.name,
    if (visibleToParticipantId != null)
      'visibleToParticipantId': visibleToParticipantId,
  };
  factory GameMessage.fromJson(Map<dynamic, dynamic> json) => GameMessage(
    id: json['id']?.toString(),
    sessionId: json['sessionId']?.toString() ?? '',
    senderId: json['senderId']?.toString() ?? '',
    type: GameMessageType.values.firstWhere(
      (item) => item.name == json['type'],
      orElse: () => GameMessageType.system,
    ),
    content: json['content']?.toString() ?? '',
    createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? ''),
    visibility: GameMessageVisibility.values.firstWhere(
      (item) => item.name == json['visibility'],
      orElse: () => GameMessageVisibility.public,
    ),
    visibleToParticipantId: json['visibleToParticipantId']?.toString(),
  );
}

class GameAction {
  const GameAction({
    required this.type,
    required this.actorParticipantId,
    this.payload = const {},
  });
  final GameActionType type;
  final String actorParticipantId;
  final Map<String, dynamic> payload;
}

class GameEvent {
  const GameEvent({required this.type, this.message, this.state});
  final GameEventType type;
  final GameMessage? message;
  final GameStateSnapshot? state;
}

class GameResult<T> {
  const GameResult(this.code, {this.value, this.message = ''});
  const GameResult.success([T? value])
    : this(GameResultCode.success, value: value);
  final GameResultCode code;
  final T? value;
  final String message;
  bool get isSuccess => code == GameResultCode.success;
}

class GameSession {
  GameSession({
    required this.sessionId,
    required this.gameId,
    required this.createdAt,
    required this.updatedAt,
    required this.status,
    required this.host,
    required Iterable<GameParticipant> participants,
    this.currentRound = 0,
    this.gameState = const BaseGameState(),
    this.messages = const [],
    this.schemaVersion = currentSchemaVersion,
  }) : participants = _dedupe(participants);
  static const currentSchemaVersion = 1;
  final String sessionId;
  final String gameId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final GameSessionStatus status;
  final GameHost host;
  final List<GameParticipant> participants;
  final int currentRound;
  final GameStateSnapshot gameState;
  final List<GameMessage> messages;
  final int schemaVersion;

  static List<GameParticipant> _dedupe(Iterable<GameParticipant> input) {
    final seen = <String>{};
    return input.where((item) => seen.add(item.participantId)).toList();
  }

  GameSession copyWith({
    GameSessionStatus? status,
    GameHost? host,
    Iterable<GameParticipant>? participants,
    int? currentRound,
    GameStateSnapshot? gameState,
    List<GameMessage>? messages,
    DateTime? updatedAt,
  }) => GameSession(
    sessionId: sessionId,
    gameId: gameId,
    createdAt: createdAt,
    updatedAt: updatedAt ?? DateTime.now(),
    status: status ?? this.status,
    host: host ?? this.host,
    participants: participants ?? this.participants,
    currentRound: currentRound ?? this.currentRound,
    gameState: gameState ?? this.gameState,
    messages: messages ?? this.messages,
    schemaVersion: schemaVersion,
  );

  Map<String, dynamic> toJson() => {
    'sessionId': sessionId,
    'gameId': gameId,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'status': status.name,
    'host': host.toJson(),
    'participants': participants.map((item) => item.toJson()).toList(),
    'currentRound': currentRound,
    'gameState': gameState.toJson(),
    'messages': messages.map((item) => item.toJson()).toList(),
    'schemaVersion': schemaVersion,
  };
  String encode() => jsonEncode(toJson());
  factory GameSession.fromJson(Map<dynamic, dynamic> json) => GameSession(
    sessionId: json['sessionId']?.toString() ?? '',
    gameId: json['gameId']?.toString() ?? '',
    createdAt:
        DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
        DateTime.now(),
    updatedAt:
        DateTime.tryParse(json['updatedAt']?.toString() ?? '') ??
        DateTime.now(),
    status: GameSessionStatus.values.firstWhere(
      (item) => item.name == json['status'],
      orElse: () => GameSessionStatus.draft,
    ),
    host: json['host'] is Map
        ? GameHost.fromJson(json['host'] as Map)
        : const GameHost.system(),
    participants: (json['participants'] as List? ?? const [])
        .whereType<Map>()
        .map(GameParticipant.fromJson),
    currentRound: (json['currentRound'] as num?)?.toInt() ?? 0,
    gameState: json['gameState'] is Map
        ? GameStateSnapshotCodec.decode(json['gameState'] as Map)
        : const BaseGameState(),
    messages: (json['messages'] as List? ?? const [])
        .whereType<Map>()
        .map(GameMessage.fromJson)
        .toList(),
    schemaVersion:
        (json['schemaVersion'] as num?)?.toInt() ?? currentSchemaVersion,
  );
  factory GameSession.decode(String raw) =>
      GameSession.fromJson(jsonDecode(raw) as Map);
}

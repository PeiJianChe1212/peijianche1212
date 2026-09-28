import '../models/game_models.dart';
import 'turtle_soup_reasoning_ledger.dart';

enum TurtleSoupPhase { ready, questioning, guessing, revealed, finished }

enum TurtleSoupDifficulty { easy, normal, hard }

class TurtleSoupPuzzle {
  const TurtleSoupPuzzle({
    required this.id,
    required this.title,
    required this.surface,
    required this.truth,
    required this.hints,
    required this.requiredTruthPoints,
    this.difficulty = TurtleSoupDifficulty.easy,
    this.reasoningDimensions = const [],
    this.yesKeywords = const [],
    this.noKeywords = const [],
    this.irrelevantKeywords = const [],
  });
  final String id;
  final String title;
  final String surface;
  final String truth;
  final List<String> hints;
  final List<String> requiredTruthPoints;
  final TurtleSoupDifficulty difficulty;
  final List<String> reasoningDimensions;
  final List<String> yesKeywords;
  final List<String> noKeywords;
  final List<String> irrelevantKeywords;
}

class TurtleSoupState extends GameStateSnapshot {
  const TurtleSoupState({
    required this.puzzleId,
    required this.title,
    required this.surface,
    required this.truth,
    required this.hints,
    this.usedHintCount = 0,
    this.questionCount = 0,
    this.guessCount = 0,
    this.phase = TurtleSoupPhase.ready,
    this.isSolved = false,
    this.startedAt,
    this.finishedAt,
    this.solvedByParticipantId,
    this.reasoningLedger,
  });

  final String puzzleId;
  final String title;
  final String surface;
  final String truth;
  final List<String> hints;
  final int usedHintCount;
  final int questionCount;
  final int guessCount;
  final TurtleSoupPhase phase;
  final bool isSolved;
  final DateTime? startedAt;
  final DateTime? finishedAt;
  final String? solvedByParticipantId;
  final PublicReasoningLedger? reasoningLedger;

  @override
  String get stateType => 'turtle_soup_v1';

  TurtleSoupState copyWith({
    int? usedHintCount,
    int? questionCount,
    int? guessCount,
    TurtleSoupPhase? phase,
    bool? isSolved,
    DateTime? startedAt,
    DateTime? finishedAt,
    String? solvedByParticipantId,
    PublicReasoningLedger? reasoningLedger,
  }) => TurtleSoupState(
    puzzleId: puzzleId,
    title: title,
    surface: surface,
    truth: truth,
    hints: hints,
    usedHintCount: usedHintCount ?? this.usedHintCount,
    questionCount: questionCount ?? this.questionCount,
    guessCount: guessCount ?? this.guessCount,
    phase: phase ?? this.phase,
    isSolved: isSolved ?? this.isSolved,
    startedAt: startedAt ?? this.startedAt,
    finishedAt: finishedAt ?? this.finishedAt,
    solvedByParticipantId: solvedByParticipantId ?? this.solvedByParticipantId,
    reasoningLedger: reasoningLedger ?? this.reasoningLedger,
  );

  @override
  Map<String, dynamic> toJson() => {
    'stateType': stateType,
    'puzzleId': puzzleId,
    'title': title,
    'surface': surface,
    'truth': truth,
    'hints': hints,
    'usedHintCount': usedHintCount,
    'questionCount': questionCount,
    'guessCount': guessCount,
    'phase': phase.name,
    'isSolved': isSolved,
    if (startedAt != null) 'startedAt': startedAt!.toIso8601String(),
    if (finishedAt != null) 'finishedAt': finishedAt!.toIso8601String(),
    if (solvedByParticipantId != null)
      'solvedByParticipantId': solvedByParticipantId,
    if (reasoningLedger != null) 'reasoningLedger': reasoningLedger!.toJson(),
  };

  factory TurtleSoupState.fromJson(Map<dynamic, dynamic> json) =>
      TurtleSoupState(
        puzzleId: json['puzzleId']?.toString() ?? '',
        title: json['title']?.toString() ?? '',
        surface: json['surface']?.toString() ?? '',
        truth: json['truth']?.toString() ?? '',
        hints: (json['hints'] as List? ?? const [])
            .map((item) => item.toString())
            .toList(),
        usedHintCount: (json['usedHintCount'] as num?)?.toInt() ?? 0,
        questionCount: (json['questionCount'] as num?)?.toInt() ?? 0,
        guessCount: (json['guessCount'] as num?)?.toInt() ?? 0,
        phase: TurtleSoupPhase.values.firstWhere(
          (item) => item.name == json['phase'],
          orElse: () => TurtleSoupPhase.ready,
        ),
        isSolved: json['isSolved'] == true,
        startedAt: DateTime.tryParse(json['startedAt']?.toString() ?? ''),
        finishedAt: DateTime.tryParse(json['finishedAt']?.toString() ?? ''),
        solvedByParticipantId: json['solvedByParticipantId']?.toString(),
        reasoningLedger: json['reasoningLedger'] is Map
            ? PublicReasoningLedger.fromJson(json['reasoningLedger'] as Map)
            : null,
      );
}

void registerTurtleSoupStateCodec() =>
    GameStateSnapshotCodec.register('turtle_soup_v1', TurtleSoupState.fromJson);

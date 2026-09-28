import 'dart:async';
import 'dart:convert';

import '../../ai/model_hub.dart';
import '../models/game_models.dart';
import '../services/game_room_visibility.dart';
import 'turtle_soup_models.dart';

class TurtleSoupPublicSummaryEntry {
  const TurtleSoupPublicSummaryEntry({
    required this.senderId,
    required this.type,
    required this.content,
  });

  final String senderId;
  final GameMessageType type;
  final String content;

  Map<String, Object> toJson() => {
    'senderId': senderId,
    'type': type.name,
    'content': content,
  };
}

/// Deliberately contains public presentation data only. Hidden puzzle fields do
/// not exist on this type and therefore cannot be serialized into a prompt.
class TurtleSoupPublicSummaryView {
  const TurtleSoupPublicSummaryView({
    required this.title,
    required this.surface,
    required this.phase,
    required this.questionCount,
    required this.guessCount,
    required this.usedHintCount,
    required this.entries,
  });

  final String title;
  final String surface;
  final String phase;
  final int questionCount;
  final int guessCount;
  final int usedHintCount;
  final List<TurtleSoupPublicSummaryEntry> entries;

  int get inquiryCount => entries
      .where(
        (entry) => {
          GameMessageType.question,
          GameMessageType.guess,
        }.contains(entry.type),
      )
      .length;

  Map<String, Object> toJson() => {
    'title': title,
    'surface': surface,
    'phase': phase,
    'stats': {
      'questionCount': questionCount,
      'guessCount': guessCount,
      'usedHintCount': usedHintCount,
    },
    'publicTimeline': entries.map((entry) => entry.toJson()).toList(),
  };
}

class TurtleSoupPublicSummaryViewBuilder {
  const TurtleSoupPublicSummaryViewBuilder();

  TurtleSoupPublicSummaryView build(GameSession session) {
    final state = session.gameState as TurtleSoupState;
    final entries = GameRoomVisibility.visibleMessages(session)
        .where(
          (message) => {
            GameMessageType.system,
            GameMessageType.host,
            GameMessageType.participant,
            GameMessageType.narration,
            GameMessageType.puzzle,
            GameMessageType.question,
            GameMessageType.answer,
            GameMessageType.hint,
            GameMessageType.guess,
          }.contains(message.type),
        )
        .map(
          (message) => TurtleSoupPublicSummaryEntry(
            senderId: message.senderId,
            type: message.type,
            content: message.content,
          ),
        )
        .toList(growable: false);
    return TurtleSoupPublicSummaryView(
      title: state.title,
      surface: state.surface,
      phase: state.phase.name,
      questionCount: state.questionCount,
      guessCount: state.guessCount,
      usedHintCount: state.usedHintCount,
      entries: List.unmodifiable(entries),
    );
  }
}

abstract interface class TurtleSoupSummaryModelGateway {
  Future<String> complete({required List<Map<String, dynamic>> messages});
}

class ModelHubTurtleSoupSummaryGateway
    implements TurtleSoupSummaryModelGateway {
  ModelHubTurtleSoupSummaryGateway({ModelHub? modelHub})
    : _modelHub = modelHub ?? ModelHub();

  final ModelHub _modelHub;

  @override
  Future<String> complete({
    required List<Map<String, dynamic>> messages,
  }) async {
    final provider = await _modelHub.chatProvider();
    return provider.complete(
      messages: messages,
      temperature: .15,
      maxTokens: 320,
    );
  }
}

class TurtleSoupPublicSummary {
  const TurtleSoupPublicSummary({
    this.confirmed = const [],
    this.ruledOut = const [],
    this.unresolved = const [],
    this.fallbackMessage,
  });

  static const insufficient = TurtleSoupPublicSummary(
    fallbackMessage: '目前的信息还比较少，再问几步后我帮你整理。',
  );

  final List<String> confirmed;
  final List<String> ruledOut;
  final List<String> unresolved;
  final String? fallbackMessage;

  bool get hasSections =>
      confirmed.isNotEmpty || ruledOut.isNotEmpty || unresolved.isNotEmpty;
}

class TurtleSoupPublicSummaryService {
  TurtleSoupPublicSummaryService({
    TurtleSoupSummaryModelGateway? gateway,
    this.timeout = const Duration(seconds: 15),
  }) : _gateway = gateway ?? ModelHubTurtleSoupSummaryGateway();

  final TurtleSoupSummaryModelGateway _gateway;
  final Duration timeout;

  Future<TurtleSoupPublicSummary> summarize(
    TurtleSoupPublicSummaryView view,
  ) async {
    if (view.inquiryCount < 2) return TurtleSoupPublicSummary.insufficient;
    try {
      final raw = await _gateway
          .complete(messages: _messages(view))
          .timeout(timeout);
      final parsed = _parse(raw, view);
      return parsed.hasSections ? parsed : TurtleSoupPublicSummary.insufficient;
    } catch (_) {
      return TurtleSoupPublicSummary.insufficient;
    }
  }

  List<Map<String, dynamic>> _messages(TurtleSoupPublicSummaryView view) => [
    {
      'role': 'system',
      'content':
          '''
你只负责整理海龟汤玩家已经公开看到的信息，不推理新答案，不补充新线索。
只能使用输入中的 surface 与 publicTimeline。不得提出记录中从未出现的新方向。
输出简短 JSON，不要 Markdown，不要解释：
{"confirmed":["..."],"ruledOut":["..."],"unresolved":["..."]}
无法可靠整理的栏目输出空数组。每项必须能在公开记录中找到直接语义依据。
'''
              .trim(),
    },
    {'role': 'user', 'content': jsonEncode(view.toJson())},
  ];

  TurtleSoupPublicSummary _parse(String raw, TurtleSoupPublicSummaryView view) {
    final decoded = jsonDecode(
      raw
          .trim()
          .replaceFirst(RegExp(r'^```(?:json)?\s*'), '')
          .replaceFirst(RegExp(r'\s*```$'), ''),
    );
    if (decoded is! Map) return TurtleSoupPublicSummary.insufficient;
    final evidence = [
      view.surface,
      ...view.entries.map((entry) => entry.content),
    ];
    List<String> section(String key) {
      final values = decoded[key];
      if (values is! List) return const [];
      return values
          .whereType<String>()
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty && item.length <= 100)
          .where((item) => _hasPublicSupport(item, evidence))
          .take(5)
          .toList(growable: false);
    }

    return TurtleSoupPublicSummary(
      confirmed: section('confirmed'),
      ruledOut: section('ruledOut'),
      unresolved: section('unresolved'),
    );
  }

  bool _hasPublicSupport(String item, List<String> evidence) {
    final normalized = _normalize(item);
    if (normalized.length < 4) return false;
    final itemBigrams = _bigrams(normalized).toSet();
    return evidence.any((source) {
      final sourceBigrams = _bigrams(_normalize(source)).toSet();
      if (sourceBigrams.isEmpty) return false;
      final overlap = itemBigrams.intersection(sourceBigrams).length;
      return overlap >= 2 && overlap / itemBigrams.length >= .12;
    });
  }

  String _normalize(String value) => value.toLowerCase().replaceAll(
    RegExp(r'[\s\p{P}\p{S}]', unicode: true),
    '',
  );

  List<String> _bigrams(String value) => [
    for (var index = 0; index < value.length - 1; index++)
      value.substring(index, index + 2),
  ];
}

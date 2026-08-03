enum EchoDailyLifeKind { work, interest, environment, mood, arrival }

class EchoDailyLife {
  const EchoDailyLife({
    required this.kind,
    required this.content,
    required this.summary,
  });

  final EchoDailyLifeKind kind;
  final String content;
  final String summary;
}

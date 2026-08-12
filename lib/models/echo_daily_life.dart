import 'echo_item.dart';

enum EchoDailyLifeKind {
  daily,
  work,
  interest,
  environment,
  mood,
  interaction,
  arrival,
  collection,
}

class EchoDailyLife {
  const EchoDailyLife({
    required this.kind,
    required this.content,
    required this.summary,
    this.sourceEvent = '',
    this.characterState = '',
  });

  final EchoDailyLifeKind kind;
  final String content;
  final String summary;
  final String sourceEvent;
  final String characterState;

  EchoLifeType get lifeType => switch (kind) {
    EchoDailyLifeKind.daily => EchoLifeType.daily,
    EchoDailyLifeKind.work => EchoLifeType.workStudy,
    EchoDailyLifeKind.interest => EchoLifeType.interest,
    EchoDailyLifeKind.environment => EchoLifeType.environment,
    EchoDailyLifeKind.mood => EchoLifeType.mood,
    EchoDailyLifeKind.interaction => EchoLifeType.interaction,
    EchoDailyLifeKind.arrival => EchoLifeType.arrival,
    EchoDailyLifeKind.collection => EchoLifeType.collection,
  };
}

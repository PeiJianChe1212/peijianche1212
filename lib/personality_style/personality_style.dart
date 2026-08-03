enum StyleTone { warm, cold, playful, calm, dominant, soft, coldButCaring }

enum StyleLength { short, medium, long }

enum EmotionExpression { direct, implicit, teasing, reserved }

enum StyleInitiative { low, medium, high }

enum HumorLevel { low, medium, high }

enum Formality { casual, neutral, formal }

enum SpeechPattern { concise, balanced, expressive }

extension StyleToneKey on StyleTone {
  String get key => switch (this) {
    StyleTone.coldButCaring => 'cold_but_caring',
    _ => name,
  };
}

class PersonalityStyle {
  const PersonalityStyle({
    required this.tone,
    required this.speechPattern,
    required this.emotionExpression,
    required this.initiative,
    required this.humorLevel,
    required this.formality,
    required this.length,
  });

  final StyleTone tone;
  final SpeechPattern speechPattern;
  final EmotionExpression emotionExpression;
  final StyleInitiative initiative;
  final HumorLevel humorLevel;
  final Formality formality;
  final StyleLength length;

  /// 只输出表达方向，不包含任何可直接发送的回复正文。
  String toPromptSection() =>
      '''【Personality Style｜仅控制表达习惯】
tone=${tone.key}
speech_pattern=${speechPattern.name}
emotion=${emotionExpression.name}
initiative=${initiative.name}
humor=${humorLevel.name}
formality=${formality.name}
length=${length.name}
保持这些表达倾向，但不要复述字段，不要据此虚构事实，不要把风格说明写进回复正文。''';
}

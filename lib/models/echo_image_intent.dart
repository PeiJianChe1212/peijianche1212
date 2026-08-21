enum EchoImageSubjectType {
  object,
  food,
  environment,
  scenery,
  workStudy,
  shopping,
  travel,
  pet,
  screenshotLike,
  character,
  selfie,
  outfit,
  group,
  other,
}

enum EchoCharacterPresence { none, optional, required }

class EchoImageIntent {
  const EchoImageIntent({
    required this.shouldGenerateImage,
    required this.subjectType,
    required this.characterPresence,
    required this.visualFocus,
    required this.mood,
    this.requiredCharacterIds = const [],
    this.sourceMomentId = '',
    this.sourceLifeEventId = '',
  });

  final bool shouldGenerateImage;
  final EchoImageSubjectType subjectType;
  final EchoCharacterPresence characterPresence;
  final String visualFocus;
  final String mood;
  final List<String> requiredCharacterIds;
  final String sourceMomentId;
  final String sourceLifeEventId;
}

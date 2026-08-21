enum PeiLinkVisualSubject {
  object,
  food,
  environment,
  scenery,
  workStudy,
  shopping,
  travel,
  pet,
  interface,
  character,
  selfie,
  outfit,
  group,
  other,
}

enum PeiLinkCharacterPresence { none, optional, required }

/// Cross-surface visual requirements after a scene-level Intent has decided
/// what should be shown. Echo, Chat and Group keep their own semantic Intent.
class PeiLinkVisualIntent {
  const PeiLinkVisualIntent({
    required this.subject,
    required this.characterPresence,
    required this.visualFocus,
    this.mood = '',
    this.requiredCharacterIds = const [],
    this.includeEyes = false,
    this.includeClothing = false,
    this.includeBodyProportions = false,
    this.compositionHint = '',
  });

  final PeiLinkVisualSubject subject;
  final PeiLinkCharacterPresence characterPresence;
  final String visualFocus;
  final String mood;
  final List<String> requiredCharacterIds;
  final bool includeEyes;
  final bool includeClothing;
  final bool includeBodyProportions;
  final String compositionHint;
}

/// Reserved scene-level contract for a future mature group image entry.
/// It deliberately does not create a Group image feature by itself.
class GroupImageIntent {
  const GroupImageIntent({
    required this.visualFocus,
    this.requiredCharacterIds = const [],
    this.mood = '',
  });

  final String visualFocus;
  final List<String> requiredCharacterIds;
  final String mood;
}

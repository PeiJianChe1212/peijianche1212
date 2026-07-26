enum RelationshipBoundaryLevel {
  private,
  sharedWorld,
  cooperative,
}

class RelationshipBoundary {
  const RelationshipBoundary({
    required this.characterId,
    this.level = RelationshipBoundaryLevel.sharedWorld,
    this.allowSharedEvents = true,
    this.allowPublicMentions = true,
    this.allowPrivateMemoryAccess = false,
    this.allowSpeakingForOthers = false,
    this.allowExclusiveClaims = false,
  });

  final String characterId;
  final RelationshipBoundaryLevel level;
  final bool allowSharedEvents;
  final bool allowPublicMentions;
  final bool allowPrivateMemoryAccess;
  final bool allowSpeakingForOthers;
  final bool allowExclusiveClaims;
}

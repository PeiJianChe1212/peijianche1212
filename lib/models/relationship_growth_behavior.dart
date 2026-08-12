class RelationshipGrowthBehavior {
  const RelationshipGrowthBehavior({
    required this.shareChanceModifier,
    required this.personalSharingBias,
    required this.memoryReferenceBias,
    required this.specialEventBias,
  });

  final int shareChanceModifier;
  final double personalSharingBias;
  final double memoryReferenceBias;
  final double specialEventBias;

  factory RelationshipGrowthBehavior.forLevel(int level) {
    final safe = level.clamp(1, 100);
    if (safe <= 10) {
      return const RelationshipGrowthBehavior(
        shareChanceModifier: -4,
        personalSharingBias: 0.08,
        memoryReferenceBias: 0.02,
        specialEventBias: 0.01,
      );
    }
    if (safe <= 30) {
      return const RelationshipGrowthBehavior(
        shareChanceModifier: 2,
        personalSharingBias: 0.18,
        memoryReferenceBias: 0.08,
        specialEventBias: 0.03,
      );
    }
    if (safe <= 50) {
      return const RelationshipGrowthBehavior(
        shareChanceModifier: 7,
        personalSharingBias: 0.32,
        memoryReferenceBias: 0.18,
        specialEventBias: 0.08,
      );
    }
    if (safe <= 70) {
      return const RelationshipGrowthBehavior(
        shareChanceModifier: 11,
        personalSharingBias: 0.44,
        memoryReferenceBias: 0.28,
        specialEventBias: 0.14,
      );
    }
    if (safe <= 90) {
      return const RelationshipGrowthBehavior(
        shareChanceModifier: 14,
        personalSharingBias: 0.56,
        memoryReferenceBias: 0.4,
        specialEventBias: 0.2,
      );
    }
    return const RelationshipGrowthBehavior(
      shareChanceModifier: 17,
      personalSharingBias: 0.65,
      memoryReferenceBias: 0.52,
      specialEventBias: 0.28,
    );
  }
}

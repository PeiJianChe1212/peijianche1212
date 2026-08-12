import 'echo_item.dart';

class EchoSpaceSummary {
  const EchoSpaceSummary({
    required this.currentStatus,
    required this.recentActivity,
    required this.interactionCount,
    required this.sharedExperienceCount,
  });

  final String currentStatus;
  final String recentActivity;
  final int interactionCount;
  final int sharedExperienceCount;

  factory EchoSpaceSummary.fromExistingData({
    required List<EchoItem> echoes,
    required int interactionCount,
    required int sharedExperienceCount,
    DateTime? now,
  }) {
    final sorted = [...echoes]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final latest = sorted.firstOrNull;
    final status = latest?.characterState.trim() ?? '';
    final reference = now ?? DateTime.now();
    final recentCount = sorted.where((item) {
      final age = reference.difference(item.createdAt);
      return !age.isNegative && age <= const Duration(days: 7);
    }).length;

    return EchoSpaceSummary(
      currentStatus: status.isNotEmpty
          ? status
          : latest == null
          ? '安静生活中'
          : '${latest.lifeType.label}中',
      recentActivity: recentCount == 0 ? '最近暂无新动态' : '近7天发布了 $recentCount 条动态',
      interactionCount: interactionCount < 0 ? 0 : interactionCount,
      sharedExperienceCount: sharedExperienceCount < 0
          ? 0
          : sharedExperienceCount,
    );
  }
}

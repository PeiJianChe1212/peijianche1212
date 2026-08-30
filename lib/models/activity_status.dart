class ActivityStatus {
  const ActivityStatus({
    required this.id,
    required this.label,
    required this.emoji,
    required this.detail,
    required this.promptGuidance,
    this.isSleeping = false,
  });

  final String id;
  final String label;
  final String emoji;
  final String detail;
  final String promptGuidance;
  final bool isSleeping;

  String get displayText => '$label $emoji';

  String toPromptSection() {
    return '''
【当前角色状态】
当前活动：$label
状态说明：$detail

$promptGuidance

把这个状态当作自然的生活背景，而不是必须反复表演的剧情。
只有在用户刚来找你、话题与当前活动有关，或状态会明显影响反应时，才轻轻体现。
不要每条回复都重复描述当前活动，不要输出冗长小说旁白。
''';
  }
}

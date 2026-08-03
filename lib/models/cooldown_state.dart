enum ChatRelationshipState { normal, cooldown }

class CooldownState {
  const CooldownState({
    required this.state,
    this.startTime,
    this.endTime,
    this.reason,
  });

  final ChatRelationshipState state;
  final DateTime? startTime;
  final DateTime? endTime;
  final String? reason;

  const CooldownState.normal()
    : state = ChatRelationshipState.normal,
      startTime = null,
      endTime = null,
      reason = null;

  bool isInCooldownAt(DateTime time) {
    if (state != ChatRelationshipState.cooldown) return false;
    final end = endTime;
    return end != null && time.isBefore(end);
  }

  Map<String, dynamic> toJson() => {
    'state': state.name,
    'startTime': startTime?.toIso8601String(),
    'endTime': endTime?.toIso8601String(),
    'reason': reason,
  };

  factory CooldownState.fromJson(Map<dynamic, dynamic> json) {
    final state = ChatRelationshipState.values.firstWhere(
      (value) => value.name == json['state']?.toString(),
      orElse: () => ChatRelationshipState.normal,
    );
    if (state == ChatRelationshipState.normal) {
      return const CooldownState.normal();
    }

    final startTime = DateTime.tryParse(json['startTime']?.toString() ?? '');
    final endTime = DateTime.tryParse(json['endTime']?.toString() ?? '');
    if (startTime == null || endTime == null || !endTime.isAfter(startTime)) {
      return const CooldownState.normal();
    }

    final rawReason = json['reason']?.toString().trim();
    return CooldownState(
      state: ChatRelationshipState.cooldown,
      startTime: startTime,
      endTime: endTime,
      reason: rawReason == null || rawReason.isEmpty ? null : rawReason,
    );
  }
}

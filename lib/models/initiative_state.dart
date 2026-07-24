class InitiativeState {
  const InitiativeState({
    required this.dateKey,
    required this.sentCount,
    required this.unreadCount,
    required this.usedSlots,
    this.usedLifeMomentIds = const [],
    this.lastSentAt,
  });

  final String dateKey;
  final int sentCount;
  final int unreadCount;
  final List<String> usedSlots;
  final List<String> usedLifeMomentIds;
  final DateTime? lastSentAt;

  factory InitiativeState.empty([DateTime? now]) {
    final time = now ?? DateTime.now();
    return InitiativeState(
      dateKey: _dateKey(time),
      sentCount: 0,
      unreadCount: 0,
      usedSlots: const [],
      usedLifeMomentIds: const [],
    );
  }

  InitiativeState normalized(DateTime now) {
    if (dateKey == _dateKey(now)) return this;
    return InitiativeState.empty(now);
  }

  InitiativeState copyWith({
    String? dateKey,
    int? sentCount,
    int? unreadCount,
    List<String>? usedSlots,
    List<String>? usedLifeMomentIds,
    DateTime? lastSentAt,
    bool clearLastSentAt = false,
  }) {
    return InitiativeState(
      dateKey: dateKey ?? this.dateKey,
      sentCount: sentCount ?? this.sentCount,
      unreadCount: unreadCount ?? this.unreadCount,
      usedSlots: usedSlots ?? this.usedSlots,
      usedLifeMomentIds: usedLifeMomentIds ?? this.usedLifeMomentIds,
      lastSentAt: clearLastSentAt ? null : (lastSentAt ?? this.lastSentAt),
    );
  }

  Map<String, dynamic> toJson() => {
        'dateKey': dateKey,
        'sentCount': sentCount,
        'unreadCount': unreadCount,
        'usedSlots': usedSlots,
        'usedLifeMomentIds': usedLifeMomentIds,
        'lastSentAt': lastSentAt?.toIso8601String(),
      };

  factory InitiativeState.fromJson(Map<dynamic, dynamic> json) {
    return InitiativeState(
      dateKey: json['dateKey']?.toString() ?? '',
      sentCount: (json['sentCount'] as num?)?.toInt() ?? 0,
      unreadCount: (json['unreadCount'] as num?)?.toInt() ?? 0,
      usedSlots: (json['usedSlots'] as List?)
              ?.map((item) => item.toString())
              .toList() ??
          const [],
      usedLifeMomentIds: (json['usedLifeMomentIds'] as List?)
              ?.map((item) => item.toString())
              .toList() ??
          const [],
      lastSentAt: DateTime.tryParse(json['lastSentAt']?.toString() ?? ''),
    );
  }

  static String _dateKey(DateTime time) =>
      '${time.year}-${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')}';
}

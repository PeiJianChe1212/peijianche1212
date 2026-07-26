class AutoEchoState {
  const AutoEchoState({
    required this.dateKey,
    required this.publishedToday,
    required this.recentSummaries,
    this.lastPublishedAt,
    this.lastCheckedAt,
  });

  final String dateKey;
  final int publishedToday;
  final DateTime? lastPublishedAt;
  final DateTime? lastCheckedAt;
  final List<String> recentSummaries;

  factory AutoEchoState.initial(DateTime now) => AutoEchoState(
        dateKey: _key(now),
        publishedToday: 0,
        recentSummaries: const [],
      );

  AutoEchoState normalized(DateTime now) {
    if (dateKey == _key(now)) return this;
    return AutoEchoState(
      dateKey: _key(now),
      publishedToday: 0,
      lastPublishedAt: lastPublishedAt,
      lastCheckedAt: lastCheckedAt,
      recentSummaries: recentSummaries,
    );
  }

  AutoEchoState copyWith({
    String? dateKey,
    int? publishedToday,
    DateTime? lastPublishedAt,
    DateTime? lastCheckedAt,
    List<String>? recentSummaries,
  }) => AutoEchoState(
        dateKey: dateKey ?? this.dateKey,
        publishedToday: publishedToday ?? this.publishedToday,
        lastPublishedAt: lastPublishedAt ?? this.lastPublishedAt,
        lastCheckedAt: lastCheckedAt ?? this.lastCheckedAt,
        recentSummaries: recentSummaries ?? this.recentSummaries,
      );

  Map<String, dynamic> toJson() => {
        'dateKey': dateKey,
        'publishedToday': publishedToday,
        'lastPublishedAt': lastPublishedAt?.toIso8601String(),
        'lastCheckedAt': lastCheckedAt?.toIso8601String(),
        'recentSummaries': recentSummaries,
      };

  factory AutoEchoState.fromJson(Map<dynamic, dynamic> json) => AutoEchoState(
        dateKey: json['dateKey']?.toString() ?? '',
        publishedToday: int.tryParse(json['publishedToday']?.toString() ?? '') ?? 0,
        lastPublishedAt: DateTime.tryParse(json['lastPublishedAt']?.toString() ?? ''),
        lastCheckedAt: DateTime.tryParse(json['lastCheckedAt']?.toString() ?? ''),
        recentSummaries: json['recentSummaries'] is List
            ? (json['recentSummaries'] as List).map((e) => e.toString()).toList()
            : const [],
      );

  static String _key(DateTime value) =>
      '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
}

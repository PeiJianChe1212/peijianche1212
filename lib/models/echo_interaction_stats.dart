enum EchoHeatLevel { calm, popular, commemorative }

enum EchoLikeType { real, virtual }

extension EchoHeatLevelText on EchoHeatLevel {
  String get label => switch (this) {
    EchoHeatLevel.calm => '🌱 平淡',
    EchoHeatLevel.popular => '🔥 热门',
    EchoHeatLevel.commemorative => '✨ 纪念',
  };
}

class EchoInteractionStats {
  const EchoInteractionStats({
    required this.echoId,
    required this.viewCount,
    required this.likeCount,
    required this.commentCount,
    required this.collectCount,
    required this.heatLevel,
    this.realLikeCount = 0,
    int? virtualLikeCount,
  }) : virtualLikeCount = virtualLikeCount ?? likeCount;

  final String echoId;
  final int viewCount;
  final int likeCount;
  final int commentCount;
  final int collectCount;
  final EchoHeatLevel heatLevel;
  final int realLikeCount;
  final int virtualLikeCount;

  Map<String, dynamic> toJson() => {
    'echoId': echoId,
    'viewCount': viewCount,
    'likeCount': likeCount,
    'commentCount': commentCount,
    'collectCount': collectCount,
    'heatLevel': heatLevel.name,
    'likes': [
      {'likeType': 'real', 'count': realLikeCount},
      {'likeType': 'virtual', 'count': virtualLikeCount},
    ],
  };

  factory EchoInteractionStats.fromJson(Map<dynamic, dynamic> json) =>
      EchoInteractionStats(
        echoId: json['echoId']?.toString() ?? '',
        viewCount: _count(json['viewCount']),
        likeCount: _count(json['likeCount']),
        commentCount: _count(json['commentCount']),
        collectCount: _count(json['collectCount']),
        heatLevel: EchoHeatLevel.values.firstWhere(
          (value) => value.name == json['heatLevel']?.toString(),
          orElse: () => _count(json['viewCount']) >= 200
              ? EchoHeatLevel.popular
              : EchoHeatLevel.calm,
        ),
        realLikeCount: _likeCount(json, 'real'),
        virtualLikeCount: _likeCount(
          json,
          'virtual',
          fallback: json['likeCount'],
        ),
      );

  static int _likeCount(
    Map<dynamic, dynamic> json,
    String type, {
    dynamic fallback,
  }) {
    final likes = json['likes'];
    if (likes is List) {
      for (final raw in likes.whereType<Map>()) {
        if (raw['likeType']?.toString() == type) return _count(raw['count']);
      }
    }
    return _count(fallback);
  }

  static int _count(dynamic value) =>
      (int.tryParse(value?.toString() ?? '') ?? 0).clamp(0, 100000000);
}

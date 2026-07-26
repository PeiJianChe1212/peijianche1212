enum WorldEventType {
  time,
  weather,
  location,
  shop,
  npc,
  festival,
  news,
  publicEvent,
  encounter,
  mapState,
  other,
}

enum WorldEventStatus {
  scheduled,
  active,
  ended,
  cancelled,
}

enum WorldEventEvidence {
  confirmed,
  forecast,
  reported,
  inferred,
}

class WorldEvent {
  const WorldEvent({
    required this.id,
    required this.type,
    required this.title,
    required this.description,
    required this.startAt,
    required this.createdAt,
    this.endAt,
    this.status = WorldEventStatus.active,
    this.locationId,
    this.locationName,
    this.participantCharacterIds = const [],
    this.tags = const [],
    this.source = 'manual',
    this.evidence = WorldEventEvidence.confirmed,
    this.confidence = 0.8,
    this.metadata = const {},
  });

  final String id;
  final WorldEventType type;
  final String title;
  final String description;
  final DateTime startAt;
  final DateTime? endAt;
  final DateTime createdAt;
  final WorldEventStatus status;
  final String? locationId;
  final String? locationName;
  final List<String> participantCharacterIds;
  final List<String> tags;
  final String source;
  final WorldEventEvidence evidence;
  final double confidence;
  final Map<String, dynamic> metadata;

  double get normalizedConfidence => confidence.clamp(0.0, 1.0).toDouble();

  bool get isStrongEvidence =>
      evidence == WorldEventEvidence.confirmed && normalizedConfidence >= 0.75;

  bool isActiveAt(DateTime time) {
    if (status == WorldEventStatus.cancelled ||
        status == WorldEventStatus.ended) {
      return false;
    }
    if (time.isBefore(startAt)) return false;
    final finish = endAt;
    return finish == null || time.isBefore(finish);
  }

  bool isScheduledWithin(DateTime from, DateTime until) {
    if (status == WorldEventStatus.cancelled ||
        status == WorldEventStatus.ended) {
      return false;
    }
    return startAt.isAfter(from) && !startAt.isAfter(until);
  }

  WorldEventStatus statusAt(DateTime time) {
    if (status == WorldEventStatus.cancelled) {
      return WorldEventStatus.cancelled;
    }
    final finish = endAt;
    if (status == WorldEventStatus.ended ||
        (finish != null && !time.isBefore(finish))) {
      return WorldEventStatus.ended;
    }
    if (time.isBefore(startAt)) return WorldEventStatus.scheduled;
    return WorldEventStatus.active;
  }

  String? get stateKey {
    final value = metadata['stateKey']?.toString().trim() ?? '';
    return value.isEmpty ? null : value;
  }

  bool appliesToCharacter(String characterId) {
    return participantCharacterIds.isEmpty ||
        participantCharacterIds.contains(characterId);
  }

  WorldEvent copyWith({
    String? id,
    WorldEventType? type,
    String? title,
    String? description,
    DateTime? startAt,
    DateTime? endAt,
    bool clearEndAt = false,
    DateTime? createdAt,
    WorldEventStatus? status,
    String? locationId,
    bool clearLocationId = false,
    String? locationName,
    bool clearLocationName = false,
    List<String>? participantCharacterIds,
    List<String>? tags,
    String? source,
    WorldEventEvidence? evidence,
    double? confidence,
    Map<String, dynamic>? metadata,
  }) {
    return WorldEvent(
      id: id ?? this.id,
      type: type ?? this.type,
      title: title ?? this.title,
      description: description ?? this.description,
      startAt: startAt ?? this.startAt,
      endAt: clearEndAt ? null : endAt ?? this.endAt,
      createdAt: createdAt ?? this.createdAt,
      status: status ?? this.status,
      locationId: clearLocationId ? null : locationId ?? this.locationId,
      locationName:
          clearLocationName ? null : locationName ?? this.locationName,
      participantCharacterIds:
          participantCharacterIds ?? this.participantCharacterIds,
      tags: tags ?? this.tags,
      source: source ?? this.source,
      evidence: evidence ?? this.evidence,
      confidence: confidence ?? this.confidence,
      metadata: metadata ?? this.metadata,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'title': title,
        'description': description,
        'startAt': startAt.toIso8601String(),
        'endAt': endAt?.toIso8601String(),
        'createdAt': createdAt.toIso8601String(),
        'status': status.name,
        'locationId': locationId,
        'locationName': locationName,
        'participantCharacterIds': participantCharacterIds,
        'tags': tags,
        'source': source,
        'evidence': evidence.name,
        'confidence': normalizedConfidence,
        'metadata': metadata,
      };

  factory WorldEvent.fromJson(Map<dynamic, dynamic> json) {
    return WorldEvent(
      id: _readText(json['id']).isNotEmpty
          ? _readText(json['id'])
          : 'world_${DateTime.now().microsecondsSinceEpoch}',
      type: _readType(json['type']),
      title: _readText(json['title']),
      description: _readText(json['description']),
      startAt: DateTime.tryParse(_readText(json['startAt'])) ?? DateTime.now(),
      endAt: DateTime.tryParse(_readText(json['endAt'])),
      createdAt:
          DateTime.tryParse(_readText(json['createdAt'])) ?? DateTime.now(),
      status: _readStatus(json['status']),
      locationId: _readNullableText(json['locationId']),
      locationName: _readNullableText(json['locationName']),
      participantCharacterIds: _readStringList(
        json['participantCharacterIds'],
      ),
      tags: _readStringList(json['tags']),
      source: _readText(json['source']).isEmpty
          ? 'manual'
          : _readText(json['source']),
      evidence: _readEvidence(json['evidence'], json['source']),
      confidence: _readConfidence(json['confidence'], json['source']),
      metadata: json['metadata'] is Map
          ? Map<String, dynamic>.from(json['metadata'] as Map)
          : const {},
    );
  }

  static String _readText(dynamic value) => value?.toString().trim() ?? '';

  static String? _readNullableText(dynamic value) {
    final text = _readText(value);
    return text.isEmpty ? null : text;
  }

  static List<String> _readStringList(dynamic value) {
    if (value is! List) return const [];
    return value
        .map(_readText)
        .where((item) => item.isNotEmpty)
        .toSet()
        .toList();
  }


  static WorldEventEvidence _readEvidence(dynamic value, dynamic source) {
    final name = _readText(value);
    if (name.isNotEmpty) {
      return WorldEventEvidence.values.firstWhere(
        (item) => item.name == name,
        orElse: () => WorldEventEvidence.confirmed,
      );
    }
    return _readText(source) == 'device_clock'
        ? WorldEventEvidence.confirmed
        : WorldEventEvidence.confirmed;
  }

  static double _readConfidence(dynamic value, dynamic source) {
    final parsed = value is num ? value.toDouble() : double.tryParse(_readText(value));
    if (parsed != null) return parsed.clamp(0.0, 1.0).toDouble();
    return _readText(source) == 'device_clock' ? 1.0 : 0.8;
  }

  static WorldEventType _readType(dynamic value) {
    final name = _readText(value);
    return WorldEventType.values.firstWhere(
      (item) => item.name == name,
      orElse: () => WorldEventType.other,
    );
  }

  static WorldEventStatus _readStatus(dynamic value) {
    final name = _readText(value);
    return WorldEventStatus.values.firstWhere(
      (item) => item.name == name,
      orElse: () => WorldEventStatus.active,
    );
  }
}

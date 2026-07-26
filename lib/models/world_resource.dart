class WorldResourceReservation {
  const WorldResourceReservation({
    required this.decisionId,
    required this.characterId,
    required this.quantity,
    required this.reservedAt,
    required this.expiresAt,
  });

  final String decisionId;
  final String characterId;
  final int quantity;
  final DateTime reservedAt;
  final DateTime expiresAt;

  bool isExpiredAt(DateTime time) => !time.isBefore(expiresAt);

  Map<String, dynamic> toJson() => {
        'decisionId': decisionId,
        'characterId': characterId,
        'quantity': quantity,
        'reservedAt': reservedAt.toIso8601String(),
        'expiresAt': expiresAt.toIso8601String(),
      };

  factory WorldResourceReservation.fromJson(Map<dynamic, dynamic> json) {
    final now = DateTime.now();
    return WorldResourceReservation(
      decisionId: json['decisionId']?.toString().trim() ?? '',
      characterId: json['characterId']?.toString().trim() ?? '',
      quantity: _readPositiveInt(json['quantity'], fallback: 1),
      reservedAt:
          DateTime.tryParse(json['reservedAt']?.toString() ?? '') ?? now,
      expiresAt: DateTime.tryParse(json['expiresAt']?.toString() ?? '') ??
          now.add(const Duration(hours: 2)),
    );
  }

  static int _readPositiveInt(dynamic value, {required int fallback}) {
    final parsed = value is num ? value.toInt() : int.tryParse('$value');
    if (parsed == null || parsed <= 0) return fallback;
    return parsed;
  }
}

class WorldResource {
  const WorldResource({
    required this.id,
    required this.name,
    required this.totalQuantity,
    required this.remainingQuantity,
    required this.updatedAt,
    this.locationId,
    this.locationName,
    this.sourceWorldEventId = '',
    this.isReusable = false,
    this.reservations = const [],
    this.metadata = const {},
  });

  final String id;
  final String name;
  final int totalQuantity;
  final int remainingQuantity;
  final DateTime updatedAt;
  final String? locationId;
  final String? locationName;
  final String sourceWorldEventId;
  final bool isReusable;
  final List<WorldResourceReservation> reservations;
  final Map<String, dynamic> metadata;

  int availableAt(DateTime time) {
    if (isReusable) return remainingQuantity;
    final reserved = reservations
        .where((item) => !item.isExpiredAt(time))
        .fold<int>(0, (sum, item) => sum + item.quantity);
    final available = remainingQuantity - reserved;
    return available < 0 ? 0 : available;
  }

  WorldResource copyWith({
    String? id,
    String? name,
    int? totalQuantity,
    int? remainingQuantity,
    DateTime? updatedAt,
    String? locationId,
    bool clearLocationId = false,
    String? locationName,
    bool clearLocationName = false,
    String? sourceWorldEventId,
    bool? isReusable,
    List<WorldResourceReservation>? reservations,
    Map<String, dynamic>? metadata,
  }) {
    return WorldResource(
      id: id ?? this.id,
      name: name ?? this.name,
      totalQuantity: totalQuantity ?? this.totalQuantity,
      remainingQuantity: remainingQuantity ?? this.remainingQuantity,
      updatedAt: updatedAt ?? this.updatedAt,
      locationId: clearLocationId ? null : (locationId ?? this.locationId),
      locationName:
          clearLocationName ? null : (locationName ?? this.locationName),
      sourceWorldEventId: sourceWorldEventId ?? this.sourceWorldEventId,
      isReusable: isReusable ?? this.isReusable,
      reservations: reservations ?? this.reservations,
      metadata: metadata ?? this.metadata,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'totalQuantity': totalQuantity,
        'remainingQuantity': remainingQuantity,
        'updatedAt': updatedAt.toIso8601String(),
        'locationId': locationId,
        'locationName': locationName,
        'sourceWorldEventId': sourceWorldEventId,
        'isReusable': isReusable,
        'reservations': reservations.map((item) => item.toJson()).toList(),
        'metadata': metadata,
      };

  factory WorldResource.fromJson(Map<dynamic, dynamic> json) {
    final now = DateTime.now();
    final total = _readNonNegativeInt(json['totalQuantity']);
    final remaining = _readNonNegativeInt(
      json['remainingQuantity'],
      fallback: total,
    );
    final rawReservations = json['reservations'];
    return WorldResource(
      id: json['id']?.toString().trim() ?? '',
      name: json['name']?.toString().trim() ?? '',
      totalQuantity: total,
      remainingQuantity: remaining,
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? '') ?? now,
      locationId: _nullableText(json['locationId']),
      locationName: _nullableText(json['locationName']),
      sourceWorldEventId:
          json['sourceWorldEventId']?.toString().trim() ?? '',
      isReusable: json['isReusable'] == true,
      reservations: rawReservations is List
          ? rawReservations
              .whereType<Map>()
              .map(WorldResourceReservation.fromJson)
              .where((item) => item.decisionId.isNotEmpty)
              .toList()
          : const [],
      metadata: json['metadata'] is Map
          ? Map<String, dynamic>.from(json['metadata'] as Map)
          : const {},
    );
  }

  static int _readNonNegativeInt(dynamic value, {int fallback = 0}) {
    final parsed = value is num ? value.toInt() : int.tryParse('$value');
    if (parsed == null || parsed < 0) return fallback;
    return parsed;
  }

  static String? _nullableText(dynamic value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }
}

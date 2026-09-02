import 'memory_source_type.dart';

enum UserMemoryStatus {
  active,
  superseded,
  archived;

  static UserMemoryStatus fromJson(dynamic value) {
    final name = value?.toString();
    return UserMemoryStatus.values.firstWhere(
      (item) => item.name == name,
      orElse: () => UserMemoryStatus.active,
    );
  }
}

/// A character-scoped understanding formed about the user through interaction.
///
/// Conflict precedence is: CharacterUserProfile (user-authored hard setting),
/// UserMemory (character-specific learned understanding), then global
/// UserProfile. This model does not overwrite either profile.
class UserMemory {
  UserMemory({
    required this.id,
    required this.characterId,
    required this.key,
    required this.value,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.sourceMessageIds = const [],
    this.status = UserMemoryStatus.active,
    this.supersededById,
    this.mergedFromIds = const [],
    this.isPinned = false,
    this.userConfirmed = false,
    this.sourceType = MemorySourceType.manual,
    this.legacySourceId,
  }) : createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? createdAt ?? DateTime.now();

  final String id;
  final String characterId;
  final String key;
  final String value;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<String> sourceMessageIds;
  final UserMemoryStatus status;
  final String? supersededById;
  final List<String> mergedFromIds;
  final bool isPinned;
  final bool userConfirmed;
  final MemorySourceType sourceType;
  final String? legacySourceId;

  String get displayText {
    final cleanKey = key.trim();
    final cleanValue = value.trim();
    if (cleanKey.isEmpty) return cleanValue;
    if (cleanValue.isEmpty) return cleanKey;
    return '$cleanKey：$cleanValue';
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'characterId': characterId,
    'key': key,
    'value': value,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'sourceMessageIds': sourceMessageIds,
    'status': status.name,
    'supersededById': supersededById,
    'mergedFromIds': mergedFromIds,
    'isPinned': isPinned,
    'userConfirmed': userConfirmed,
    'sourceType': sourceType.name,
    'legacySourceId': legacySourceId,
  };

  factory UserMemory.fromJson(Map<dynamic, dynamic> json) {
    final now = DateTime.now();
    final createdAt = _date(json['createdAt']) ?? now;
    return UserMemory(
      id: _text(json['id']),
      characterId: _text(json['characterId']),
      key: _text(json['key']),
      value: _text(json['value']),
      createdAt: createdAt,
      updatedAt: _date(json['updatedAt']) ?? createdAt,
      sourceMessageIds: _stringList(json['sourceMessageIds']),
      status: UserMemoryStatus.fromJson(json['status']),
      supersededById: _nullableText(json['supersededById']),
      mergedFromIds: _stringList(json['mergedFromIds']),
      isPinned: json['isPinned'] == true,
      userConfirmed: json['userConfirmed'] == true,
      sourceType: MemorySourceType.fromJson(json['sourceType']),
      legacySourceId: _nullableText(json['legacySourceId']),
    );
  }

  static String _text(dynamic value) => value?.toString().trim() ?? '';
  static String? _nullableText(dynamic value) {
    final text = _text(value);
    return text.isEmpty ? null : text;
  }

  static DateTime? _date(dynamic value) =>
      DateTime.tryParse(value?.toString() ?? '');

  static List<String> _stringList(dynamic value) {
    if (value is! List) return const [];
    return value.map(_text).where((item) => item.isNotEmpty).toSet().toList();
  }
}

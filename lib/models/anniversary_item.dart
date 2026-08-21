enum AnniversaryRepeatType { none, yearly }

extension AnniversaryRepeatTypeLabel on AnniversaryRepeatType {
  String get label => switch (this) {
    AnniversaryRepeatType.none => '不重复',
    AnniversaryRepeatType.yearly => '每年',
  };
}

class AnniversaryItem {
  const AnniversaryItem({
    required this.id,
    required this.title,
    required this.date,
    required this.repeatType,
    required this.isPinned,
    required this.createdAt,
    this.relatedCharacterId,
  });

  final String id;
  final String title;
  final DateTime date;
  final AnniversaryRepeatType repeatType;
  final String? relatedCharacterId;
  final bool isPinned;
  final DateTime createdAt;

  AnniversaryItem copyWith({
    String? title,
    DateTime? date,
    AnniversaryRepeatType? repeatType,
    String? relatedCharacterId,
    bool clearRelatedCharacter = false,
    bool? isPinned,
  }) => AnniversaryItem(
    id: id,
    title: title ?? this.title,
    date: date ?? this.date,
    repeatType: repeatType ?? this.repeatType,
    relatedCharacterId: clearRelatedCharacter
        ? null
        : relatedCharacterId ?? this.relatedCharacterId,
    isPinned: isPinned ?? this.isPinned,
    createdAt: createdAt,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'date': date.toIso8601String(),
    'repeatType': repeatType.name,
    'relatedCharacterId': relatedCharacterId,
    'isPinned': isPinned,
    'createdAt': createdAt.toIso8601String(),
  };

  factory AnniversaryItem.fromJson(Map<dynamic, dynamic> json) {
    final date = DateTime.tryParse(json['date']?.toString() ?? '');
    final createdAt = DateTime.tryParse(json['createdAt']?.toString() ?? '');
    return AnniversaryItem(
      id: json['id']?.toString().trim() ?? '',
      title: json['title']?.toString().trim() ?? '',
      date: date ?? DateTime.now(),
      repeatType: AnniversaryRepeatType.values.firstWhere(
        (value) => value.name == json['repeatType']?.toString(),
        orElse: () => AnniversaryRepeatType.none,
      ),
      relatedCharacterId:
          json['relatedCharacterId']?.toString().trim().isNotEmpty == true
          ? json['relatedCharacterId'].toString().trim()
          : null,
      isPinned: json['isPinned'] == true,
      createdAt: createdAt ?? DateTime.now(),
    );
  }
}

class AnniversaryDayStatus {
  const AnniversaryDayStatus({required this.label, required this.days});
  final String label;
  final int days;

  String get displayText => days == 0 ? '就是今天' : '$label $days 天';

  static AnniversaryDayStatus calculate(AnniversaryItem item, {DateTime? now}) {
    final value = now ?? DateTime.now();
    final today = DateTime(value.year, value.month, value.day);
    final original = DateTime(item.date.year, item.date.month, item.date.day);
    if (item.repeatType == AnniversaryRepeatType.none) {
      final difference = original.difference(today).inDays;
      return difference > 0
          ? AnniversaryDayStatus(label: '还有', days: difference)
          : AnniversaryDayStatus(label: '已经', days: -difference);
    }

    DateTime occurrence(int year) {
      final lastDay = DateTime(year, item.date.month + 1, 0).day;
      return DateTime(
        year,
        item.date.month,
        item.date.day.clamp(1, lastDay).toInt(),
      );
    }

    var next = occurrence(today.year);
    if (next.isBefore(today)) next = occurrence(today.year + 1);
    return AnniversaryDayStatus(
      label: '还有',
      days: next.difference(today).inDays,
    );
  }
}

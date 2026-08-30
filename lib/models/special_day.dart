import 'anniversary_item.dart';

enum SpecialDayType {
  memorialDay,
  userAnniversary,
  traditionalFestival,
  modernFestival,
  worldDay,
}

class SpecialDay {
  const SpecialDay({
    required this.id,
    required this.name,
    required this.type,
    required this.marker,
    required this.shortMessage,
    required this.priority,
    this.anniversary,
  });

  final String id;
  final String name;
  final SpecialDayType type;
  final String marker;
  final String shortMessage;
  final int priority;
  final AnniversaryItem? anniversary;

  bool get isMemorial => type == SpecialDayType.memorialDay;
  bool get isUserAnniversary => type == SpecialDayType.userAnniversary;
}

class WorldStatusContent {
  const WorldStatusContent({
    required this.headline,
    required this.title,
    required this.detail,
    required this.isMemorial,
  });

  final String headline;
  final String title;
  final String detail;
  final bool isMemorial;
}

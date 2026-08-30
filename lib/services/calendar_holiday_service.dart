import 'special_day_service.dart';

/// Backwards-compatible label boundary backed by deterministic local data.
abstract final class CalendarHolidayService {
  static String? labelFor(DateTime date) =>
      SpecialDayService.systemDaysFor(date).firstOrNull?.name;
}

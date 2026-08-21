/// 纯本地的现实节日查询边界。
///
/// 当前不内置不可靠的节日数据；后续可以在这里接入经校验的
/// 本地日历表，而不需要让 UI 访问网络或 AI。
abstract final class CalendarHolidayService {
  static String? labelFor(DateTime date) => null;
}

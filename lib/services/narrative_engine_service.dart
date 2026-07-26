import '../models/story_fragment.dart';

/// 把同一份 Story Fragment 翻译成不同使用场景下的表达。
///
/// 叙事引擎不生成新事实，只允许删减、排序和改变语气。
class NarrativeEngineService {
  const NarrativeEngineService();

  NarrativeSnapshot render(
    StoryFragment fragment, {
    required NarrativePerspective perspective,
    DateTime? now,
  }) {
    final content = switch (perspective) {
      NarrativePerspective.chat => _forChat(fragment),
      NarrativePerspective.echo => _forEcho(fragment),
      NarrativePerspective.memory => _forMemory(fragment),
      NarrativePerspective.summary => _forSummary(fragment),
    };
    return NarrativeSnapshot(
      fragmentId: fragment.id,
      perspective: perspective,
      content: content,
      createdAt: now ?? DateTime.now(),
      lifeMomentIds: fragment.lifeMomentIds,
      causeNodeIds: fragment.causeNodeIds,
    );
  }

  String _forChat(StoryFragment fragment) {
    final core = _trim(fragment.summary, 180);
    if (core.isEmpty) return '';
    return '${_relativeTime(fragment.startedAt)}，$core。';
  }

  String _forEcho(StoryFragment fragment) {
    final core = _trim(fragment.summary, 150);
    if (core.isEmpty) return '';
    final feeling = _trim(fragment.feeling, 45);
    return feeling.isEmpty ? core : '$core。$feeling。';
  }

  String _forMemory(StoryFragment fragment) {
    final core = _trim(fragment.summary, 220);
    if (core.isEmpty) return '';
    final cause = fragment.worldEventIds.isEmpty ? '' : '，过程中受到当时世界状态影响';
    return '${_date(fragment.startedAt)}，$core$cause。';
  }

  String _forSummary(StoryFragment fragment) {
    final core = _trim(fragment.summary, 120);
    if (core.isEmpty) return '';
    return '${fragment.title}：$core';
  }

  String _relativeTime(DateTime time) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(time.year, time.month, time.day);
    final difference = today.difference(day).inDays;
    if (difference == 0) return '今天${_dayPart(time.hour)}';
    if (difference == 1) return '昨天${_dayPart(time.hour)}';
    return '${time.month}月${time.day}日${_dayPart(time.hour)}';
  }

  String _dayPart(int hour) => switch (hour) {
        < 6 => '凌晨',
        < 11 => '上午',
        < 14 => '中午',
        < 18 => '下午',
        < 22 => '晚上',
        _ => '深夜',
      };

  String _date(DateTime time) => '${time.year}年${time.month}月${time.day}日';

  String _trim(String value, int maxLength) {
    final clean = value.trim();
    if (clean.length <= maxLength) return clean;
    return '${clean.substring(0, maxLength).trim()}…';
  }
}

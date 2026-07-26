import '../models/life_moment.dart';
import '../models/story_fragment.dart';

/// 把已经发生的生活事件整理成稳定的故事片段。
///
/// 这里只做归组和事实压缩，不调用模型，也不会创造新的生活事实。
class StoryFragmentEngineService {
  const StoryFragmentEngineService();

  static const Duration _maximumGap = Duration(hours: 3);

  List<StoryFragment> build(
    List<LifeMomentCandidate> moments, {
    DateTime? now,
    int limit = 8,
  }) {
    final time = now ?? DateTime.now();
    final occurred = moments
        .where((item) => !item.occurredAt.isAfter(time))
        .toList()
      ..sort((a, b) => a.occurredAt.compareTo(b.occurredAt));
    if (occurred.isEmpty) return const [];

    final groups = <List<LifeMomentCandidate>>[];
    for (final moment in occurred) {
      if (groups.isEmpty || !_belongsTo(groups.last.last, moment)) {
        groups.add([moment]);
      } else {
        groups.last.add(moment);
      }
    }

    final fragments = groups.map(_buildFragment).toList()
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return fragments.take(limit).toList();
  }

  StoryFragment buildAround(
    LifeMomentCandidate selected,
    List<LifeMomentCandidate> moments, {
    DateTime? now,
  }) {
    final fragments = build(moments, now: now, limit: moments.length + 1);
    for (final fragment in fragments) {
      if (fragment.lifeMomentIds.contains(selected.id)) return fragment;
    }
    return _buildFragment([selected]);
  }

  bool _belongsTo(LifeMomentCandidate previous, LifeMomentCandidate current) {
    if (!_sameDay(previous.occurredAt, current.occurredAt)) return false;
    if (current.occurredAt.difference(previous.occurredAt) > _maximumGap) {
      return false;
    }

    final previousScene = _normalize(previous.scene);
    final currentScene = _normalize(current.scene);
    if (previousScene.isNotEmpty && previousScene == currentScene) return true;

    final sharedCause = previous.causeNodeId.isNotEmpty &&
        previous.causeNodeId == current.causeNodeId;
    final sharedWorld = previous.worldEventIds
        .toSet()
        .intersection(current.worldEventIds.toSet())
        .isNotEmpty;
    final sharedCharacter = previous.relatedCharacterNames
        .toSet()
        .intersection(current.relatedCharacterNames.toSet())
        .isNotEmpty;
    return sharedCause || sharedWorld || sharedCharacter;
  }

  StoryFragment _buildFragment(List<LifeMomentCandidate> items) {
    final first = items.first;
    final last = items.last;
    final title = _titleFor(first.occurredAt, first.scene);
    final summaries = items
        .map(_momentSummary)
        .where((value) => value.isNotEmpty)
        .toList();
    final feelings = items
        .map((item) => item.feeling.trim())
        .where((value) => value.isNotEmpty)
        .toList();
    final scenes = items
        .map((item) => item.scene.trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList();

    return StoryFragment(
      id: 'fragment_${first.id}_${last.id}',
      title: title,
      summary: summaries.join('；'),
      startedAt: first.occurredAt,
      endedAt: last.occurredAt,
      lifeMomentIds: items.map((item) => item.id).toList(),
      scene: scenes.join('、'),
      feeling: feelings.isEmpty ? '' : feelings.last,
      causeNodeIds: items
          .map((item) => item.causeNodeId.trim())
          .where((value) => value.isNotEmpty)
          .toSet()
          .toList(),
      worldEventIds: items
          .expand((item) => item.worldEventIds)
          .where((value) => value.trim().isNotEmpty)
          .toSet()
          .toList(),
      relatedCharacterNames: items
          .expand((item) => item.relatedCharacterNames)
          .where((value) => value.trim().isNotEmpty)
          .toSet()
          .toList(),
    );
  }

  String _momentSummary(LifeMomentCandidate item) {
    final event = _clean(item.event);
    final detail = _clean(item.detail);
    if (event.isEmpty) return detail;
    if (detail.isEmpty || detail == event) return event;
    return '$event，$detail';
  }

  String _titleFor(DateTime time, String scene) {
    final part = switch (time.hour) {
      < 6 => '凌晨',
      < 11 => '上午',
      < 14 => '中午',
      < 18 => '下午',
      < 22 => '晚上',
      _ => '深夜',
    };
    final cleanScene = scene.trim();
    return cleanScene.isEmpty ? part : '$part · $cleanScene';
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  String _normalize(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'\s+'), '').trim();

  String _clean(String value) => value
      .trim()
      .replaceAll(RegExp(r'^[“”\s]+|[“”\s]+$'), '')
      .replaceAll(RegExp(r'[。！？!?；;]+$'), '');
}

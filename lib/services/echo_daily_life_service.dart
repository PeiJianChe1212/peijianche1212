import '../models/ai_character.dart';
import '../models/echo_daily_life.dart';

/// API-free daily life pool used as the reliability layer below Life/Moment.
class EchoDailyLifeService {
  const EchoDailyLifeService();

  EchoDailyLife create({
    required AiCharacter character,
    required DateTime at,
    bool initial = false,
    bool offlineReturn = false,
    int recentUserMessages = 0,
  }) {
    if (initial) {
      const options = [
        EchoDailyLife(
          kind: EchoDailyLifeKind.arrival,
          content: '今天第一次来到这里，还在慢慢熟悉周围。',
          summary: '初次来到 PeiLink',
        ),
        EchoDailyLife(
          kind: EchoDailyLifeKind.arrival,
          content: '把自己的空间简单整理了一下，感觉这里比刚来时熟悉了一点。',
          summary: '整理新的空间',
        ),
      ];
      return options[_hash('${character.id}|initial') % options.length];
    }

    final options = <EchoDailyLife>[
      const EchoDailyLife(
        kind: EchoDailyLifeKind.work,
        content: '今天整理了一下午资料，终于把积着的文件归档好了。',
        summary: '整理资料',
      ),
      const EchoDailyLife(
        kind: EchoDailyLifeKind.work,
        content: '把接下来要做的事情重新排了一遍，思路总算清楚了。',
        summary: '安排近期事务',
      ),
      const EchoDailyLife(
        kind: EchoDailyLifeKind.interest,
        content: '空下来读了几页书，正好看到一段很有意思的内容。',
        summary: '空闲时看书',
      ),
      const EchoDailyLife(
        kind: EchoDailyLifeKind.interest,
        content: '戴着耳机听了一会儿音乐，原本乱糟糟的心情安静了不少。',
        summary: '听音乐放松',
      ),
      const EchoDailyLife(
        kind: EchoDailyLifeKind.environment,
        content: '出去走了一小段路，回来时整个人都清醒了些。',
        summary: '出门散步',
      ),
      const EchoDailyLife(
        kind: EchoDailyLifeKind.mood,
        content: '今天状态还不错，把几件拖着的小事都处理完了。',
        summary: '状态不错的一天',
      ),
      const EchoDailyLife(
        kind: EchoDailyLifeKind.mood,
        content: '稍微有点疲惫，决定把剩下的事情留到明天再做。',
        summary: '有些疲惫',
      ),
      if (recentUserMessages >= 20)
        const EchoDailyLife(
          kind: EchoDailyLifeKind.mood,
          content: '今天说了很多话。安静下来以后，脑子里还留着不少没散去的念头。',
          summary: '交流很多的一天',
        ),
      if (offlineReturn)
        const EchoDailyLife(
          kind: EchoDailyLifeKind.interest,
          content: '昨天晚些时候去附近转了转，顺便带回了一本想看的书。',
          summary: '离线期间去了书店',
        ),
    ];
    final dayKey = '${at.year}-${at.month}-${at.day}';
    return options[_hash('${character.id}|$dayKey|${options.length}') %
        options.length];
  }

  int _hash(String value) {
    var hash = 17;
    for (final unit in value.codeUnits) {
      hash = (hash * 37 + unit) & 0x7fffffff;
    }
    return hash;
  }
}

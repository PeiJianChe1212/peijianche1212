import '../models/echo_comment.dart';
import '../models/echo_item.dart';
import 'echo_relationship_engine_service.dart';

class EchoCommentDiversityService {
  const EchoCommentDiversityService();

  EchoCommentStyle chooseStyle({
    required String seed,
    required Set<EchoCommentStyle> used,
    EchoRelationshipKind? relationshipKind,
    bool virtualVisitor = false,
  }) {
    final preferred = virtualVisitor
        ? const [
            EchoCommentStyle.resonance,
            EchoCommentStyle.observation,
            EchoCommentStyle.shortInteraction,
            EchoCommentStyle.mood,
            EchoCommentStyle.detail,
            EchoCommentStyle.encouragement,
            EchoCommentStyle.care,
            EchoCommentStyle.teasing,
          ]
        : switch (relationshipKind) {
            EchoRelationshipKind.lover => const [
                EchoCommentStyle.care,
                EchoCommentStyle.care,
                EchoCommentStyle.care,
                EchoCommentStyle.care,
                EchoCommentStyle.care,
                EchoCommentStyle.care,
                EchoCommentStyle.care,
                EchoCommentStyle.teasing,
                EchoCommentStyle.resonance,
                EchoCommentStyle.observation,
            ],
            EchoRelationshipKind.family => const [
              EchoCommentStyle.care,
              EchoCommentStyle.encouragement,
              EchoCommentStyle.resonance,
              EchoCommentStyle.observation,
            ],
            EchoRelationshipKind.friend => const [
                EchoCommentStyle.teasing,
                EchoCommentStyle.teasing,
                EchoCommentStyle.observation,
                EchoCommentStyle.resonance,
              ],
            _ => const [
              EchoCommentStyle.observation,
              EchoCommentStyle.detail,
              EchoCommentStyle.shortInteraction,
              EchoCommentStyle.resonance,
            ],
          };
    final available = preferred
        .where((style) => !used.contains(style))
        .toList();
    if (available.isNotEmpty) return available[_hash(seed) % available.length];
    return EchoCommentStyle.values.firstWhere(
      (style) => !used.contains(style),
      orElse: () => EchoCommentStyle.shortInteraction,
    );
  }

  String createTemplate({
    required EchoItem echo,
    required EchoCommentStyle style,
    required String seed,
    required List<String> existing,
    EchoRelationshipKind? relationshipKind,
  }) {
    final work = RegExp(r'工作|资料|文件|会议|加班|忙|整理').hasMatch(echo.content);
    final tired = RegExp(r'累|疲惫|晚|休息|熬夜').hasMatch(echo.content);
    final options = switch (style) {
      EchoCommentStyle.observation =>
        echo.imagePaths.isNotEmpty
            ? ['这个地方视野很开阔。', '画面里最远处的景色很耐看。', '周围看起来很安静。']
            : ['你留意到的这个细节挺有意思。', '这件小事很有生活感。', '读着能想象出当时的场景。'],
      EchoCommentStyle.care =>
        work || tired
            ? ['忙到现在，也该让自己喘口气了。', '事情做完了就早点休息。', '别只顾着手里的事，记得照顾自己。']
            : ['最近的状态看起来还不错。', '慢慢来，别把行程排得太满。', '有空的时候也要好好休息。'],
      EchoCommentStyle.teasing =>
        relationshipKind == EchoRelationshipKind.lover
            ? ['你居然还记得停下来看看周围。', '还知道给自己留一点休息时间。', '这次总算没把所有时间都给工作。']
            : ['难得被你抓到一个清闲的瞬间。', '原来你也会认真记录这些。', '这次行动得倒是挺快。'],
      EchoCommentStyle.resonance => [
        '有时候短暂地停一会儿，反而最舒服。',
        '这种普通的小片刻，过后想起来很珍贵。',
        '我也喜欢忙完以后让脑子安静一会儿。',
      ],
      EchoCommentStyle.shortInteraction => [
        '这个瞬间很好。',
        '今天这一段值得记下来。',
        '看到这里也跟着放松了。',
      ],
      EchoCommentStyle.encouragement =>
        work
            ? ['能把积着的事情处理好，已经很不错了。', '一点点收拾清楚，也算很踏实的进展。', '辛苦有了结果，值得给自己放个假。']
            : ['保持这样的状态就很好。', '愿接下来的事情也一样顺利。', '今天算是稳稳地过好了。'],
      EchoCommentStyle.detail =>
        echo.imagePaths.isNotEmpty
            ? ['远处那一小片景色很抢眼。', '画面里的层次很舒服。', '背景里的细节越看越有意思。']
            : ['“终于弄完”这几个字看着就很解压。', '最后这个小细节一下让内容真实了。', '这种收尾后的轻松感很具体。'],
      EchoCommentStyle.mood => [
        '看得出来这一刻心情很松弛。',
        '整条动态有种终于慢下来的感觉。',
        '读完会让人心里安静一点。',
      ],
    };
    final start = _hash('$seed|${style.name}') % options.length;
    for (var offset = 0; offset < options.length; offset++) {
      final candidate = options[(start + offset) % options.length];
      if (!existing.any((old) => isSemanticallySimilar(candidate, old))) {
        return candidate;
      }
    }
    return options[start];
  }

  bool isSemanticallySimilar(String first, String second) {
    final left = _concepts(first);
    final right = _concepts(second);
    if (left.isEmpty || right.isEmpty) {
      return _normalize(first) == _normalize(second);
    }
    final overlap = left.intersection(right).length;
    final union = left.union(right).length;
    if (overlap >= 2 || (union > 0 && overlap / union >= .6)) return true;
    final a = _bigrams(_normalize(first));
    final b = _bigrams(_normalize(second));
    if (a.isEmpty || b.isEmpty) return false;
    return a.intersection(b).length / a.union(b).length >= .55;
  }

  String instruction(EchoCommentStyle style) => switch (style) {
    EchoCommentStyle.observation => '观察型：只谈一个尚未被评论的画面或内容细节',
    EchoCommentStyle.care => '关心型：关注发布者此刻的状态',
    EchoCommentStyle.teasing => '调侃型：根据关系轻微调侃，不挖苦',
    EchoCommentStyle.resonance => '共鸣型：表达相似感受，不虚构具体经历',
    EchoCommentStyle.shortInteraction => '简短互动型：用一句话接住这个瞬间',
    EchoCommentStyle.encouragement => '鼓励型：肯定正文里的具体进展',
    EchoCommentStyle.detail => '细节型：抓住正文里一个没人提过的小细节',
    EchoCommentStyle.mood => '情绪型：回应动态传达出的情绪',
  };

  Set<String> _concepts(String value) {
    final result = <String>{};
    final groups = <String, RegExp>{
      'light': RegExp(r'光线|光影|明暗|采光'),
      'angle': RegExp(r'角度|构图|取景'),
      'atmosphere': RegExp(r'氛围|画面感|感觉'),
      'photoPraise': RegExp(r'拍得好|拍得不错|照片好看|很出片'),
      'rest': RegExp(r'休息|喘口气|放松|停一会|慢下来'),
      'care': RegExp(r'照顾自己|别太累|早点睡|辛苦'),
      'view': RegExp(r'视野|远处|景色|夜景|风景'),
      'mood': RegExp(r'心情|状态|安静|松弛'),
      'work': RegExp(r'工作|资料|文件|加班|忙|事情'),
    };
    for (final entry in groups.entries) {
      if (entry.value.hasMatch(value)) result.add(entry.key);
    }
    return result;
  }

  Set<String> _bigrams(String value) {
    if (value.length < 2) return {value};
    return {
      for (var i = 0; i < value.length - 1; i++) value.substring(i, i + 2),
    };
  }

  String _normalize(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), '')
      .replaceAll(RegExp(r'[，。！？、,.!?;；:：\-—“”‘’]'), '');

  int _hash(String value) {
    var hash = 17;
    for (final unit in value.codeUnits) {
      hash = (hash * 37 + unit) & 0x7fffffff;
    }
    return hash;
  }
}

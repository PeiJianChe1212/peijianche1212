import '../models/ai_character.dart';
import '../models/character_relationship.dart';
import '../models/character_settings.dart';
import '../models/echo_item.dart';
import 'activity_service.dart';

enum EchoContentType {
  daily,
  food,
  work,
  feeling,
  achievement,
  travel,
  share,
  complaint,
}

class EchoCommentDecision {
  const EchoCommentDecision({
    required this.shouldComment,
    required this.reason,
    required this.contentType,
    required this.relevance,
    required this.activityLabel,
    this.styleHint = '',
  });

  final bool shouldComment;
  final String reason;
  final EchoContentType contentType;
  final int relevance;
  final String activityLabel;
  final String styleHint;
}

/// 在调用模型前判断角色是否真的看见、在意、有话可说且当前适合说。
class EchoCommentInteractionPolicy {
  const EchoCommentInteractionPolicy();

  EchoCommentDecision evaluate({
    required EchoItem echo,
    required AiCharacter commenter,
    required CharacterSettings settings,
    CharacterRelationship? relationship,
    DateTime? now,
  }) {
    final time = now ?? DateTime.now();
    final type = classify(echo.content);
    final activity =
        ActivityService(characterId: commenter.id).current(now: time);
    final isUserEcho =
        echo.characterId == 'peilink_user_echo';
    final seed = _stableScore('${echo.id}|${commenter.id}|policy') % 100;

    if (activity.isSleeping) {
      return _skip(type, activity.label, '当前正在睡眠');
    }

    var relevance = isUserEcho ? 42 : 0;
    if (echo.isFromSharedExperience) relevance += 38;
    if (relationship != null) {
      relevance += switch (relationship.stage) {
        CharacterRelationshipStage.aware => 4,
        CharacterRelationshipStage.acquainted => 14,
        CharacterRelationshipStage.familiar => 24,
        CharacterRelationshipStage.cooperative => 27,
        CharacterRelationshipStage.friend => 34,
      };
      relevance += relationship.sharedEventCount.clamp(0, 4).toInt() * 4;
    }

    relevance += switch (type) {
      EchoContentType.food => 10,
      EchoContentType.achievement => 14,
      EchoContentType.travel => 9,
      EchoContentType.share => 8,
      EchoContentType.work => 5,
      EchoContentType.daily => 2,
      EchoContentType.feeling => relationship == null && !isUserEcho ? -22 : 4,
      EchoContentType.complaint =>
        relationship == null && !isUserEcho ? -18 : 3,
    };

    final personaText = [
      settings.coreProfile,
      settings.behaviorStyle,
      settings.forbiddenRules,
    ].join(' ');
    final quiet = RegExp(r'寡言|沉默|少言|话少|克制|冷淡|清冷')
        .hasMatch(personaText);
    final active = RegExp(r'活泼|开朗|健谈|话多|外向|热情')
        .hasMatch(personaText);
    final esports =
        RegExp(r'电竞|职业选手|战队|训练|比赛').hasMatch(personaText);
    final teasing = RegExp(r'毒舌|嘴硬|调侃|腹黑').hasMatch(personaText);

    if (quiet) relevance -= 12;
    if (active) relevance += 10;
    if (activity.id.contains('working')) relevance -= 14;
    if (esports &&
        (activity.id.contains('working') ||
            (time.hour >= 13 && time.hour < 22))) {
      relevance -= 16;
    }

    final threshold = relevance.clamp(8, 82);
    if (seed >= threshold) {
      return _skip(
        type,
        activity.label,
        '有资格看到，但当前没有足够强的互动动机',
        relevance: relevance,
      );
    }

    final styleHint = [
      if (quiet) '角色偏寡言，评论尽量短，能少说就不展开。',
      if (teasing) '可以有一丁点符合关系的轻微调侃，但不能带敌意。',
      if (activity.id.contains('working')) '角色正忙，回应应更简短。',
      if (esports) '训练或比赛优先，不要写成恋爱脑式公开互动。',
    ].join('\n');
    return EchoCommentDecision(
      shouldComment: true,
      reason: _reason(type, echo, relationship),
      contentType: type,
      relevance: relevance,
      activityLabel: activity.label,
      styleHint: styleHint,
    );
  }

  EchoContentType classify(String content) {
    final text = content.toLowerCase();
    if (RegExp(r'吃|饭|早餐|午餐|晚餐|夜宵|咖啡|奶茶|甜品|餐厅|做菜')
        .hasMatch(text)) {
      return EchoContentType.food;
    }
    if (RegExp(r'完成|终于|拿到|成功|冠军|获奖|达成|通过|赢了')
        .hasMatch(text)) {
      return EchoContentType.achievement;
    }
    if (RegExp(r'工作|方案|文件|会议|加班|下班|训练|比赛|复盘|项目')
        .hasMatch(text)) {
      return EchoContentType.work;
    }
    if (RegExp(r'旅行|出发|机场|车站|酒店|景点|海边|登山|回程|城市')
        .hasMatch(text)) {
      return EchoContentType.travel;
    }
    if (RegExp(r'烦|累死|崩溃|倒霉|无语|抱怨|气死|不顺')
        .hasMatch(text)) {
      return EchoContentType.complaint;
    }
    if (RegExp(r'难过|低落|想念|心情|失眠|孤单|开心|幸福')
        .hasMatch(text)) {
      return EchoContentType.feeling;
    }
    if (RegExp(r'分享|推荐|好看|好听|电影|书|歌|照片|链接')
        .hasMatch(text)) {
      return EchoContentType.share;
    }
    return EchoContentType.daily;
  }

  EchoCommentDecision _skip(
    EchoContentType type,
    String activity,
    String reason, {
    int relevance = 0,
  }) {
    return EchoCommentDecision(
      shouldComment: false,
      reason: reason,
      contentType: type,
      relevance: relevance,
      activityLabel: activity,
    );
  }

  String _reason(
    EchoContentType type,
    EchoItem echo,
    CharacterRelationship? relationship,
  ) {
    if (echo.isFromSharedExperience) return '共同经历与 Echo 内容直接相关';
    if (relationship != null) {
      return '${relationship.stage.label}关系，且对${type.name}内容有回应意愿';
    }
    return '用户 Echo 与角色现有关系相关';
  }

  int _stableScore(String value) {
    var hash = 17;
    for (final unit in value.codeUnits) {
      hash = 0x1fffffff & (hash * 31 + unit);
    }
    return hash.abs();
  }
}

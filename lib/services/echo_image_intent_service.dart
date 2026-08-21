import '../models/echo_image_intent.dart';
import '../models/life_moment.dart';

class EchoImageIntentService {
  const EchoImageIntentService();

  EchoImageIntent resolve({
    required LifeMomentCandidate moment,
    required String characterId,
    bool suggestedByMoment = true,
  }) {
    final facts = [
      moment.scene,
      moment.event,
      moment.detail,
      moment.feeling,
      moment.shareHook,
    ].where((value) => value.trim().isNotEmpty).join('，');
    final subject = _subjectType(facts);
    final presence = _presence(subject, facts);
    final unsuitable = _containsAny(facts, const [
      '纯想法',
      '回忆起',
      '梦见',
      '抽象',
      '争吵',
      '危险',
      '受伤',
      '事故',
    ]);
    final focus = _visualFocus(subject, moment);
    final shouldGenerate = suggestedByMoment && !unsuitable && focus.isNotEmpty;

    return EchoImageIntent(
      shouldGenerateImage: shouldGenerate,
      subjectType: subject,
      characterPresence: shouldGenerate ? presence : EchoCharacterPresence.none,
      visualFocus: focus,
      mood: moment.feeling.trim(),
      requiredCharacterIds:
          shouldGenerate && presence == EchoCharacterPresence.required
          ? [characterId]
          : const [],
      sourceMomentId: moment.id,
      sourceLifeEventId: moment.decisionId,
    );
  }

  EchoImageSubjectType _subjectType(String facts) {
    if (_containsAny(facts, const ['自拍', '自拍照', '拍自己', '镜子里的自己'])) {
      return EchoImageSubjectType.selfie;
    }
    if (_containsAny(facts, const ['穿搭', '试穿', '搭配', '今日着装', '衣服上身'])) {
      return EchoImageSubjectType.outfit;
    }
    if (_containsAny(facts, const ['合照', '合影', '一起拍'])) {
      return EchoImageSubjectType.group;
    }
    if (_containsAny(facts, const [
      '咖啡',
      '早餐',
      '午餐',
      '晚餐',
      '食物',
      '甜点',
      '饮料',
      '吃了',
    ])) {
      return EchoImageSubjectType.food;
    }
    if (_containsAny(facts, const [
      '文件',
      '资料',
      '电脑',
      '键盘',
      '书桌',
      '学习',
      '作业',
      '工作',
    ])) {
      return EchoImageSubjectType.workStudy;
    }
    if (_containsAny(facts, const ['海边', '海面', '沙滩', '山景', '夜景', '风景', '日落'])) {
      return EchoImageSubjectType.scenery;
    }
    if (_containsAny(facts, const [
      '天气',
      '下雨',
      '雨天',
      '窗外',
      '街景',
      '天空',
      '云',
      '雪',
    ])) {
      return EchoImageSubjectType.environment;
    }
    if (_containsAny(facts, const ['旅行', '行程', '机票', '酒店', '马尔代夫', '车窗外'])) {
      return EchoImageSubjectType.travel;
    }
    if (_containsAny(facts, const ['买了', '购物', '逛街', '快递', '包裹', '商品'])) {
      return EchoImageSubjectType.shopping;
    }
    if (_containsAny(facts, const ['猫', '狗', '宠物'])) {
      return EchoImageSubjectType.pet;
    }
    if (_containsAny(facts, const ['截图', '聊天记录', '游戏界面'])) {
      return EchoImageSubjectType.screenshotLike;
    }
    if (_containsAny(facts, const ['新发型', '健身照', '拍了一张自己', '人物动作'])) {
      return EchoImageSubjectType.character;
    }
    if (_containsAny(facts, const ['桌面', '手机', '花', '礼物', '游戏', '物品', '颜色'])) {
      return EchoImageSubjectType.object;
    }
    return EchoImageSubjectType.other;
  }

  EchoCharacterPresence _presence(EchoImageSubjectType subject, String facts) {
    if (const {
      EchoImageSubjectType.selfie,
      EchoImageSubjectType.outfit,
      EchoImageSubjectType.group,
      EchoImageSubjectType.character,
    }.contains(subject)) {
      return EchoCharacterPresence.required;
    }
    if (_containsAny(facts, const ['本人出镜', '拍我', '我的背影', '我的侧脸'])) {
      return EchoCharacterPresence.required;
    }
    return EchoCharacterPresence.none;
  }

  String _visualFocus(
    EchoImageSubjectType subject,
    LifeMomentCandidate moment,
  ) {
    final facts = [
      moment.scene,
      moment.event,
      moment.detail,
    ].map((value) => value.trim()).where((value) => value.isNotEmpty).toList();
    if (facts.isEmpty) return '';
    final label = switch (subject) {
      EchoImageSubjectType.food => '食物或饮品与其所在桌面',
      EchoImageSubjectType.workStudy => '文件、电脑或学习用品构成的工作桌面',
      EchoImageSubjectType.environment => '天气、窗外或街道环境',
      EchoImageSubjectType.scenery => '自然景色与现场环境',
      EchoImageSubjectType.shopping => '新买的物品、包装或购物现场细节',
      EchoImageSubjectType.travel => '旅行资料、交通视野或目的地线索',
      EchoImageSubjectType.pet => '宠物与它所在的生活环境',
      EchoImageSubjectType.screenshotLike => '界面或屏幕中的视觉信息',
      EchoImageSubjectType.selfie => '角色本人自拍',
      EchoImageSubjectType.outfit => '角色当前穿搭展示',
      EchoImageSubjectType.group => '事实中明确参与者的合照',
      EchoImageSubjectType.character => '事实明确要求记录的人物动作',
      EchoImageSubjectType.object => '事实中被记录的物品与周围环境',
      EchoImageSubjectType.other => '这个生活片段中明确可见的环境或物品',
    };
    return '$label。事实依据：${facts.join('；')}';
  }

  bool _containsAny(String value, List<String> keywords) =>
      keywords.any(value.contains);
}

import '../context_builder/context_build_result.dart';
import '../models/character_settings.dart';
import '../reply_strategy/reply_strategy.dart';
import 'personality_style.dart';

class PersonalityStyleEngine {
  const PersonalityStyleEngine();

  PersonalityStyle resolve({
    required CharacterSettings settings,
    required ReplyStrategy replyStrategy,
  }) {
    final source = <String>[
      settings.introduction,
      settings.coreProfile,
      settings.behaviorStyle,
      settings.exampleDialogues,
    ].join('\n');
    final tone = _resolveTone(source);
    final length = _resolveLength(settings, source, replyStrategy);
    final emotion = _resolveEmotion(settings, source);

    return PersonalityStyle(
      tone: tone,
      speechPattern: _resolveSpeechPattern(length, source),
      emotionExpression: emotion,
      initiative: _resolveInitiative(settings.initiative),
      humorLevel: _resolveHumor(source, tone, emotion),
      formality: _resolveFormality(source),
      length: length,
    );
  }

  /// 模块实验专用：只解析 Personality Style，不读取 Reply Strategy。
  PersonalityStyle resolveForExperiment({required CharacterSettings settings}) {
    final source = <String>[
      settings.introduction,
      settings.coreProfile,
      settings.behaviorStyle,
      settings.exampleDialogues,
    ].join('\n');
    final tone = _resolveTone(source);
    final length = _resolveLengthWithoutStrategy(settings, source);
    final emotion = _resolveEmotion(settings, source);
    return PersonalityStyle(
      tone: tone,
      speechPattern: _resolveSpeechPattern(length, source),
      emotionExpression: emotion,
      initiative: _resolveInitiative(settings.initiative),
      humorLevel: _resolveHumor(source, tone, emotion),
      formality: _resolveFormality(source),
      length: length,
    );
  }

  ContextBuildResult apply({
    required ContextBuildResult context,
    required PersonalityStyle style,
  }) {
    if (context.messages.isEmpty) return context;
    final messages = context.messages
        .map((message) => Map<String, dynamic>.from(message))
        .toList();
    final system = messages.first;
    final original = system['content']?.toString() ?? context.systemPrompt;
    final prompt = '$original\n\n${style.toPromptSection()}';
    system['content'] = prompt;

    // ignore: avoid_print
    print(
      '[PersonalityStyleEngine] tone=${style.tone.key}, '
      'emotion=${style.emotionExpression.name}, '
      'length=${style.length.name}, initiative=${style.initiative.name}',
    );
    return ContextBuildResult(messages: messages, systemPrompt: prompt);
  }

  StyleTone _resolveTone(String source) {
    final cold = RegExp(r'冷淡|清冷|冷漠|外冷|疏离').hasMatch(source);
    final caring = RegExp(r'外冷内热|温柔|关心|体贴|细节|亲近的人').hasMatch(source);
    if (cold && caring) return StyleTone.coldButCaring;
    if (RegExp(r'强势|主导|霸道|压迫感|不容置疑').hasMatch(source)) {
      return StyleTone.dominant;
    }
    if (RegExp(r'活泼|调皮|爱笑|爱开玩笑|玩心|俏皮').hasMatch(source)) {
      return StyleTone.playful;
    }
    if (RegExp(r'温暖|热情|热心').hasMatch(source)) return StyleTone.warm;
    if (RegExp(r'柔和|温和|柔软|轻声').hasMatch(source)) {
      return StyleTone.soft;
    }
    if (RegExp(r'沉稳|冷静|平静|从容|克制').hasMatch(source)) {
      return StyleTone.calm;
    }
    if (cold) return StyleTone.cold;
    return StyleTone.calm;
  }

  StyleLength _resolveLength(
    CharacterSettings settings,
    String source,
    ReplyStrategy replyStrategy,
  ) {
    if (RegExp(r'寡言|惜字如金|言简意赅|回复简短|少说话').hasMatch(source)) {
      return StyleLength.short;
    }
    if (RegExp(r'健谈|话多|详细|长篇|喜欢展开').hasMatch(source)) {
      return StyleLength.long;
    }
    return switch (settings.replyLength) {
      'short' => StyleLength.short,
      'long' => StyleLength.long,
      _ =>
        replyStrategy.length == StrategyLength.short
            ? StyleLength.short
            : StyleLength.medium,
    };
  }

  StyleLength _resolveLengthWithoutStrategy(
    CharacterSettings settings,
    String source,
  ) {
    if (RegExp(r'寡言|惜字如金|言简意赅|回复简短|少说话').hasMatch(source)) {
      return StyleLength.short;
    }
    if (RegExp(r'健谈|话多|详细|长篇|喜欢展开').hasMatch(source)) {
      return StyleLength.long;
    }
    return switch (settings.replyLength) {
      'short' => StyleLength.short,
      'long' => StyleLength.long,
      _ => StyleLength.medium,
    };
  }

  EmotionExpression _resolveEmotion(CharacterSettings settings, String source) {
    if (settings.tsundere >= 0.6 ||
        RegExp(r'嘴硬|毒舌|调侃|故意逗|反话').hasMatch(source)) {
      return EmotionExpression.teasing;
    }
    if (RegExp(r'克制|寡言|含蓄|不动声色|隐藏情绪').hasMatch(source)) {
      return EmotionExpression.reserved;
    }
    if (settings.intimacy >= 0.72 ||
        RegExp(r'直率|直接表达|坦率|不掩饰').hasMatch(source)) {
      return EmotionExpression.direct;
    }
    return EmotionExpression.implicit;
  }

  StyleInitiative _resolveInitiative(double value) => switch (value) {
    >= 0.72 => StyleInitiative.high,
    >= 0.42 => StyleInitiative.medium,
    _ => StyleInitiative.low,
  };

  HumorLevel _resolveHumor(
    String source,
    StyleTone tone,
    EmotionExpression emotion,
  ) {
    if (RegExp(r'幽默|接梗|爱开玩笑|调皮|一本正经地胡说').hasMatch(source)) {
      return HumorLevel.high;
    }
    if (tone == StyleTone.playful || emotion == EmotionExpression.teasing) {
      return HumorLevel.medium;
    }
    return HumorLevel.low;
  }

  Formality _resolveFormality(String source) {
    if (RegExp(r'正式|严谨|书面|礼貌克制').hasMatch(source)) {
      return Formality.formal;
    }
    if (RegExp(r'口语|随意|自然聊天|熟人聊天').hasMatch(source)) {
      return Formality.casual;
    }
    return Formality.neutral;
  }

  SpeechPattern _resolveSpeechPattern(StyleLength length, String source) {
    if (length == StyleLength.short || RegExp(r'短句|言简意赅|寡言').hasMatch(source)) {
      return SpeechPattern.concise;
    }
    if (length == StyleLength.long || RegExp(r'详细|展开|长句').hasMatch(source)) {
      return SpeechPattern.expressive;
    }
    return SpeechPattern.balanced;
  }
}

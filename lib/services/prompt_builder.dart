import '../models/character_settings.dart';
import '../models/user_profile.dart';
import 'context_builder.dart';

/// 只负责模型消息格式和输出约束。
/// 人设、记忆、生活与关系上下文统一交给 ContextBuilder。
class PromptBuilder {
  const PromptBuilder._();

  static String buildStableSystemPrompt({
    required CharacterSettings characterSettings,
    required UserProfile userProfile,
    String styleExamplesPrompt = '',
  }) {
    return ContextBuilder.build(
      task: ContextTask.chat,
      settings: characterSettings,
      userProfile: userProfile,
      styleExamples: styleExamplesPrompt,
    );
  }

  static String buildDynamicSystemPrompt({
    required String timeContext,
    required String conversationEnginePrompt,
    required String personalityPrompt,
    required String replyLengthPrompt,
    String memoryPrompt = '',
    String activityPrompt = '',
  }) {
    return '''
$memoryPrompt

$timeContext

$activityPrompt

【场景优先级】
当前真实聊天中已经建立的位置、动作、时间推进和剧情，优先级高于手机系统显示的活动状态。
活动状态只允许作为刚开始聊天时的一点背景，不得强行把已经推进的聊天拉回原来的状态。

$conversationEnginePrompt

$personalityPrompt

【回复长度要求】
$replyLengthPrompt
''';
  }

  static String buildSystemPrompt({
    required CharacterSettings characterSettings,
    required UserProfile userProfile,
    required String timeContext,
    required String conversationEnginePrompt,
    required String personalityPrompt,
    required String replyLengthPrompt,
    String memoryPrompt = '',
    String activityPrompt = '',
    String styleExamplesPrompt = '',
  }) {
    return '''
${buildStableSystemPrompt(
      characterSettings: characterSettings,
      userProfile: userProfile,
      styleExamplesPrompt: styleExamplesPrompt,
    )}

${buildDynamicSystemPrompt(
      timeContext: timeContext,
      conversationEnginePrompt: conversationEnginePrompt,
      personalityPrompt: personalityPrompt,
      replyLengthPrompt: replyLengthPrompt,
      memoryPrompt: memoryPrompt,
      activityPrompt: activityPrompt,
    )}
''';
  }

  static String buildStyleExamplesPrompt(CharacterSettings settings) {
    final examples = settings.parseExampleMessages();
    if (examples.isEmpty) return '';

    final lines = examples.map((message) {
      final speaker = message['role'] == 'user'
          ? settings.userCallName
          : settings.characterName;
      return '$speaker：${message['content'] ?? ''}';
    }).join('\n');

    return '''
【语言风格样本｜STYLE_ONLY｜NON_FACTUAL】
以下文本只用于学习${settings.characterName}的语气、用词、句长、回应节奏、接梗方式和情绪表达。
它们不是历史聊天记录、共同记忆或当前剧情。
禁止主动提起、延续、引用或把样本写入记忆。
只学习表达方式，不学习内容。

<STYLE_EXAMPLES>
$lines
</STYLE_EXAMPLES>
''';
  }
}

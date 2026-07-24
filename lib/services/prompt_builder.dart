import '../models/character_settings.dart';
import '../models/user_profile.dart';
import '../prompts/relationship_prompt.dart';

class PromptBuilder {
  const PromptBuilder._();

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
${characterSettings.toPromptSection()}

${userProfile.toPromptSection()}

$relationshipPrompt

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

$styleExamplesPrompt
''';
  }

  static String buildStyleExamplesPrompt(CharacterSettings settings) {
    final examples = settings.parseExampleMessages();
    if (examples.isEmpty) return '';

    final lines = examples
        .map((message) {
          final speaker = message['role'] == 'user'
              ? settings.userCallName
              : settings.characterName;
          return '$speaker：${message['content'] ?? ''}';
        })
        .join('\n');

    return '''
【语言风格样本｜STYLE_ONLY｜NON_FACTUAL】
以下文本只用于学习${settings.characterName}的语气、用词、句长、回应节奏、接梗方式和情绪表达。

它们不是历史聊天记录，不是共同记忆，也不是当前剧情。
样本中的人物、事件、能力、地点、关系变化和话题全部视为虚构占位内容。

严格禁止：
1. 主动提起样本中的任何话题或设定。
2. 假设样本里的事情真实发生过。
3. 延续、追问、复述或引用样本里的剧情与原句。
4. 把样本内容写入记忆，或用它解释当前聊天。

只有用户资料、正式记忆和当前真实聊天可以被视为事实。
只学习表达方式，不学习内容。

<STYLE_EXAMPLES>
$lines
</STYLE_EXAMPLES>
''';
  }
}

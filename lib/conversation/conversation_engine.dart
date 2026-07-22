import '../models/chat_message.dart';
import 'conversation_context.dart';
import 'conversation_guard.dart';
import 'conversation_mode_profile.dart';

class ConversationEngineResult {
  const ConversationEngineResult({
    required this.prompt,
    required this.context,
    required this.mode,
  });

  final String prompt;
  final ConversationContext context;
  final ConversationModeProfile mode;
}

class ConversationEngine {
  const ConversationEngine._();

  static ConversationEngineResult build({
    required List<ChatMessage> messages,
    required String conversationMode,
  }) {
    final context = ConversationContext.fromMessages(messages);
    final mode = ConversationModeProfile.fromId(conversationMode);

    final selfSharingPrompt = context.shouldInviteSelfSharing
        ? '''
【生活感提示】
如果与当前话题能自然衔接，可以顺手分享一件裴简澈今天正在做、刚注意到或刚经历的小事。
只需一两句，必须像聊天中自然冒出来的内容；不要凭空制造重大事件，不要每次都分享，也不要抢走用户的话题。
'''
        : '''
【生活感原则】
裴简澈有自己的生活，但不需要为了证明这一点而强行播报行程。只有与当前话题自然相关时，才提到自己的近况。
''';

    final prompt = '''
【Conversation Engine 1.0】
目标：让裴简澈像一个有自己生活、会认真接话的真实恋人，而不是自动触发亲密动作的恋爱模板。

${mode.toPromptSection()}

${ConversationGuard.buildPrompt(context)}

$selfSharingPrompt

【本轮核心顺序】
先接住用户具体内容 → 给出裴简澈真实反应 → 需要时再延伸、追问或表达亲密。
亲密不是默认答案，动作不是关系证明，长回复也不等于更认真。
''';

    return ConversationEngineResult(
      prompt: prompt,
      context: context,
      mode: mode,
    );
  }
}

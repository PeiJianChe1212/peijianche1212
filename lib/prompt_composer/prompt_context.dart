enum PromptContextType {
  system,
  character,
  memory,
  conversation,
  relationship,
  cooldown,
  chatFlow,
  personalityStyle,
  replyStrategy,
  extension,
}

abstract final class PromptContextPriority {
  static const int system = 0;
  static const int character = 100;
  static const int memory = 200;
  static const int conversation = 300;
  static const int relationship = 400;
  static const int cooldown = 450;
  static const int chatFlow = 500;
  static const int personalityStyle = 600;
  static const int replyStrategy = 700;
}

class PromptContext {
  const PromptContext({
    required this.id,
    required this.type,
    required this.content,
    required this.priority,
  });

  final String id;
  final PromptContextType type;
  final String content;

  /// 数值越高，越靠近最终模型请求末尾，冲突时优先级越高。
  final int priority;

  factory PromptContext.chatFlow(String content) => PromptContext(
    id: 'chat_flow',
    type: PromptContextType.chatFlow,
    content: content,
    priority: PromptContextPriority.chatFlow,
  );

  factory PromptContext.cooldown(String content) => PromptContext(
    id: 'relationship_cooldown',
    type: PromptContextType.cooldown,
    content: content,
    priority: PromptContextPriority.cooldown,
  );

  factory PromptContext.personalityStyle(String content) => PromptContext(
    id: 'personality_style',
    type: PromptContextType.personalityStyle,
    content: content,
    priority: PromptContextPriority.personalityStyle,
  );

  factory PromptContext.replyStrategy(String content) => PromptContext(
    id: 'reply_strategy',
    type: PromptContextType.replyStrategy,
    content: content,
    priority: PromptContextPriority.replyStrategy,
  );

  /// Relationship Engine、Life Event、Echo、World Timeline、Group Context
  /// 等未来模块通过该入口接入，无需修改 Composer。
  factory PromptContext.extension({
    required String id,
    required String content,
    int priority = PromptContextPriority.relationship,
  }) => PromptContext(
    id: id,
    type: PromptContextType.extension,
    content: content,
    priority: priority,
  );
}

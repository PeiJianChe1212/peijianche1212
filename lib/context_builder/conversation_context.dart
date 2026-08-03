import '../models/chat_message.dart';

/// Conversation Context：保存有效聊天记录，并只向模型发送最近 36 条。
class ConversationContext {
  ConversationContext(List<ChatMessage> messages)
    : messages = List<ChatMessage>.unmodifiable(
        messages.where(
          (message) =>
              message.isVisibleInConversationContext &&
              (message.role == 'user' || message.role == 'assistant'),
        ),
      );

  final List<ChatMessage> messages;

  List<ChatMessage> get recentMessages =>
      messages.length > 36 ? messages.sublist(messages.length - 36) : messages;
}

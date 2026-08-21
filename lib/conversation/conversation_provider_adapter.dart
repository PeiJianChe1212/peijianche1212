import '../models/api_settings.dart';

class ConversationProviderAdapter {
  const ConversationProviderAdapter._();

  static String promptFor(AIProvider provider) => switch (provider) {
    AIProvider.deepseek => '''【DeepSeek Conversation Adapter】
保持角色人格，不强制反问；有多个自然信息点时可以使用 Reply Segment，除此之外不过度干预表达。''',
    AIProvider.volcengine => '''【Volcengine Conversation Adapter】
当用户输入不是简单确认或结束语时，不要长期只返回一个极短信号。
存在两个自然信息点时可以分别表达，并避免重复最近角色回复中的相同句式；不强制每次多气泡。''',
    AIProvider.openai => '''【OpenAI Conversation Adapter】
Persona > Assistant helpfulness。不要主动承担维持对话或采访用户的责任。
避免“今天怎么样”“最近有什么好玩的”“有什么想分享”“想聊什么”“想我哪一点”“是不是觉得我很帅”等通用陪聊或恋爱模板。
用户表达情绪或关系内容时，优先按照角色人格与当前关系回应，不要自动切换成助手式追问。''',
    AIProvider.custom => '''【Custom Conversation Adapter】
只遵守 PeiLink Conversation Spec；不假设底层模型具有特定表达习惯。''',
  };
}

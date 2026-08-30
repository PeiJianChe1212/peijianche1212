enum AiCapability { chat, imageGeneration, textToSpeech, speechToText }

extension AiCapabilityInfo on AiCapability {
  String get label => switch (this) {
    AiCapability.chat => '聊天',
    AiCapability.imageGeneration => '图片生成',
    AiCapability.textToSpeech => '语音合成',
    AiCapability.speechToText => '语音识别',
  };

  String get description => switch (this) {
    AiCapability.chat => '负责日常对话、记忆整理与结构化文本任务',
    AiCapability.imageGeneration => '为游记、今日快照和相册生成图片',
    AiCapability.textToSpeech => '把角色回复转换成语音',
    AiCapability.speechToText => '把用户语音转换成可发送的文字',
  };
}

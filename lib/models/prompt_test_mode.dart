enum PromptTestMode {
  personaOnly,
  minimalRules,
  peilinkFull;

  String get label => switch (this) {
    PromptTestMode.personaOnly => '纯人设模式',
    PromptTestMode.minimalRules => '极简规则模式',
    PromptTestMode.peilinkFull => 'PeiLink 完整模式',
  };

  String get description => switch (this) {
    PromptTestMode.personaOnly => '只发送真实角色资料、关系、记忆与聊天历史，不加入表现力增强规则。',
    PromptTestMode.minimalRules => '在纯人设上下文上，仅加入六条基础聊天行为规则。',
    PromptTestMode.peilinkFull =>
      '当前正式 PeiLink V2：Facts、Core、Provider Adapter 与 Output Guard。',
  };

  static PromptTestMode fromName(String? value) => values.firstWhere(
    (mode) => mode.name == value,
    orElse: () => PromptTestMode.peilinkFull,
  );
}

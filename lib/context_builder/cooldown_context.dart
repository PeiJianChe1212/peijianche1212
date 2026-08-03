class CooldownContext {
  const CooldownContext({required this.isInCooldown});

  final bool isInCooldown;

  String toPromptSection() {
    if (!isInCooldown) return '';
    return '''Relationship State:
Currently in cooldown.
The character is less talkative.
Avoid excessive enthusiasm and emotional expression.
Keep responses brief and basically polite.
Do not actively ask questions unless essential.''';
  }
}

import '../prompts/character_prompt.dart';
import '../prompts/example_messages.dart';

class CharacterSettings {
  const CharacterSettings({
    required this.coreProfile,
    required this.behaviorStyle,
    required this.forbiddenRules,
    required this.exampleDialogues,
  });

  final String coreProfile;
  final String behaviorStyle;
  final String forbiddenRules;
  final String exampleDialogues;

  factory CharacterSettings.defaults() => CharacterSettings(
    coreProfile: defaultCharacterCoreProfile,
    behaviorStyle: defaultCharacterBehaviorStyle,
    forbiddenRules: defaultCharacterForbiddenRules,
    exampleDialogues: _defaultExamplesText(),
  );

  Map<String, dynamic> toJson() => {
    'coreProfile': coreProfile,
    'behaviorStyle': behaviorStyle,
    'forbiddenRules': forbiddenRules,
    'exampleDialogues': exampleDialogues,
  };

  factory CharacterSettings.fromJson(Map<dynamic, dynamic> json) {
    final defaults = CharacterSettings.defaults();

    String read(String key, String fallback) {
      final value = json[key]?.toString().trim();
      return value == null || value.isEmpty ? fallback : value;
    }

    return CharacterSettings(
      coreProfile: read('coreProfile', defaults.coreProfile),
      behaviorStyle: read('behaviorStyle', defaults.behaviorStyle),
      forbiddenRules: read('forbiddenRules', defaults.forbiddenRules),
      exampleDialogues: read('exampleDialogues', defaults.exampleDialogues),
    );
  }

  String toPromptSection() =>
      '''
【裴简澈的人物设定】

$coreProfile

【说话与行为规则】

$behaviorStyle

【禁止事项】

$forbiddenRules
''';

  List<Map<String, String>> parseExampleMessages() {
    final result = <Map<String, String>>[];
    for (final rawLine in exampleDialogues.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;

      final separatorIndex = line.indexOf('：');
      if (separatorIndex <= 0 || separatorIndex >= line.length - 1) continue;

      final speaker = line.substring(0, separatorIndex).trim();
      final content = line.substring(separatorIndex + 1).trim();
      if (content.isEmpty) continue;

      if (speaker == '念念' || speaker == '用户' || speaker == '我') {
        result.add({'role': 'user', 'content': content});
      } else if (speaker == '裴简澈' || speaker == '老裴') {
        result.add({'role': 'assistant', 'content': content});
      }
    }
    return result.isEmpty
        ? List<Map<String, String>>.from(exampleMessages)
        : result;
  }

  static String _defaultExamplesText() => exampleMessages
      .map((message) {
        final speaker = message['role'] == 'user' ? '念念' : '裴简澈';
        return '$speaker：${message['content'] ?? ''}';
      })
      .join('\n');
}

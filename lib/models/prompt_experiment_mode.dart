import 'api_settings.dart';

enum PromptExperimentMode { dsA, dsB, dsC, dsD, dbA, dbB, dbC }

extension PromptExperimentModeDetails on PromptExperimentMode {
  String get code => switch (this) {
    PromptExperimentMode.dsA => 'DS-A',
    PromptExperimentMode.dsB => 'DS-B',
    PromptExperimentMode.dsC => 'DS-C',
    PromptExperimentMode.dsD => 'DS-D',
    PromptExperimentMode.dbA => 'DB-A',
    PromptExperimentMode.dbB => 'DB-B',
    PromptExperimentMode.dbC => 'DB-C',
  };

  String get label => switch (this) {
    PromptExperimentMode.dsA => 'Facts + Core',
    PromptExperimentMode.dsB => '+ Conversation Engine',
    PromptExperimentMode.dsC => '+ Personality Style',
    PromptExperimentMode.dsD => '+ Reply Strategy',
    PromptExperimentMode.dbA => 'Facts + Core',
    PromptExperimentMode.dbB => '+ Volcengine Adapter',
    PromptExperimentMode.dbC => '+ Adapter + Simplified Reply Strategy',
  };

  String get description => '$code · $label';

  AIProvider get requiredProvider => switch (this) {
    PromptExperimentMode.dsA ||
    PromptExperimentMode.dsB ||
    PromptExperimentMode.dsC ||
    PromptExperimentMode.dsD => AIProvider.deepseek,
    _ => AIProvider.volcengine,
  };

  bool supports(AIProvider provider) => provider == requiredProvider;

  List<String> get enabledModules => switch (this) {
    PromptExperimentMode.dsA ||
    PromptExperimentMode.dbA => const ['Character Facts', 'PeiLink Core'],
    PromptExperimentMode.dsB => const [
      'Character Facts',
      'PeiLink Core',
      'Conversation Engine',
    ],
    PromptExperimentMode.dsC => const [
      'Character Facts',
      'PeiLink Core',
      'Personality Style',
    ],
    PromptExperimentMode.dsD => const [
      'Character Facts',
      'PeiLink Core',
      'Reply Strategy',
    ],
    PromptExperimentMode.dbB => const [
      'Character Facts',
      'PeiLink Core',
      'Volcengine Provider Adapter',
    ],
    PromptExperimentMode.dbC => const [
      'Character Facts',
      'PeiLink Core',
      'Volcengine Provider Adapter',
      'Simplified Reply Guidance',
    ],
  };

  List<String> get disabledModules {
    const candidates = <String>[
      'Conversation Engine',
      'Personality Style',
      'Reply Strategy',
      'Volcengine Provider Adapter',
      'Simplified Reply Guidance',
      'Full Context Builder behavior rules',
      'Base relationship rules',
      'Chat Flow Prompt',
      'PeiLink Conversation Spec',
      'Style examples',
      'Natural chat / reply-length prompt',
      'Media rules',
      'Cooldown / event behavior prompt',
    ];
    return candidates.where((item) => !enabledModules.contains(item)).toList();
  }

  static PromptExperimentMode? fromName(String? value) {
    for (final mode in PromptExperimentMode.values) {
      if (mode.name == value) return mode;
    }
    return null;
  }
}

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/config/peilink_runtime.dart';
import 'package:peijianche_app/models/activity_status.dart';
import 'package:peijianche_app/models/api_settings.dart';
import 'package:peijianche_app/models/character_archive.dart';
import 'package:peijianche_app/models/character_profile.dart';
import 'package:peijianche_app/models/character_settings.dart';
import 'package:peijianche_app/models/prompt_experiment_mode.dart';
import 'package:peijianche_app/models/prompt_test_mode.dart';
import 'package:peijianche_app/models/user_profile.dart';
import 'package:peijianche_app/personality_style/personality_style_engine.dart';
import 'package:peijianche_app/services/prompt_experiment_context_builder.dart';
import 'package:peijianche_app/services/prompt_experiment_mode_service.dart';
import 'package:peijianche_app/services/prompt_test_snapshot_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory documentsDirectory;

  setUp(() async {
    documentsDirectory = await Directory.systemTemp.createTemp('prompt_exp_');
    PeiLinkRuntime.configure(PeiLinkBuild.dev);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => documentsDirectory.path,
        );
  });

  tearDown(() async {
    PeiLinkRuntime.configure(PeiLinkBuild.unspecified);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    await documentsDirectory.delete(recursive: true);
  });

  test(
    'experiment selection persists independently and can be cleared',
    () async {
      final service = PromptExperimentModeService();
      expect(await service.load(), isNull);
      await service.save(PromptExperimentMode.dsC);
      expect(
        await PromptExperimentModeService().load(),
        PromptExperimentMode.dsC,
      );
      await service.clear();
      expect(await service.load(), isNull);
    },
  );

  test('experiment provider compatibility is strict', () {
    expect(PromptExperimentMode.dsA.supports(AIProvider.deepseek), isTrue);
    expect(PromptExperimentMode.dsA.supports(AIProvider.volcengine), isFalse);
    expect(PromptExperimentMode.dbC.supports(AIProvider.volcengine), isTrue);
    expect(PromptExperimentMode.dbC.supports(AIProvider.deepseek), isFalse);
  });

  test(
    'Facts keeps archive language descriptive and excludes behavior guidance',
    () {
      const guidance = 'GUIDANCE_MUST_NOT_ENTER_FACTS';
      final prompt = PromptExperimentContextBuilder.buildFacts(
        settings: CharacterSettings.defaults().copyWith(
          coreProfile: '只是一段角色事实',
          behaviorStyle: 'BEHAVIOR_STRATEGY_MUST_NOT_ENTER_FACTS',
          forbiddenRules: 'FORBIDDEN_RULE_MUST_NOT_ENTER_FACTS',
          exampleDialogues: 'STYLE_EXAMPLE_MUST_NOT_ENTER_FACTS',
        ),
        profile: const CharacterProfile(
          characterId: 'test',
          name: '裴简澈',
          occupation: '医生',
        ),
        archive: const CharacterArchive(
          characterId: 'test',
          values: {'languageHabits': '偶尔用短句', 'chatPace': '熟人间节奏轻快'},
        ),
        user: const UserProfile(
          peiCallName: '念念',
          interactionPreference: '喜欢直接沟通',
        ),
        memory: '【已确认记忆】用户喜欢雨天',
        currentTime: '【当前时间事实】今天',
        recentLifeFacts: '【近期生活事实】刚结束一台手术',
        sharedWorldFacts: '【共享世界事实】昨天与顾言白见过面',
        relationshipFacts: '【关系网络事实】顾言白：认识',
        activity: const ActivityStatus(
          id: 'working',
          label: '工作中',
          emoji: '💼',
          detail: '正在整理资料',
          promptGuidance: guidance,
        ),
      );

      expect(prompt, contains('职业：医生'));
      expect(prompt, contains('用户喜欢雨天'));
      expect(prompt, contains('刚结束一台手术'));
      expect(prompt, contains('昨天与顾言白见过面'));
      expect(prompt, contains('顾言白：认识'));
      expect(prompt, contains('不是本轮行为策略'));
      expect(prompt, isNot(contains(guidance)));
      expect(prompt, isNot(contains('先回应事情本身')));
      expect(prompt, isNot(contains('不要急着说教')));
      expect(prompt, isNot(contains('BEHAVIOR_STRATEGY_MUST_NOT_ENTER_FACTS')));
      expect(prompt, isNot(contains('FORBIDDEN_RULE_MUST_NOT_ENTER_FACTS')));
      expect(prompt, isNot(contains('STYLE_EXAMPLE_MUST_NOT_ENTER_FACTS')));
    },
  );

  test(
    'DS-C style is resolved without Reply Strategy text and is snapshotted',
    () {
      final style = const PersonalityStyleEngine().resolveForExperiment(
        settings: CharacterSettings.defaults(),
      );
      final prompt =
          '${PromptExperimentContextBuilder.core}\n\n${style.toPromptSection()}';
      expect(prompt, contains('Personality Style'));
      expect(prompt, isNot(contains('Reply Strategy')));
      expect(
        style.snapshotValues.keys,
        containsAll(['tone', 'humor', 'initiative', 'formality', 'length']),
      );

      PromptTestSnapshotService.capture(
        mode: PromptTestMode.peilinkFull,
        experiment: PromptExperimentMode.dsC,
        provider: AIProvider.deepseek,
        enabledModules: PromptExperimentMode.dsC.enabledModules,
        disabledModules: PromptExperimentMode.dsC.disabledModules,
        styleValues: style.snapshotValues,
        messages: [
          {'role': 'system', 'content': prompt},
        ],
      );
      final display = PromptTestSnapshotService.latest!.displayText;
      expect(display, contains('tone='));
      expect(display, contains('humor='));
      expect(display, contains('initiative='));
      expect(display, contains('System characters:'));
      expect(display, contains('System SHA-256:'));
    },
  );

  test('experiment module matrix isolates the requested additions', () {
    expect(PromptExperimentMode.dsA.enabledModules, hasLength(2));
    expect(PromptExperimentMode.dbA.enabledModules, hasLength(2));
    expect(
      PromptExperimentMode.dsB.enabledModules,
      contains('Conversation Engine'),
    );
    expect(
      PromptExperimentMode.dsC.enabledModules,
      contains('Personality Style'),
    );
    expect(
      PromptExperimentMode.dsC.enabledModules,
      isNot(contains('Reply Strategy')),
    );
    expect(
      PromptExperimentMode.dsC.disabledModules,
      contains('Reply Strategy'),
    );
    expect(PromptExperimentMode.dsD.enabledModules, contains('Reply Strategy'));
    expect(
      PromptExperimentMode.dsD.enabledModules,
      isNot(contains('Chat Flow Prompt')),
    );
    expect(
      PromptExperimentMode.dbB.enabledModules,
      contains('Volcengine Provider Adapter'),
    );
    expect(
      PromptExperimentMode.dbC.enabledModules,
      contains('Simplified Reply Guidance'),
    );
    expect(
      PromptExperimentContextBuilder.simplifiedDoubaoStrategy,
      isNot(contains('%')),
    );
    expect(
      PromptExperimentContextBuilder.simplifiedDoubaoStrategy,
      isNot(contains('固定')),
    );
  });
}

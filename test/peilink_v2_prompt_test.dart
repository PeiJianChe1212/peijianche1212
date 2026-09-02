import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/config/peilink_runtime.dart';
import 'package:peijianche_app/context_builder/context_build_result.dart';
import 'package:peijianche_app/conversation/peilink_v2_prompt.dart';
import 'package:peijianche_app/conversation/reply_quality_guard.dart';
import 'package:peijianche_app/models/api_settings.dart';
import 'package:peijianche_app/models/prompt_test_mode.dart';
import 'package:peijianche_app/prompt_composer/prompt_composer.dart';
import 'package:peijianche_app/prompt_composer/prompt_context.dart';
import 'package:peijianche_app/services/prompt_test_snapshot_service.dart';

void main() {
  setUp(() => PeiLinkRuntime.configure(PeiLinkBuild.dev));
  tearDown(() => PeiLinkRuntime.configure(PeiLinkBuild.unspecified));

  String compose(AIProvider provider) {
    const facts = '【Character Facts】\n角色：裴简澈\n用户：林念念\n关系：夫妻';
    final composer = PromptComposer(
      baseContext: const ContextBuildResult(
        systemPrompt: facts,
        messages: [
          {'role': 'system', 'content': facts},
          {'role': 'user', 'content': '不知道去哪，你来定'},
        ],
      ),
    );
    composer
        .addContext(
          PromptContext.extension(
            id: 'peilink_v2_core',
            content: PeiLinkV2Prompt.core,
            priority: PromptContextPriority.character,
          ),
        )
        .addContext(
          PromptContext.providerAdapter(PeiLinkV2Prompt.adapterFor(provider)),
        );
    return composer.compose().systemPrompt;
  }

  test('DeepSeek V2 contains only Facts Core and the slim adapter', () {
    final prompt = compose(AIProvider.deepseek);
    expect(prompt, contains('【Character Facts】'));
    expect(prompt, contains('【PeiLink Core】'));
    expect(prompt, contains('这是即时通讯，不是小说正文'));
    expect(prompt, contains('动作、神态和情绪只用于理解角色'));
    expect(prompt, contains('不输出旁白式动作、神态、语气说明或舞台指令'));
    expect(prompt, contains('【DeepSeek Adapter】'));
    expect(prompt, contains('分享角色自己的生活'));
    expect(prompt, contains('提出一个具体方案'));
    expect(prompt, contains('少用机械反问'));
    expect(prompt, contains('“我陪你”'));
    expect(prompt, contains('不要把合理推测写成用户已经发生过的事实'));
    expect(prompt, contains('不冒充共同记忆'));
    expect(prompt, contains('身份、职业和关系只说明某件事可能发生'));
    expect(prompt, contains('不能证明具体历史已经发生'));
    expect(prompt, contains('已确认 Shared World Event'));
    expect(prompt, contains('角色自己的轻量日常仍可自然生成'));
    expect(prompt, contains('可以猜测和调侃'));
    expect(prompt, contains('保留幽默、毒舌和主动发挥'));
    expect(prompt, contains('不要长期只集中在传统霸总素材'));
    expect(prompt, isNot(contains('Personality Style')));
    expect(prompt, isNot(contains('Reply Strategy')));
    expect(prompt, isNot(contains('Chat Flow')));
    expect(prompt, isNot(contains('固定轮次')));
    expect(prompt, isNot(contains('气泡比例')));
    expect(prompt, isNot(contains('句数')));
    expect(prompt, isNot(contains('固定回复结构')));
    expect(prompt, isNot(contains('【Volcengine Adapter】')));
    expect(
      prompt.indexOf('【Character Facts】'),
      lessThan(prompt.indexOf('【PeiLink Core】')),
    );
    expect(
      prompt.indexOf('【PeiLink Core】'),
      lessThan(prompt.indexOf('【DeepSeek Adapter】')),
    );
  });

  test('Doubao V2 contains only the verified missing capabilities', () {
    final prompt = compose(AIProvider.volcengine);
    expect(prompt, contains('【Character Facts】'));
    expect(prompt, contains('【PeiLink Core】'));
    expect(prompt, contains('【Volcengine Adapter】'));
    expect(prompt, contains('给出至少一个具体内容'));
    expect(prompt, contains('不要只是把用户的陈述改写成反问'));
    expect(prompt, contains('补充一个确实不同的信息点'));
    expect(prompt, contains('每条承担不同内容'));
    expect(prompt, contains('不要长期连续只用一个极短问句'));
    expect(prompt, contains('不要求每轮变长或主动推进'));
    expect(prompt, contains('简单确认、斗嘴和情绪停顿仍可很短'));
    expect(prompt, contains('不为增加长度而灌水'));
    expect(prompt, contains('可以吃醋、嘴硬、强势、调侃'));
    expect(prompt, contains('不必无条件顺从'));
    expect(prompt, contains('不能替用户完成最终决定'));
    expect(prompt, contains('用户明确拒绝后'));
    expect(prompt, contains('不可取消的安排写成已经执行的事实'));
    expect(prompt, contains('仍可不爽、拌嘴、继续争取'));
    expect(prompt, isNot(contains('Personality Style')));
    expect(prompt, isNot(contains('Reply Strategy')));
    expect(prompt, isNot(contains('Chat Flow')));
    expect(prompt, isNot(contains('百分比')));
    expect(prompt, isNot(contains('固定回复结构')));
    expect(prompt, isNot(contains('固定句数')));
    expect(prompt, isNot(contains('固定气泡')));
    expect(prompt, isNot(contains('【DeepSeek Adapter】')));
  });

  test('provider adapters are strictly isolated for every provider', () {
    expect(
      PeiLinkV2Prompt.adapterNameFor(AIProvider.deepseek),
      'DeepSeek Adapter',
    );
    expect(
      PeiLinkV2Prompt.adapterNameFor(AIProvider.volcengine),
      'Volcengine Adapter',
    );
    for (final provider in [AIProvider.openai, AIProvider.custom]) {
      final prompt = PeiLinkV2Prompt.adapterFor(provider);
      expect(
        PeiLinkV2Prompt.adapterNameFor(provider),
        'Neutral Provider Adapter',
      );
      expect(prompt, isNot(contains('【DeepSeek Adapter】')));
      expect(prompt, isNot(contains('【Volcengine Adapter】')));
    }
    expect(
      PeiLinkV2Prompt.adapterFor(AIProvider.deepseek),
      isNot(contains('【Volcengine Adapter】')),
    );
    expect(
      PeiLinkV2Prompt.adapterFor(AIProvider.volcengine),
      isNot(contains('【DeepSeek Adapter】')),
    );
  });

  test('V2 snapshot identifies architecture adapter modules and messages', () {
    final system = compose(AIProvider.deepseek);
    PromptTestSnapshotService.capture(
      mode: PromptTestMode.peilinkFull,
      provider: AIProvider.deepseek,
      architecture: PeiLinkV2Prompt.architectureName,
      providerAdapter: PeiLinkV2Prompt.adapterNameFor(AIProvider.deepseek),
      enabledModules: const [
        'Character Facts',
        'PeiLink Core V2',
        'Provider Adapter V2',
        'Output Guard',
      ],
      disabledModules: const [
        'Personality Style',
        'Full Reply Strategy',
        'Round-modulo Chat Flow',
      ],
      messages: [
        {'role': 'system', 'content': system},
        {'role': 'user', 'content': '第一条真实消息'},
        {'role': 'assistant', 'content': '第二条真实消息'},
      ],
    );

    final snapshot = PromptTestSnapshotService.latest!;
    final display = snapshot.displayText;
    expect(snapshot.architecture, 'PeiLink V2');
    expect(snapshot.providerAdapter, 'DeepSeek Adapter');
    expect(display, contains('Prompt Architecture: PeiLink V2'));
    expect(display, contains('Provider: DeepSeek'));
    expect(display, contains('Provider Adapter: DeepSeek Adapter'));
    expect(display, contains('Character Facts'));
    expect(display, contains('Personality Style'));
    expect(display, contains('System characters:'));
    expect(display, contains('System SHA-256:'));
    expect(display.indexOf('第一条真实消息'), lessThan(display.indexOf('第二条真实消息')));
    expect(display, contains(system));
  });

  test('snapshot traces a fact to labels without returning its content', () {
    PromptTestSnapshotService.capture(
      mode: PromptTestMode.peilinkFull,
      messages: const [
        {'role': 'system', 'content': '【角色最近自己的生活｜统一叙事】\n旅行资料仍在桌上'},
        {'role': 'user', 'content': '聊点别的'},
        {'role': 'assistant', 'content': '旅行资料我还记得'},
      ],
    );
    final labels = PromptTestSnapshotService.latest!.sourceLabelsForTerm(
      '旅行资料',
    );
    expect(labels, contains('System section: 角色最近自己的生活｜统一叙事'));
    expect(labels, contains('Recent chat: assistant'));
    expect(labels.join('\n'), isNot(contains('仍在桌上')));
    expect(labels.join('\n'), isNot(contains('我还记得')));
  });

  test('Output Guard removes actions, internals and repetition', () {
    const guard = ReplyQualityGuard();
    final cleaned = guard.inspect(
      reply: '（指尖转着钢笔）\n消息1：去江边。\n消息2：我订七点的位子。',
      allowRetry: false,
    );
    expect(cleaned.output, isNot(contains('指尖转着钢笔')));
    expect(cleaned.output, isNot(contains('消息1')));
    expect(cleaned.output, contains('去江边'));

    final repeated = guard.inspect(
      reply: '老地方见。',
      recentAssistantReplies: const ['老地方见。'],
      allowRetry: false,
    );
    expect(repeated.output, isEmpty);
    expect(repeated.shouldRetry, isFalse);
  });
}

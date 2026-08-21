import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/conversation/conversation_provider_adapter.dart';
import 'package:peijianche_app/conversation/peilink_conversation_spec.dart';
import 'package:peijianche_app/context_builder/context_build_result.dart';
import 'package:peijianche_app/models/api_settings.dart';
import 'package:peijianche_app/prompt_composer/prompt_composer.dart';
import 'package:peijianche_app/prompt_composer/prompt_context.dart';

void main() {
  test('conversation spec keeps provider-independent chat rules', () {
    const prompt = PeiLinkConversationSpec.prompt;

    expect(prompt, contains('Persona First'));
    expect(prompt, contains('不要为了续聊强行开启新话题'));
    expect(prompt, contains('不得凭空制造重大事故'));
    expect(prompt, contains('Reply Segment'));
    expect(prompt, contains('独立动作或心理标签'));
  });

  test('each provider receives its own minimal adapter', () {
    final deepSeek = ConversationProviderAdapter.promptFor(AIProvider.deepseek);
    final volcengine = ConversationProviderAdapter.promptFor(
      AIProvider.volcengine,
    );
    final openAI = ConversationProviderAdapter.promptFor(AIProvider.openai);
    final custom = ConversationProviderAdapter.promptFor(AIProvider.custom);

    expect(deepSeek, contains('DeepSeek'));
    expect(volcengine, contains('Volcengine'));
    expect(openAI, contains('OpenAI'));
    expect(openAI, contains('Persona > Assistant'));
    expect(custom, contains('Custom'));
    expect(custom, isNot(contains('DeepSeek')));
    expect(custom, isNot(contains('Persona > Assistant')));
  });

  test('final prompt contains only the selected provider adapter', () {
    const providerLabels = {
      AIProvider.deepseek: 'DeepSeek Conversation Adapter',
      AIProvider.volcengine: 'Volcengine Conversation Adapter',
      AIProvider.openai: 'OpenAI Conversation Adapter',
      AIProvider.custom: 'Custom Conversation Adapter',
    };

    for (final selected in AIProvider.values) {
      final result =
          PromptComposer(
                baseContext: const ContextBuildResult(
                  messages: [
                    {'role': 'system', 'content': '角色人设'},
                    {'role': 'user', 'content': '在吗'},
                  ],
                  systemPrompt: '角色人设',
                ),
              )
              .addContext(
                PromptContext.conversationSpec(PeiLinkConversationSpec.prompt),
              )
              .addContext(
                PromptContext.providerAdapter(
                  ConversationProviderAdapter.promptFor(selected),
                ),
              )
              .compose();

      expect(result.systemPrompt, contains(providerLabels[selected]!));
      for (final other in AIProvider.values.where((item) => item != selected)) {
        expect(result.systemPrompt, isNot(contains(providerLabels[other]!)));
      }
    }
  });
}

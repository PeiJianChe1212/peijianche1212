import '../context_builder/context_build_result.dart';
import 'prompt_context.dart';

class PromptComposer {
  PromptComposer({required this.baseContext});

  final ContextBuildResult baseContext;
  final List<PromptContext> _contexts = <PromptContext>[];

  PromptComposer addContext(PromptContext context) {
    final content = context.content.trim();
    if (content.isEmpty) return this;
    _contexts.removeWhere((item) => item.id == context.id);
    _contexts.add(
      PromptContext(
        id: context.id,
        type: context.type,
        content: content,
        priority: context.priority,
      ),
    );
    return this;
  }

  ContextBuildResult compose() {
    final ordered = _contexts.toList()
      ..sort((left, right) {
        final priority = left.priority.compareTo(right.priority);
        if (priority != 0) return priority;
        return left.id.compareTo(right.id);
      });
    final sections = <String>[
      baseContext.systemPrompt,
      ...ordered.map((context) => context.content),
    ].where((content) => content.trim().isNotEmpty).toList();
    final systemPrompt = sections.join('\n\n');
    final messages = baseContext.messages
        .map((message) => Map<String, dynamic>.from(message))
        .toList();
    if (messages.isNotEmpty) messages.first['content'] = systemPrompt;

    // ignore: avoid_print
    print(
      '[PromptComposer] final request composed: '
      'contexts=${ordered.map((item) => item.id).join(',')}, '
      'messages=${messages.length}',
    );
    return ContextBuildResult(messages: messages, systemPrompt: systemPrompt);
  }
}

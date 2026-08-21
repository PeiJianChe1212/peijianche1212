import '../models/echo_item.dart';
import '../models/story_fragment.dart';
import 'echo_storage_service.dart';
import 'life_moment_storage_service.dart';
import 'narrative_engine_service.dart';
import 'story_fragment_engine_service.dart';

/// 把角色最近公开过的 Echo 与真实生活，统一整理成聊天可读取的叙事背景。
class EchoChatContextService {
  EchoChatContextService({required this.characterId});

  final String characterId;

  Future<String> buildPromptSection() async {
    final facts = await buildFactsSection();
    if (facts.isEmpty) return '';
    return '''
$facts

使用规则：
1. 这些是角色自己的近期经历，不是用户说过的话，也不是必须主动提起的话题。
2. 只有用户问到近况、Echo 内容，或当前聊天自然相关时，才可以顺手接上。
3. 不要逐条复述，不要像汇报行程，也不要说“根据我的朋友圈”。
4. 同一故事片段只能改变说法，不能新增地点、天气、人物或事件。
5. 不要把尚未公开的故事片段说成已经发过 Echo。
'''
        .trim();
  }

  /// V2 Facts 专用：只输出已经存储的近期生活，不附加回复策略。
  Future<String> buildFactsSection() async {
    final echoes = await EchoStorageService(
      characterId: characterId,
    ).loadItems();
    final moments = await LifeMomentStorageService(
      characterId: characterId,
    ).loadItems();

    final recentEchoes = echoes
        .where((item) => item.content.trim().isNotEmpty)
        .take(5)
        .toList();
    final fragments = const StoryFragmentEngineService().build(
      moments,
      limit: 5,
    );

    if (recentEchoes.isEmpty && fragments.isEmpty) return '';

    final buffer = StringBuffer('【角色最近自己的生活｜统一叙事】\n');

    if (recentEchoes.isNotEmpty) {
      buffer.writeln('最近公开过的 Echo：');
      for (final item in recentEchoes) {
        buffer.writeln('- ${_formatEcho(item)}');
      }
    }

    if (fragments.isNotEmpty) {
      buffer.writeln('最近真实发生过、但不一定全部公开的故事片段：');
      for (final fragment in fragments) {
        final narrative = const NarrativeEngineService().render(
          fragment,
          perspective: NarrativePerspective.chat,
        );
        if (narrative.content.trim().isNotEmpty) {
          buffer.writeln('- ${narrative.content}');
        }
      }
    }

    return buffer.toString().trim();
  }

  String _formatEcho(EchoItem item) {
    final date = item.createdAt;
    final content = _truncate(item.content, 180);
    return '${date.month}/${date.day}：$content';
  }

  String _truncate(String value, int maxLength) {
    final clean = value.trim();
    if (clean.length <= maxLength) return clean;
    return '${clean.substring(0, maxLength)}…';
  }
}

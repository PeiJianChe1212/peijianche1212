import '../models/echo_item.dart';
import '../models/life_moment.dart';
import 'echo_storage_service.dart';
import 'life_moment_storage_service.dart';

/// 把角色最近在 Echo 里公开过的生活，以及背后的生活片段，
/// 整理成聊天模型可以自然使用的轻量背景。
///
/// 这不是强制话题，也不是让角色每次都主动复述朋友圈。
class EchoChatContextService {
  EchoChatContextService({required this.characterId});

  final String characterId;

  Future<String> buildPromptSection() async {
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
    final recentMoments = moments.take(5).toList();

    if (recentEchoes.isEmpty && recentMoments.isEmpty) return '';

    final buffer = StringBuffer('【角色最近自己的生活｜Echo 连续性】\n');

    if (recentEchoes.isNotEmpty) {
      buffer.writeln('最近公开过的 Echo：');
      for (final item in recentEchoes) {
        buffer.writeln('- ${_formatEcho(item)}');
      }
    }

    if (recentMoments.isNotEmpty) {
      buffer.writeln('最近真实发生过、但不一定全部公开的生活片段：');
      for (final item in recentMoments) {
        buffer.writeln('- ${_formatMoment(item)}');
      }
    }

    buffer.writeln('''
使用规则：
1. 这些是角色自己的近期经历，不是用户说过的话，也不是必须主动提起的话题。
2. 只有用户问到近况、Echo 内容，或当前聊天自然相关时，才可以顺手接上。
3. 不要每次聊天都复述 Echo，不要像汇报行程，也不要说“根据我的朋友圈”。
4. 可以自然体现事情的后续、余味或尚未解决的小问题，让聊天和 Echo 属于同一段生活。
5. 不要把尚未发布的生活片段说成已经发过 Echo。
''');

    return buffer.toString().trim();
  }

  String _formatEcho(EchoItem item) {
    final date = item.createdAt;
    final content = _truncate(item.content, 180);
    return '${date.month}/${date.day}：$content';
  }

  String _formatMoment(LifeMomentCandidate item) {
    final date = item.occurredAt;
    final event = _truncate(item.event, 100);
    final detail = _truncate(item.detail, 100);
    final feeling = _truncate(item.feeling, 70);
    return '${date.month}/${date.day}：$event；细节：$detail；感受：$feeling';
  }

  String _truncate(String value, int maxLength) {
    final clean = value.trim();
    if (clean.length <= maxLength) return clean;
    return '${clean.substring(0, maxLength)}…';
  }
}

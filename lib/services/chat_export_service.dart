import 'dart:convert';
import 'dart:typed_data';

import '../models/ai_character.dart';
import '../models/chat_message.dart';
import 'chat_storage_service.dart';
import 'pei_file_platform_service.dart';

/// Exports chat history as a readable .txt file via the platform save dialog.
///
/// Does NOT include API keys, system prompts, internal reasoning, or
/// hidden character configuration. Only user-visible conversation content.
class ChatExportService {
  const ChatExportService();

  Future<({bool ok, String message})> exportChat({
    required AiCharacter character,
  }) async {
    final storage = ChatStorageService(characterId: character.id);
    final messages = await storage.loadMessages();

    final visible = messages
        .where((m) => m.messageStatus != MessageStatus.recalled)
        .where((m) => m.type == MessageType.text || m.type == MessageType.image)
        .toList();

    if (visible.isEmpty) {
      return (ok: false, message: '当前没有可导出的聊天记录');
    }

    final buffer = StringBuffer();
    buffer.writeln('PeiLink 聊天记录导出');
    buffer.writeln('角色：${character.characterName}');
    buffer.writeln('导出时间：${DateTime.now().toIso8601String()}');
    buffer.writeln('消息总数：${visible.length}');
    buffer.writeln('=' * 40);
    buffer.writeln();

    for (final m in visible) {
      final who = m.role == 'user' ? '我' : character.characterName;
      final time = m.createdAt.toLocal().toString().substring(0, 19);
      if (m.type == MessageType.image) {
        buffer.writeln('[$time] $who：[图片消息]');
      } else {
        buffer.writeln('[$time] $who：');
        buffer.writeln(m.content);
      }
      buffer.writeln();
    }

    final bytes = Uint8List.fromList(utf8.encode(buffer.toString()));
    final safeName = character.characterName.replaceAll(RegExp(r'[^\w\u4e00-\u9fff]'), '_');
    final ok = await PeiFilePlatformService().saveFile(
      suggestedName: 'PeiLink_聊天记录_${safeName}_${DateTime.now().millisecondsSinceEpoch}.txt',
      bytes: bytes,
    );

    if (ok) {
      return (ok: true, message: '聊天记录已导出');
    }
    return (ok: false, message: '导出取消或保存失败');
  }
}

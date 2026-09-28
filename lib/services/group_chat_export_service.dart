import 'dart:convert';
import 'dart:typed_data';

import '../../models/group_message.dart';
import '../../services/group_message_storage_service.dart';
import '../../services/pei_file_platform_service.dart';

class GroupChatExportService {
  const GroupChatExportService();

  Future<({bool ok, String message})> exportGroup({
    required String groupId,
    required String groupName,
  }) async {
    final msgs = await GroupMessageStorageService(groupId: groupId).loadMessages();
    if (msgs.isEmpty) return (ok: false, message: '没有可导出的聊天记录');

    final buf = StringBuffer();
    buf.writeln('PeiLink 群聊记录导出');
    buf.writeln('群聊：$groupName');
    buf.writeln('导出时间：${DateTime.now().toIso8601String()}');
    buf.writeln('消息数：${msgs.length}');
    buf.writeln('=' * 40);
    for (final m in msgs) {
      final who = m.senderType == GroupSenderType.user ? '我' : m.senderId;
      final time = m.createdAt.toLocal().toString().substring(0, 19);
      buf.writeln('[$time] $who: ${m.content}');
    }

    final bytes = Uint8List.fromList(utf8.encode(buf.toString()));
    final ok = await PeiFilePlatformService().saveFile(
      suggestedName: 'PeiLink_群聊_${groupName}_${DateTime.now().millisecondsSinceEpoch}.txt',
      bytes: bytes,
    );
    return ok ? (ok: true, message: '群聊记录已导出') : (ok: false, message: '导出取消');
  }
}

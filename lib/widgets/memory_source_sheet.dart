import 'dart:io';
import 'package:flutter/material.dart';
import '../models/chat_message.dart';
import '../services/memory_center_controller.dart';
import '../services/memory_source_resolver.dart';

Future<void> showMemorySources(
  BuildContext context,
  MemoryCenterController controller,
  List<String> ids, {
  String? legacySourceId,
}) async {
  List<ResolvedMemorySource> sources;
  try {
    sources = await controller.resolveSources(ids);
  } catch (_) {
    sources = ids.map((id) => ResolvedMemorySource(messageId: id)).toList();
  }
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (_) => ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.all(16),
      children: [
        const Text('记忆来源'),
        if (ids.isEmpty)
          Text(
            legacySourceId?.isNotEmpty == true
                ? '来源：旧版记忆（没有聊天来源）'
                : '这条记忆没有聊天来源',
          ),
        for (final source in sources)
          ListTile(
            title: Text(
              source.available
                  ? '${_typeName(source.type)} · ${source.createdAt!.toLocal().toString().split('.').first}'
                  : '原始来源已不可用',
            ),
            subtitle: source.available
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (source.preview.isNotEmpty) Text(source.preview),
                      if (source.imagePath != null)
                        Image.file(
                          File(source.imagePath!),
                          height: 96,
                          width: 96,
                          cacheWidth: 192,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const Text('原始图片已不可用'),
                        ),
                      if (source.imageMissing) const Text('原始图片已不可用'),
                      if (source.visionPreview.isNotEmpty)
                        Text('AI 视觉描述（非用户自述）：${source.visionPreview}'),
                    ],
                  )
                : null,
          ),
      ],
    ),
  );
}

String _typeName(MessageType? type) => switch (type) {
  MessageType.image => '图片',
  MessageType.voice => '语音',
  MessageType.system => '系统消息',
  MessageType.card => '卡片',
  MessageType.redPacket => '红包',
  _ => '聊天文字',
};

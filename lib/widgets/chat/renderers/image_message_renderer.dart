import 'dart:io';

import 'package:flutter/material.dart';

import '../../../models/chat_message.dart';
import '../chat_image_preview.dart';

class ImageMessageRenderer extends StatelessWidget {
  const ImageMessageRenderer({super.key, required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final path = message.metadata['imagePath']?.toString().trim() ?? '';
    final file = path.isEmpty ? null : File(path);
    final hasImage = file != null && file.existsSync();
    return GestureDetector(
      key: const Key('chat-image-preview-trigger'),
      behavior: HitTestBehavior.opaque,
      onTap: hasImage ? () => ChatImagePreview.open(context, file.path) : null,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: hasImage
            ? ConstrainedBox(
                constraints: const BoxConstraints(
                  minWidth: 150,
                  minHeight: 120,
                  maxWidth: 230,
                  maxHeight: 310,
                ),
                child: Image.file(
                  file,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const _MissingImage(),
                ),
              )
            : const _MissingImage(),
      ),
    );
  }
}

class _MissingImage extends StatelessWidget {
  const _MissingImage();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 180,
      height: 120,
      alignment: Alignment.center,
      color: Colors.black.withValues(alpha: 0.06),
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.broken_image_outlined, color: Colors.black38),
          SizedBox(height: 6),
          Text('图片已失效', style: TextStyle(fontSize: 12, color: Colors.black38)),
        ],
      ),
    );
  }
}

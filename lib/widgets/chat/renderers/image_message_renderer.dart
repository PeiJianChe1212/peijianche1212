import 'dart:io';

import 'package:flutter/material.dart';

import '../../../models/chat_message.dart';
import 'text_message_renderer.dart';

class ImageMessageRenderer extends StatelessWidget {
  const ImageMessageRenderer({super.key, required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final path = message.metadata['imagePath']?.toString().trim() ?? '';
    final file = path.isEmpty ? null : File(path);
    final hasImage = file != null && file.existsSync();
    final caption = message.content.trim();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: hasImage
              ? ConstrainedBox(
                  constraints: const BoxConstraints(
                    minWidth: 150,
                    maxWidth: 230,
                    maxHeight: 310,
                  ),
                  child: Image.file(
                    file!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const _MissingImage(),
                  ),
                )
              : const _MissingImage(),
        ),
        if (caption.isNotEmpty) ...[
          const SizedBox(height: 8),
          TextMessageRenderer(message: message),
        ],
      ],
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
          Text(
            '图片已失效',
            style: TextStyle(fontSize: 12, color: Colors.black38),
          ),
        ],
      ),
    );
  }
}

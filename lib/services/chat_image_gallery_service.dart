import 'dart:io';

import 'package:flutter/services.dart';

class ChatImageGalleryService {
  const ChatImageGalleryService();

  static const MethodChannel _channel = MethodChannel(
    'peilink/chat_image_gallery',
  );

  Future<void> save(String imagePath) async {
    final path = imagePath.trim();
    if (path.isEmpty || !await File(path).exists()) {
      throw StateError('图片文件不存在。');
    }
    final saved = await _channel.invokeMethod<bool>('save', {'path': path});
    if (saved != true) throw StateError('图片保存失败。');
  }
}

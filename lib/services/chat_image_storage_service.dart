import 'dart:io';

import 'character_scope_service.dart';

/// 将聊天中选择的图片复制到角色自己的长期目录。
///
/// image_picker 返回的路径可能只是系统临时文件，不能直接拿来长期保存。
class ChatImageStorageService {
  const ChatImageStorageService({this.characterId});

  final String? characterId;


  Future<Directory> imageDirectory() async {
    final characterDirectory =
        await CharacterScopeService(characterId).characterDirectory();
    final directory = Directory('${characterDirectory.path}/chat_images');
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  Future<String> saveImage({
    required String sourcePath,
    required String messageId,
  }) async {
    final source = File(sourcePath);
    if (!await source.exists()) {
      throw StateError('选择的图片已经不存在。');
    }

    final imageDirectory = await this.imageDirectory();

    final extension = _extensionOf(sourcePath);
    final target = File(
      '${imageDirectory.path}/${messageId}_${DateTime.now().microsecondsSinceEpoch}$extension',
    );
    await source.copy(target.path);
    return target.path;
  }

  Future<void> deleteImage(String path) async {
    if (path.trim().isEmpty) return;
    final file = File(path);
    if (!await file.exists()) return;
    try {
      await file.delete();
    } catch (_) {
      // 图片清理失败不应阻断聊天回溯或重置。
    }
  }

  String _extensionOf(String path) {
    final dot = path.lastIndexOf('.');
    if (dot < 0 || dot == path.length - 1) return '.jpg';
    final extension = path.substring(dot).toLowerCase();
    const supported = {'.jpg', '.jpeg', '.png', '.webp', '.gif'};
    return supported.contains(extension) ? extension : '.jpg';
  }
}

import 'dart:typed_data';

import 'media_store.dart';

MediaStore createDefaultMediaStore() => const UnsupportedMediaStore();

class UnsupportedMediaStore implements MediaStore {
  const UnsupportedMediaStore();
  Never _unsupported() => throw UnsupportedError('当前平台尚未实现 PeiLink 媒体存储。');
  @override
  Future<String> saveBytes(String reference, Uint8List bytes) async =>
      _unsupported();
  @override
  Future<Uint8List> readBytes(String reference) async => _unsupported();
  @override
  Future<bool> exists(String reference) async => _unsupported();
  @override
  Future<void> delete(String reference) async => _unsupported();
}

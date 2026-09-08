import 'dart:typed_data';

abstract interface class MediaStore {
  Future<String> saveBytes(String reference, Uint8List bytes);
  Future<Uint8List> readBytes(String reference);
  Future<bool> exists(String reference);
  Future<void> delete(String reference);
}

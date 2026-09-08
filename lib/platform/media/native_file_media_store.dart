import 'dart:io';
import 'dart:typed_data';

import 'media_store.dart';

class NativeFileMediaStore implements MediaStore {
  const NativeFileMediaStore();

  @override
  Future<String> saveBytes(String reference, Uint8List bytes) async {
    final file = File(reference);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  @override
  Future<Uint8List> readBytes(String reference) =>
      File(reference).readAsBytes();
  @override
  Future<bool> exists(String reference) => File(reference).exists();
  @override
  Future<void> delete(String reference) async {
    final file = File(reference);
    if (await file.exists()) await file.delete();
  }
}

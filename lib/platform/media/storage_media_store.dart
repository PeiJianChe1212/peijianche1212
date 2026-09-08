import 'dart:typed_data';

import '../storage/platform_storage.dart';
import 'media_store.dart';

class StorageMediaStore implements MediaStore {
  const StorageMediaStore(this.storage);

  final PlatformStorage storage;

  @override
  Future<String> saveBytes(String reference, Uint8List bytes) async {
    await storage.writeBytes(reference, bytes);
    return storage.reference(reference);
  }

  @override
  Future<Uint8List> readBytes(String reference) => storage.readBytes(reference);
  @override
  Future<bool> exists(String reference) => storage.exists(reference);
  @override
  Future<void> delete(String reference) => storage.delete(reference);
}

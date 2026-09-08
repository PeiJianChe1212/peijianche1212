import 'media_store.dart';
import 'native_file_media_store.dart';

MediaStore createDefaultMediaStore() => const NativeFileMediaStore();

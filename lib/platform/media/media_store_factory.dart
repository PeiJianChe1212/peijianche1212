import 'media_store.dart';
import 'media_store_factory_unsupported.dart'
    if (dart.library.io) 'media_store_factory_native.dart'
    as implementation;

MediaStore createDefaultMediaStore() =>
    implementation.createDefaultMediaStore();

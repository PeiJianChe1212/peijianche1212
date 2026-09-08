import 'platform_storage.dart';
import 'storage_factory_unsupported.dart'
    if (dart.library.io) 'storage_factory_native.dart'
    if (dart.library.html) 'storage_factory_web.dart'
    as implementation;

Future<PlatformStorage> createPlatformStorage(String namespace) =>
    implementation.createPlatformStorage(namespace);

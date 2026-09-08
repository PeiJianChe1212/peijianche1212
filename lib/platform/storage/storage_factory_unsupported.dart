import 'platform_storage.dart';

Future<PlatformStorage> createPlatformStorage(String namespace) async =>
    const UnsupportedPlatformStorage();

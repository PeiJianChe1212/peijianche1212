import 'platform_storage.dart';
import 'web_indexeddb_platform_storage.dart';

final Map<String, Future<PlatformStorage>> _instances = {};

Future<PlatformStorage> createPlatformStorage(String namespace) => _instances
    .putIfAbsent(namespace, () => WebIndexedDbPlatformStorage.open(namespace));

import 'dart:io';

import 'package:path_provider/path_provider.dart' as path_provider;

import 'native_platform_storage.dart';
import 'platform_storage.dart';

Future<PlatformStorage> createPlatformStorage(String namespace) async {
  final base = await path_provider.getApplicationDocumentsDirectory();
  final root = namespace.isEmpty ? base : Directory('${base.path}/$namespace');
  if (!await root.exists()) await root.create(recursive: true);
  return NativePlatformStorage(root.path);
}

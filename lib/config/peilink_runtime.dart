import 'dart:io';

import 'package:path_provider/path_provider.dart' as path_provider;

enum PeiLinkBuild { dev, user, unspecified }

/// Runtime-only build configuration. Feature services stay unaware of flavors;
/// they only receive an isolated documents root and secure-storage namespace.
abstract final class PeiLinkRuntime {
  static PeiLinkBuild _build = PeiLinkBuild.unspecified;

  static PeiLinkBuild get build => _build;
  static bool get developerToolsEnabled => _build == PeiLinkBuild.dev;
  static String get appName =>
      developerToolsEnabled ? 'PeiLink Dev' : 'PeiLink';
  static String get dataNamespace => switch (_build) {
    PeiLinkBuild.dev => 'peilink_dev',
    PeiLinkBuild.user => 'peilink_user',
    PeiLinkBuild.unspecified => '',
  };

  static void configure(PeiLinkBuild build) => _build = build;

  static Future<Directory> documentsDirectory() async {
    final base = await path_provider.getApplicationDocumentsDirectory();
    if (dataNamespace.isEmpty) return base;
    final directory = Directory('${base.path}/$dataNamespace');
    if (!await directory.exists()) await directory.create(recursive: true);
    return directory;
  }

  static String secureStorageKey(String key) =>
      dataNamespace.isEmpty ? key : '${dataNamespace}_$key';
}

/// Drop-in path-provider boundary used by storage services. Keeping this name
/// makes the environment split mechanical and avoids changing feature logic.
Future<Directory> getApplicationDocumentsDirectory() =>
    PeiLinkRuntime.documentsDirectory();

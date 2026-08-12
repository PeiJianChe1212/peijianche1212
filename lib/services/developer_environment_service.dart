import 'dart:convert';
import 'dart:io';

import '../config/peilink_runtime.dart';

class DeveloperEnvironmentState {
  const DeveloperEnvironmentState({required this.enabled});
  final bool enabled;
  Map<String, dynamic> toJson() => {'enabled': enabled};
}

/// Controls visibility of developer-only world data without deleting it.
class DeveloperEnvironmentService {
  static const String _developerKey = String.fromEnvironment(
    'PEILINK_DEVELOPER_KEY',
    defaultValue: 'PeiLink2026.v2.6',
  );
  static const String _fileName = 'developer_environment.json';

  Future<File> _file() async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/$_fileName');
  }

  Future<DeveloperEnvironmentState> load() async {
    final file = await _file();
    if (!await file.exists()) {
      return const DeveloperEnvironmentState(enabled: false);
    }
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map) {
        return DeveloperEnvironmentState(enabled: decoded['enabled'] == true);
      }
    } catch (_) {}
    return const DeveloperEnvironmentState(enabled: false);
  }

  Future<bool> isEnabled() async =>
      PeiLinkRuntime.developerToolsEnabled && (await load()).enabled;

  bool accessGranted({String? key, bool designatedAccount = false}) {
    if (!PeiLinkRuntime.developerToolsEnabled) return false;
    if (designatedAccount) return true;
    return _developerKey.isNotEmpty && key?.trim() == _developerKey;
  }

  Future<void> setEnabled(
    bool value, {
    String? key,
    bool designatedAccount = false,
  }) async {
    if (value && !PeiLinkRuntime.developerToolsEnabled) {
      throw StateError('当前构建不包含开发者环境。');
    }
    if (value &&
        !accessGranted(key: key, designatedAccount: designatedAccount)) {
      throw StateError('当前构建未获得开发者沙盒权限。');
    }
    final file = await _file();
    await file.writeAsString(
      jsonEncode(DeveloperEnvironmentState(enabled: value).toJson()),
      flush: true,
    );
  }
}

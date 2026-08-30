import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../config/peilink_runtime.dart';

class CoreBridgeConfig {
  const CoreBridgeConfig({required this.enabled, required this.token});

  final bool enabled;
  final String token;
}

class CoreBridgeConfigService {
  CoreBridgeConfigService({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const int port = 43127;
  static const _enabledKey = 'core_bridge_enabled';
  static const _tokenKey = 'core_bridge_token';

  static String _key(String value) => PeiLinkRuntime.secureStorageKey(value);

  Future<CoreBridgeConfig> load() async {
    final enabled = await _storage.read(key: _key(_enabledKey)) == 'true';
    final token = await _storage.read(key: _key(_tokenKey)) ?? '';
    return CoreBridgeConfig(enabled: enabled, token: token);
  }

  Future<String> enable() async {
    var token = await _storage.read(key: _key(_tokenKey)) ?? '';
    if (token.isEmpty) {
      token = _createToken();
      await _storage.write(key: _key(_tokenKey), value: token);
    }
    await _storage.write(key: _key(_enabledKey), value: 'true');
    return token;
  }

  Future<void> disable() =>
      _storage.write(key: _key(_enabledKey), value: 'false');

  Future<String> rotateToken() async {
    final token = _createToken();
    await _storage.write(key: _key(_tokenKey), value: token);
    return token;
  }

  String _createToken() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join();
  }
}

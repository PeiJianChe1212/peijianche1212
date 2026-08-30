import 'core_bridge_config_service.dart';
import 'core_bridge_server.dart';

class CoreBridgeRuntime {
  CoreBridgeRuntime._();

  static final CoreBridgeRuntime instance = CoreBridgeRuntime._();

  final CoreBridgeConfigService _config = CoreBridgeConfigService();
  final CoreBridgeServer _server = CoreBridgeServer();

  bool get isRunning => _server.isRunning;

  Future<void> initialize() async {
    final config = await _config.load();
    if (config.enabled && config.token.isNotEmpty) {
      try {
        await _server.start(token: config.token);
      } catch (_) {
        await _config.disable();
      }
    }
  }

  Future<String> enable() async {
    final token = await _config.enable();
    try {
      await _server.start(token: token);
      return token;
    } catch (_) {
      await _config.disable();
      rethrow;
    }
  }

  Future<void> disable() async {
    await _config.disable();
    await _server.stop();
  }

  Future<String> rotateToken() async {
    final token = await _config.rotateToken();
    if (_server.isRunning) {
      await _server.stop();
      await _server.start(token: token);
    }
    return token;
  }

  Future<CoreBridgeConfig> loadConfig() => _config.load();
}

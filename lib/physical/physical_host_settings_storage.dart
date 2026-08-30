import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../config/peilink_runtime.dart';
import 'physical_host_settings.dart';

class PhysicalHostSettingsStorage {
  PhysicalHostSettingsStorage({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  static String _key(String value) =>
      PeiLinkRuntime.secureStorageKey('physical_$value');

  Future<PhysicalHostSettings> load() async {
    final values = await _storage.readAll();
    return PhysicalHostSettings(
      esp32Host: values[_key('esp32_host')] ?? '',
      requestKey: values[_key('request_key')] ?? '',
      volcengineApiKey: values[_key('volcengine_api_key')] ?? '',
      boostingTableId: values[_key('boosting_table_id')] ?? '',
      characterId: values[_key('character_id')] ?? '',
      playbackGain:
          double.tryParse(values[_key('playback_gain')] ?? '') ?? 0.18,
    );
  }

  Future<void> save(PhysicalHostSettings value) async {
    final gain = value.playbackGain.clamp(0.01, 0.25);
    await Future.wait([
      _storage.write(key: _key('esp32_host'), value: value.esp32Host.trim()),
      _storage.write(key: _key('request_key'), value: value.requestKey.trim()),
      _storage.write(
        key: _key('volcengine_api_key'),
        value: value.volcengineApiKey.trim(),
      ),
      _storage.write(
        key: _key('boosting_table_id'),
        value: value.boostingTableId.trim(),
      ),
      _storage.write(
        key: _key('character_id'),
        value: value.characterId.trim(),
      ),
      _storage.write(key: _key('playback_gain'), value: gain.toString()),
    ]);
  }
}

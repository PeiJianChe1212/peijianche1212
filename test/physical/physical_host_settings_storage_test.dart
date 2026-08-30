import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/config/peilink_runtime.dart';
import 'package:peijianche_app/physical/physical_host_settings.dart';
import 'package:peijianche_app/physical/physical_host_settings_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    PeiLinkRuntime.configure(PeiLinkBuild.user);
    FlutterSecureStorage.setMockInitialValues({});
  });
  tearDown(() => PeiLinkRuntime.configure(PeiLinkBuild.unspecified));

  test(
    'stores Physical secrets in the user Secure Storage namespace',
    () async {
      final storage = PhysicalHostSettingsStorage();
      await storage.save(
        const PhysicalHostSettings(
          esp32Host: '192.168.2.215',
          requestKey: 'device-secret',
          volcengineApiKey: 'speech-secret',
          characterId: 'character-id',
        ),
      );
      final loaded = await storage.load();
      expect(loaded.requestKey, 'device-secret');
      expect(loaded.volcengineApiKey, 'speech-secret');
      final values = await const FlutterSecureStorage().readAll();
      expect(values.keys, everyElement(startsWith('peilink_user_physical_')));
    },
  );
}

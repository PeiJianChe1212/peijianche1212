import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/config/peilink_runtime.dart';
import 'package:peijianche_app/services/core_bridge_config_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    PeiLinkRuntime.configure(PeiLinkBuild.user);
    FlutterSecureStorage.setMockInitialValues({});
  });

  tearDown(() => PeiLinkRuntime.configure(PeiLinkBuild.unspecified));

  test('fresh Bridge configuration is disabled and has no token', () async {
    final config = await CoreBridgeConfigService().load();

    expect(config.enabled, isFalse);
    expect(config.token, isEmpty);
  });

  test('explicit enable creates an independent persistent Bridge token', () async {
    final service = CoreBridgeConfigService();
    final token = await service.enable();
    final config = await service.load();

    expect(token, hasLength(64));
    expect(config.enabled, isTrue);
    expect(config.token, token);
    expect(token, isNot(contains('api')));

    await service.disable();
    expect((await service.load()).enabled, isFalse);
  });
}

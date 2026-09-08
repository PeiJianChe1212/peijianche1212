import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final root = Directory.current;

  test('main manifest and main resources no longer carry network override', () {
    final mainManifest = File(
      '${root.path}/android/app/src/main/AndroidManifest.xml',
    );
    expect(mainManifest.existsSync(), isTrue);
    final manifestText = mainManifest.readAsStringSync();
    expect(manifestText, isNot(contains('networkSecurityConfig')));
    expect(
      File(
        '${root.path}/android/app/src/main/res/xml/network_security_config.xml',
      ).existsSync(),
      isFalse,
    );
  });

  test(
    'dev flavor keeps ESP32 cleartext whitelist and user flavor does not',
    () {
      final devXml = File(
        '${root.path}/android/app/src/dev/res/xml/network_security_config.xml',
      );
      final userXml = File(
        '${root.path}/android/app/src/user/res/xml/network_security_config.xml',
      );
      expect(devXml.existsSync(), isTrue);
      expect(userXml.existsSync(), isTrue);
      expect(devXml.readAsStringSync(), contains('192.168.2.215'));
      expect(userXml.readAsStringSync(), isNot(contains('192.168.2.215')));
      expect(
        userXml.readAsStringSync(),
        isNot(contains('cleartextTrafficPermitted="true"')),
      );
    },
  );

  test('release signing structure never falls back to debug keystore', () {
    final gradle = File('${root.path}/android/app/build.gradle.kts');
    expect(gradle.existsSync(), isTrue);
    final text = gradle.readAsStringSync();
    expect(
      text,
      isNot(contains('signingConfig = signingConfigs.getByName("debug")')),
    );
    expect(text, contains('PEILINK_KEYSTORE_FILE'));
    expect(text, contains('PEILINK_KEYSTORE_PASSWORD'));
    expect(text, contains('PEILINK_KEY_ALIAS'));
    expect(text, contains('PEILINK_KEY_PASSWORD'));
    expect(text, contains('namespace = "com.peilink.app"'));
    expect(text, contains('applicationId = "com.peilink.app"'));
  });

  test('android user manifest points at a secure user network config', () {
    final userManifest = File(
      '${root.path}/android/app/src/user/AndroidManifest.xml',
    );
    expect(userManifest.existsSync(), isTrue);
    expect(
      userManifest.readAsStringSync(),
      contains('android:networkSecurityConfig="@xml/network_security_config"'),
    );
  });
}

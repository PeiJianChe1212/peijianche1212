import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/config/peilink_runtime.dart';
import 'package:peijianche_app/pages/peilink/developer_environment_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory documents;

  setUp(() async {
    PeiLinkRuntime.configure(PeiLinkBuild.dev);
    documents = await Directory.systemTemp.createTemp('developer_dialog_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => documents.path);
  });

  tearDown(() async {
    PeiLinkRuntime.configure(PeiLinkBuild.unspecified);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    if (await documents.exists()) {
      await documents.delete(recursive: true);
    }
  });

  testWidgets('developer key dialog closes without dependency assertion', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: DeveloperEnvironmentPage(initialEnabled: false)),
    );

    await tester.pumpAndSettle();

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(find.text('进入开发者沙盒'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'invalid-test-key');
    await tester.tap(find.text('验证'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.textContaining('未获得开发者沙盒权限'), findsOneWidget);
  });
}

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/config/peilink_runtime.dart';
import 'package:peijianche_app/config/peilink_settings_sections_registry.dart';
import 'package:peijianche_app/dev_only/developer_settings_sections.dart';
import 'package:peijianche_app/pages/peilink/peilink_home_page.dart';
import 'package:peijianche_app/pages/peilink/physical_host_page.dart';
import 'package:peijianche_app/pages/settings_page.dart';
import 'package:peijianche_app/services/developer_environment_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
  late Directory documents;

  setUp(() async {
    documents = await Directory.systemTemp.createTemp(
      'physical_release_isolation_',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, (_) async => documents.path);
  });

  tearDown(() async {
    PeiLinkRuntime.configure(PeiLinkBuild.unspecified);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, null);
    await documents.delete(recursive: true);
  });

  testWidgets('dev with developer environment shows and enters Physical', (
    tester,
  ) async {
    PeiLinkRuntime.configure(PeiLinkBuild.dev);
    PeiLinkSettingsSectionsRegistry.installDeveloperSections(
      buildDeveloperSettingsSections,
    );
    await DeveloperEnvironmentService().setEnabled(
      true,
      designatedAccount: true,
    );

    await tester.pumpWidget(const MaterialApp(home: SettingsPage()));
    await tester.pumpAndSettle();

    expect(find.text('PeiLink Physical'), findsOneWidget);
    expect(find.text('Physical Core Bridge'), findsOneWidget);
    await tester.tap(find.text('PeiLink Physical'));
    await tester.pump();
    expect(find.byType(PhysicalHostPage), findsOneWidget);
  });

  testWidgets('dev with developer environment off hides Physical', (
    tester,
  ) async {
    PeiLinkRuntime.configure(PeiLinkBuild.dev);
    PeiLinkSettingsSectionsRegistry.installDeveloperSections(
      buildDeveloperSettingsSections,
    );
    await DeveloperEnvironmentService().setEnabled(false);

    await tester.pumpWidget(const MaterialApp(home: SettingsPage()));
    await tester.pumpAndSettle();

    expect(find.textContaining('Physical'), findsNothing);
    expect(find.textContaining('ESP32'), findsNothing);
  });

  testWidgets('user build hides settings, direct page, and connected status', (
    tester,
  ) async {
    PeiLinkRuntime.configure(PeiLinkBuild.user);
    await DeveloperEnvironmentService().setEnabled(false);

    await tester.pumpWidget(const MaterialApp(home: SettingsPage()));
    await tester.pumpAndSettle();
    expect(find.textContaining('Physical'), findsNothing);
    expect(find.textContaining('ESP32'), findsNothing);

    await tester.pumpWidget(const MaterialApp(home: PhysicalHostPage()));
    await tester.pumpAndSettle();
    expect(find.textContaining('Physical'), findsNothing);
    expect(find.textContaining('ESP32'), findsNothing);
    expect(find.textContaining('Phase 9'), findsNothing);

    await tester.pumpWidget(const MaterialApp(home: PeiLinkHomePage()));
    await tester.pumpAndSettle();
    expect(find.textContaining('已连接'), findsNothing);
  });
}

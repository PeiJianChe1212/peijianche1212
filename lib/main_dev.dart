import 'package:flutter/material.dart';

import 'config/peilink_runtime.dart';
import 'config/peilink_settings_sections_registry.dart';
import 'dev_only/developer_settings_sections.dart';
import 'main.dart' as app;
import 'services/core_bridge_runtime.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  PeiLinkRuntime.configure(PeiLinkBuild.dev);
  PeiLinkSettingsSectionsRegistry.installDeveloperSections(
    buildDeveloperSettingsSections,
  );
  await CoreBridgeRuntime.instance.initialize();
  await app.runPeiLink(PeiLinkBuild.dev);
}

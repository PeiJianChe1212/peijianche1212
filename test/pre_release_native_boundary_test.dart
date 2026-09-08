import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('renamed Android activity retains existing platform channels', () {
    final activity = File(
      'android/app/src/main/kotlin/com/peilink/app/MainActivity.kt',
    ).readAsStringSync();
    expect(activity, contains('package com.peilink.app'));
    for (final contract in [
      'peilink/pei_file',
      'peilink/external_url',
      '"pick" -> pickPeiFile(result)',
      '"save" -> savePeiFile',
      'Intent.ACTION_OPEN_DOCUMENT',
      'Intent.ACTION_CREATE_DOCUMENT',
      'override fun onActivityResult',
      'contentResolver.openInputStream',
      'contentResolver.openOutputStream',
    ]) {
      expect(activity, contains(contract));
    }
  });

  test('dev namespace is configured before CoreBridge reads storage', () {
    final entry = File('lib/main_dev.dart').readAsStringSync();
    final configure = entry.indexOf('PeiLinkRuntime.configure(PeiLinkBuild.dev)');
    final initialize = entry.indexOf('CoreBridgeRuntime.instance.initialize()');
    expect(configure, greaterThanOrEqualTo(0));
    expect(initialize, greaterThan(configure));
    expect(File('lib/main.dart').readAsStringSync(),
        isNot(contains('core_bridge_runtime.dart')));
  });
}

import 'dart:convert';
import 'dart:io';

import '../config/peilink_runtime.dart';
import '../models/prompt_test_mode.dart';

class PromptTestModeService {
  static const _fileName = 'prompt_test_mode.json';

  Future<File> _file() async {
    final directory = await getApplicationDocumentsDirectory();
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return File('${directory.path}/$_fileName');
  }

  Future<PromptTestMode> load() async {
    if (!PeiLinkRuntime.developerToolsEnabled) {
      return PromptTestMode.peilinkFull;
    }
    final file = await _file();
    if (!await file.exists()) {
      return PromptTestMode.peilinkFull;
    }
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map) {
        return PromptTestMode.fromName(decoded['mode']?.toString());
      }
    } catch (_) {}
    return PromptTestMode.peilinkFull;
  }

  Future<void> save(PromptTestMode mode) async {
    if (!PeiLinkRuntime.developerToolsEnabled) {
      throw StateError('Prompt 测试模式仅在开发者版可用。');
    }
    final file = await _file();
    await file.writeAsString(jsonEncode({'mode': mode.name}), flush: true);
  }
}

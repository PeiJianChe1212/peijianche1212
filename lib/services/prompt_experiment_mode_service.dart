import 'dart:convert';
import 'dart:io';

import '../config/peilink_runtime.dart';
import '../models/prompt_experiment_mode.dart';

class PromptExperimentModeService {
  static const fileName = 'prompt_experiment_mode.json';

  Future<File> _file() async {
    final directory = await getApplicationDocumentsDirectory();
    if (!await directory.exists()) await directory.create(recursive: true);
    return File('${directory.path}/$fileName');
  }

  Future<PromptExperimentMode?> load() async {
    if (!PeiLinkRuntime.developerToolsEnabled) return null;
    final file = await _file();
    if (!await file.exists()) return null;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map) {
        return PromptExperimentModeDetails.fromName(
          decoded['experiment']?.toString(),
        );
      }
    } catch (_) {}
    return null;
  }

  Future<void> save(PromptExperimentMode mode) async {
    if (!PeiLinkRuntime.developerToolsEnabled) {
      throw StateError('模块级 Prompt 实验仅在开发者版可用。');
    }
    await (await _file()).writeAsString(
      jsonEncode({'experiment': mode.name}),
      flush: true,
    );
  }

  Future<void> clear() async {
    if (!PeiLinkRuntime.developerToolsEnabled) return;
    final file = await _file();
    if (await file.exists()) await file.delete();
  }
}

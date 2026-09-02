import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../models/prompt_test_mode.dart';
import '../models/prompt_experiment_mode.dart';
import '../models/api_settings.dart';
import '../config/peilink_runtime.dart';

class PromptTestSnapshot {
  const PromptTestSnapshot({
    required this.mode,
    required this.messages,
    required this.createdAt,
    this.experiment,
    this.provider,
    this.enabledModules = const [],
    this.disabledModules = const [],
    this.styleValues = const {},
    this.internalDependencies = const [],
    this.architecture = '',
    this.providerAdapter = '',
  });

  final PromptTestMode mode;
  final List<Map<String, dynamic>> messages;
  final DateTime createdAt;
  final PromptExperimentMode? experiment;
  final AIProvider? provider;
  final List<String> enabledModules;
  final List<String> disabledModules;
  final Map<String, String> styleValues;
  final List<String> internalDependencies;
  final String architecture;
  final String providerAdapter;

  int get systemCharacters => messages
      .where((message) => message['role'] == 'system')
      .map((message) => message['content']?.toString().length ?? 0)
      .fold(0, (sum, length) => sum + length);

  String get systemSha256 {
    final system = messages
        .where((message) => message['role'] == 'system')
        .map((message) => message['content']?.toString() ?? '')
        .join('\n');
    return sha256.convert(utf8.encode(system)).toString();
  }

  /// Dev-only source tracing without returning matching Prompt or message text.
  /// The snapshot is in-memory and never participates in a model request.
  List<String> sourceLabelsForTerm(String term) {
    final needle = term.trim();
    if (needle.isEmpty) return const [];
    final labels = <String>{};
    for (var index = 0; index < messages.length; index++) {
      final message = messages[index];
      final role = message['role']?.toString() ?? 'unknown';
      final content = message['content']?.toString() ?? '';
      if (!content.contains(needle)) continue;
      if (role != 'system') {
        labels.add('Recent chat: $role');
        continue;
      }
      final headings = RegExp(r'【([^】\n]{1,80})】').allMatches(content).toList();
      var foundSection = false;
      for (
        var headingIndex = 0;
        headingIndex < headings.length;
        headingIndex++
      ) {
        final heading = headings[headingIndex];
        final end = headingIndex + 1 < headings.length
            ? headings[headingIndex + 1].start
            : content.length;
        if (content.substring(heading.start, end).contains(needle)) {
          labels.add('System section: ${heading.group(1)}');
          foundSection = true;
        }
      }
      if (!foundSection) labels.add('System section: unlabelled');
    }
    return labels.toList(growable: false);
  }

  String get displayText {
    final buffer = StringBuffer();
    buffer.writeln(
      'Prompt Architecture: ${architecture.isEmpty ? '未记录' : architecture}',
    );
    buffer.writeln('Provider: ${provider?.label ?? '未记录'}');
    buffer.writeln(
      'Provider Adapter: ${providerAdapter.isEmpty ? 'Disabled' : providerAdapter}',
    );
    buffer.writeln('Base mode: ${mode.label}');
    buffer.writeln('Experiment: ${experiment?.description ?? '未启用'}');
    buffer.writeln(
      'Enabled: ${enabledModules.isEmpty ? '—' : enabledModules.join(', ')}',
    );
    buffer.writeln(
      'Disabled: ${disabledModules.isEmpty ? '—' : disabledModules.join(', ')}',
    );
    buffer.writeln('System characters: $systemCharacters');
    buffer.writeln('System SHA-256: $systemSha256');
    if (internalDependencies.isNotEmpty) {
      buffer.writeln('Internal only: ${internalDependencies.join(', ')}');
    }
    if (styleValues.isNotEmpty) {
      buffer.writeln('Resolved Personality Style:');
      for (final entry in styleValues.entries) {
        buffer.writeln('  ${entry.key}=${entry.value}');
      }
    }
    buffer.writeln('\n${List.filled(28, '═').join()}\n');
    for (var index = 0; index < messages.length; index++) {
      final message = messages[index];
      final role = message['role']?.toString() ?? 'unknown';
      final content = message['content']?.toString() ?? '';
      if (index > 0) {
        buffer.writeln('\n${List.filled(28, '─').join()}\n');
      }
      buffer.writeln('[${index + 1}] $role');
      buffer.write(content);
    }
    return buffer.toString().trim();
  }
}

class PromptTestSnapshotService {
  PromptTestSnapshotService._();

  static PromptTestSnapshot? _latest;

  static PromptTestSnapshot? get latest =>
      PeiLinkRuntime.developerToolsEnabled ? _latest : null;

  static void capture({
    required PromptTestMode mode,
    required List<Map<String, dynamic>> messages,
    PromptExperimentMode? experiment,
    AIProvider? provider,
    List<String> enabledModules = const [],
    List<String> disabledModules = const [],
    Map<String, String> styleValues = const {},
    List<String> internalDependencies = const [],
    String architecture = '',
    String providerAdapter = '',
  }) {
    if (!PeiLinkRuntime.developerToolsEnabled) {
      _latest = null;
      return;
    }
    _latest = PromptTestSnapshot(
      mode: mode,
      messages: messages
          .map((message) => Map<String, dynamic>.from(message))
          .toList(growable: false),
      createdAt: DateTime.now(),
      experiment: experiment,
      provider: provider,
      enabledModules: List.unmodifiable(enabledModules),
      disabledModules: List.unmodifiable(disabledModules),
      styleValues: Map.unmodifiable(styleValues),
      internalDependencies: List.unmodifiable(internalDependencies),
      architecture: architecture,
      providerAdapter: providerAdapter,
    );
  }
}

import 'package:flutter/material.dart';

import '../config/peilink_runtime.dart';
import '../physical/physical_speech_contract.dart';

/// Only mounted inside the developer-environment-gated Physical page.
class PhysicalSpeechDiagnosticsCard extends StatelessWidget {
  const PhysicalSpeechDiagnosticsCard({
    super.key,
    required this.diagnostics,
    required this.displayReply,
    required this.spokenReply,
    required this.ttsInputExact,
  });

  final PhysicalContractDiagnostics diagnostics;
  final String displayReply;
  final String spokenReply;
  final String? ttsInputExact;

  static String _preview(String? text) {
    if (text == null) return '(not captured)';
    final escaped = text
        .replaceAll('\\', '\\\\')
        .replaceAll('\r', r'\r')
        .replaceAll('\n', r'\n')
        .replaceAll('\t', r'\t');
    final characters = escaped.runes.toList();
    return characters.length <= 400
        ? escaped
        : '${String.fromCharCodes(characters.take(400))}…';
  }

  @override
  Widget build(BuildContext context) {
    if (!PeiLinkRuntime.developerToolsEnabled) return const SizedBox.shrink();
    final d = diagnostics;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Speech Contract Diagnostics'),
        Text('Contract parsed: ${d.contractParsed}'),
        Text(
          'Marker counts: D-start=${d.displayStartCount} / '
          'D-end=${d.displayEndCount} / S-start=${d.spokenStartCount} / '
          'S-end=${d.spokenEndCount}',
        ),
        Text('Marker order: ${d.markerOrderValid ? 'valid' : 'invalid'}'),
        Text('Display length: ${d.displayBlockLength ?? 'unavailable'}'),
        Text('Spoken length: ${d.spokenBlockLength ?? 'unavailable'}'),
        const Text(
          'Lengths: trimmed contract blocks (UTF-16); unavailable = no unique pair',
        ),
        Text('Failure category: ${d.failure.label}'),
        Text('Fallback source: ${d.fallbackSource.name}'),
        Text(
          'Fallback reason: ${d.fallbackReason.isEmpty ? '(none)' : d.fallbackReason}',
        ),
        Text('DISPLAY preview: ${_preview(displayReply)}'),
        Text('SPOKEN preview: ${_preview(spokenReply)}'),
        Text('TTS INPUT preview: ${_preview(ttsInputExact)}'),
        Text(
          'TTS INPUT == SPOKEN: ${ttsInputExact == null ? 'not captured' : ttsInputExact == spokenReply}',
        ),
      ],
    );
  }
}

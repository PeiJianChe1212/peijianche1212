import 'physical_speech_text_adapter.dart';

/// Physical-only plain-text dual-output contract.
///
/// It is provider-agnostic: the model is asked to return two clearly delimited
/// plain-text sections. No JSON mode, response_format, function calling or
/// provider-specific structured output is used.
abstract final class PhysicalSpeechContract {
  static const displayStart = '<PEILINK_DISPLAY>';
  static const displayEnd = '</PEILINK_DISPLAY>';
  static const spokenStart = '<PEILINK_SPOKEN>';
  static const spokenEnd = '</PEILINK_SPOKEN>';

  static String get instruction =>
      '''
本次回复必须使用以下纯文本双区块格式，禁止 JSON、代码块或任何解释：

$displayStart
完整角色回复。保持角色原本的聊天风格；可以包含动作、神态、场景、语气和旁白。
$displayEnd
$spokenStart
只写角色真正说出口、应该由实体设备朗读的内容。禁止包含轻笑、抬手、停顿、
声音放轻、尾音上扬、靠进椅背等动作或语气舞台说明；不要解释正在过滤文本。
如果 DISPLAY 本来就是纯直接对白，SPOKEN 可以与 DISPLAY 相同。
$spokenEnd
''';
}

enum PhysicalContractFailure {
  none,
  markerCount,
  markerOrder,
  emptyDisplay,
  emptySpoken;

  String get label => switch (this) {
    none => 'none',
    markerCount => 'marker_count',
    markerOrder => 'marker_order',
    emptyDisplay => 'empty_display',
    emptySpoken => 'empty_spoken',
  };
}

enum PhysicalFallbackSource { none, displayCandidate, raw }

/// In-memory structure only: no provider body, credentials or logging.
class PhysicalContractDiagnostics {
  const PhysicalContractDiagnostics({
    required this.contractParsed,
    required this.displayStartCount,
    required this.displayEndCount,
    required this.spokenStartCount,
    required this.spokenEndCount,
    required this.markerOrderValid,
    required this.displayBlockLength,
    required this.spokenBlockLength,
    required this.failure,
    required this.fallbackSource,
    required this.fallbackReason,
  });

  final bool contractParsed;
  final int displayStartCount;
  final int displayEndCount;
  final int spokenStartCount;
  final int spokenEndCount;
  final bool markerOrderValid;
  // Trimmed UTF-16 length; null when a unique ordered pair is unavailable.
  final int? displayBlockLength;
  final int? spokenBlockLength;
  final PhysicalContractFailure failure;
  final PhysicalFallbackSource fallbackSource;
  final String fallbackReason;
}

class PhysicalSpeechReply {
  const PhysicalSpeechReply({
    required this.rawReply,
    required this.displayReply,
    required this.spokenReply,
    required this.contractParsed,
    required this.fallbackReason,
    required this.diagnostics,
  });

  /// The full model-returned text (including markers when present). Kept for
  /// diagnostics; never shown in normal chat or persisted to formal history.
  final String rawReply;

  /// The complete character reply meant for UI/session/context.
  final String displayReply;

  /// The actual content that should be read aloud by TTS.
  final String spokenReply;
  final bool contractParsed;
  final String fallbackReason;
  final PhysicalContractDiagnostics diagnostics;
}

abstract final class PhysicalSpeechContractParser {
  /// Strict parse. Returns null on any missing/duplicate/misordered marker.
  static PhysicalSpeechReply? tryParse(String raw) {
    final displayStartCount = _count(raw, PhysicalSpeechContract.displayStart);
    final displayEndCount = _count(raw, PhysicalSpeechContract.displayEnd);
    final spokenStartCount = _count(raw, PhysicalSpeechContract.spokenStart);
    final spokenEndCount = _count(raw, PhysicalSpeechContract.spokenEnd);
    if (displayStartCount != 1 ||
        displayEndCount != 1 ||
        spokenStartCount != 1 ||
        spokenEndCount != 1) {
      return null;
    }

    final displayStart = raw.indexOf(PhysicalSpeechContract.displayStart);
    final displayEnd = raw.indexOf(PhysicalSpeechContract.displayEnd);
    final spokenStart = raw.indexOf(PhysicalSpeechContract.spokenStart);
    final spokenEnd = raw.indexOf(PhysicalSpeechContract.spokenEnd);
    if (displayStart < 0 ||
        displayEnd <= displayStart ||
        spokenStart <= displayEnd ||
        spokenEnd <= spokenStart) {
      return null;
    }

    final display = raw
        .substring(
          displayStart + PhysicalSpeechContract.displayStart.length,
          displayEnd,
        )
        .trim();
    final spoken = raw
        .substring(
          spokenStart + PhysicalSpeechContract.spokenStart.length,
          spokenEnd,
        )
        .trim();
    if (display.isEmpty || spoken.isEmpty) return null;

    return PhysicalSpeechReply(
      rawReply: raw,
      displayReply: display,
      spokenReply: spoken,
      contractParsed: true,
      fallbackReason: '',
      diagnostics: _diagnose(raw, true, PhysicalFallbackSource.none, ''),
    );
  }

  /// Parses the dual-output reply when possible and otherwise falls back to
  /// speech-safe extraction. Full text is retained for DISPLAY, never restored
  /// into speech when extraction fails or produces an empty result.
  static PhysicalSpeechReply resolve(String raw) {
    final parsed = tryParse(raw);
    if (parsed != null) return parsed;

    final displayCandidate = _extractDisplayIfPossible(raw);
    final fallbackSource = displayCandidate.isEmpty ? raw : displayCandidate;
    String spoken;
    String fallbackReason;
    try {
      final adapted = PhysicalSpeechTextAdapter.speechSafeFallback(
        fallbackSource,
      );
      spoken = adapted.text;
      fallbackReason = 'contract_parse_failed;${adapted.note}';
    } catch (_) {
      spoken = '';
      fallbackReason =
          'contract_parse_failed;speech_safe_fallback;extraction_error;empty_safe_result';
    }
    return PhysicalSpeechReply(
      rawReply: raw,
      displayReply: displayCandidate.isEmpty ? raw.trim() : displayCandidate,
      spokenReply: spoken,
      contractParsed: false,
      fallbackReason: fallbackReason,
      diagnostics: _diagnose(
        raw,
        false,
        displayCandidate.isEmpty
            ? PhysicalFallbackSource.raw
            : PhysicalFallbackSource.displayCandidate,
        fallbackReason,
      ),
    );
  }

  // Observation only. Do not use these values to select parser/fallback paths.
  static PhysicalContractDiagnostics _diagnose(
    String raw,
    bool parsed,
    PhysicalFallbackSource source,
    String reason,
  ) {
    const markers = [
      PhysicalSpeechContract.displayStart,
      PhysicalSpeechContract.displayEnd,
      PhysicalSpeechContract.spokenStart,
      PhysicalSpeechContract.spokenEnd,
    ];
    final counts = markers.map((marker) => _count(raw, marker)).toList();
    final positions = markers.map(raw.indexOf).toList();
    final unique = counts.every((count) => count == 1);
    final ordered =
        unique &&
        positions[0] < positions[1] &&
        positions[1] < positions[2] &&
        positions[2] < positions[3];
    int? blockLength(int start, int end) {
      if (counts[start] != 1 ||
          counts[end] != 1 ||
          positions[end] <= positions[start]) {
        return null;
      }
      return raw
          .substring(positions[start] + markers[start].length, positions[end])
          .trim()
          .length;
    }

    final displayLength = blockLength(0, 1);
    final spokenLength = blockLength(2, 3);
    final failure = !unique
        ? PhysicalContractFailure.markerCount
        : !ordered
        ? PhysicalContractFailure.markerOrder
        : displayLength == 0
        ? PhysicalContractFailure.emptyDisplay
        : spokenLength == 0
        ? PhysicalContractFailure.emptySpoken
        : PhysicalContractFailure.none;
    return PhysicalContractDiagnostics(
      contractParsed: parsed,
      displayStartCount: counts[0],
      displayEndCount: counts[1],
      spokenStartCount: counts[2],
      spokenEndCount: counts[3],
      markerOrderValid: ordered,
      displayBlockLength: displayLength,
      spokenBlockLength: spokenLength,
      failure: failure,
      fallbackSource: source,
      fallbackReason: reason,
    );
  }

  static String _extractDisplayIfPossible(String raw) {
    final startCount = _count(raw, PhysicalSpeechContract.displayStart);
    final endCount = _count(raw, PhysicalSpeechContract.displayEnd);
    if (startCount != 1 || endCount != 1) return '';
    final start = raw.indexOf(PhysicalSpeechContract.displayStart);
    final end = raw.indexOf(PhysicalSpeechContract.displayEnd);
    if (start < 0 || end <= start) return '';
    return raw
        .substring(start + PhysicalSpeechContract.displayStart.length, end)
        .trim();
  }

  static int _count(String value, String marker) {
    var count = 0;
    var index = 0;
    while (true) {
      final found = value.indexOf(marker, index);
      if (found < 0) break;
      count++;
      index = found + marker.length;
    }
    return count;
  }
}

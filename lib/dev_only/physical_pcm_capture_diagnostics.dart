import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../physical/esp32_physical_client.dart';
import '../physical/pcm_audio_codec.dart';
import '../physical/pcm_audio_gain.dart';

class PhysicalPcmCaptureDiagnostics {
  const PhysicalPcmCaptureDiagnostics({
    required this.captureId,
    required this.rawWavPath,
    required this.gainWavPath,
    required this.pcmBytes,
    required this.durationMs,
    required this.appliedGain,
  });

  final int captureId;
  final String rawWavPath;
  final String gainWavPath;
  final int pcmBytes;
  final int durationMs;
  final double appliedGain;
}

abstract final class PhysicalPcmCaptureDiagnosticWriter {
  static Future<PhysicalPcmCaptureDiagnostics> save(
    PhysicalCapture capture, {
    Directory? directory,
  }) async {
    final root =
        directory ??
        Directory(
          '${(await getTemporaryDirectory()).path}'
          '${Platform.pathSeparator}peilink_physical_diagnostics',
        );
    await root.create(recursive: true);

    final captureId = capture.recordingId;
    if (captureId == null) {
      throw StateError('录音响应缺少 capture_id，未保存诊断 WAV');
    }

    final gain = PcmAudioGain.applyAdaptiveGain(capture.pcm);
    final rawFile = File(
      '${root.path}${Platform.pathSeparator}'
      'start_clipping_capture_${captureId}_raw.wav',
    );
    final gainFile = File(
      '${root.path}${Platform.pathSeparator}'
      'start_clipping_capture_${captureId}_gain.wav',
    );
    await rawFile.writeAsBytes(
      PcmAudioCodec.wavFromPcm(capture.pcm),
      flush: true,
    );
    await gainFile.writeAsBytes(
      PcmAudioCodec.wavFromPcm(gain.output),
      flush: true,
    );

    return PhysicalPcmCaptureDiagnostics(
      captureId: captureId,
      rawWavPath: rawFile.path,
      gainWavPath: gainFile.path,
      pcmBytes: capture.pcm.length,
      durationMs: capture.pcm.length * 1000 ~/ (PcmAudioCodec.sampleRate * 2),
      appliedGain: gain.appliedGain,
    );
  }
}

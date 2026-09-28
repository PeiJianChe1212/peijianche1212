import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/dev_only/physical_pcm_capture_diagnostics.dart';
import 'package:peijianche_app/physical/esp32_physical_client.dart';
import 'package:peijianche_app/physical/pcm_audio_codec.dart';

void main() {
  test(
    'writes exact raw and adaptive-gain PCM as temporary WAV files',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'peilink-start-clipping-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final pcm = Uint8List(3200);
      final data = ByteData.sublistView(pcm);
      for (var offset = 0; offset < pcm.length; offset += 2) {
        data.setInt16(offset, offset.isEven ? 100 : -100, Endian.little);
      }
      final capture = PhysicalCapture(
        pcm: pcm,
        stats: PcmAudioCodec.stats(pcm),
        crc32: PcmAudioCodec.crc32(pcm),
        captureMode: 'vad',
        vadState: 'complete',
        recordingId: 42,
      );

      final result = await PhysicalPcmCaptureDiagnosticWriter.save(
        capture,
        directory: directory,
      );
      final raw = await File(result.rawWavPath).readAsBytes();
      final gain = await File(result.gainWavPath).readAsBytes();

      expect(raw.length, pcm.length + 44);
      expect(raw.sublist(44), pcm);
      expect(gain.length, pcm.length + 44);
      expect(result.pcmBytes, pcm.length);
      expect(result.durationMs, 100);
      expect(result.appliedGain, 5.0);
      expect(result.captureId, 42);
      expect(result.rawWavPath, endsWith('start_clipping_capture_42_raw.wav'));
      expect(
        result.gainWavPath,
        endsWith('start_clipping_capture_42_gain.wav'),
      );
    },
  );

  test('keeps WAV files from consecutive capture IDs independently', () async {
    final directory = await Directory.systemTemp.createTemp(
      'peilink-start-clipping-ids-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final pcm = Uint8List.fromList([100, 0, 156, 255]);

    Future<PhysicalPcmCaptureDiagnostics> save(int captureId) =>
        PhysicalPcmCaptureDiagnosticWriter.save(
          PhysicalCapture(
            pcm: pcm,
            stats: PcmAudioCodec.stats(pcm),
            crc32: PcmAudioCodec.crc32(pcm),
            captureMode: 'vad',
            vadState: 'complete',
            recordingId: captureId,
          ),
          directory: directory,
        );

    final first = await save(2);
    final second = await save(3);

    expect(first.rawWavPath, isNot(second.rawWavPath));
    expect(first.gainWavPath, isNot(second.gainWavPath));
    expect(await File(first.rawWavPath).exists(), isTrue);
    expect(await File(first.gainWavPath).exists(), isTrue);
    expect(await File(second.rawWavPath).exists(), isTrue);
    expect(await File(second.gainWavPath).exists(), isTrue);
  });
}

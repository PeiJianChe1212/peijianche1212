import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/physical/pcm_audio_codec.dart';

void main() {
  test('CRC32 matches the standard vector', () {
    expect(
      PcmAudioCodec.crc32(Uint8List.fromList('123456789'.codeUnits)),
      0xcbf43926,
    );
  });

  test('wraps Phase 9 PCM in a canonical mono WAV header', () {
    final pcm = Uint8List(PcmAudioCodec.recordBytes);
    final wav = PcmAudioCodec.wavFromPcm(pcm);
    final data = ByteData.sublistView(wav);
    expect(String.fromCharCodes(wav.take(4)), 'RIFF');
    expect(String.fromCharCodes(wav.skip(8).take(4)), 'WAVE');
    expect(data.getUint32(24, Endian.little), 16000);
    expect(data.getUint16(22, Endian.little), 1);
    expect(data.getUint16(34, Endian.little), 16);
    expect(String.fromCharCodes(wav.skip(36).take(4)), 'data');
    expect(data.getUint32(4, Endian.little), 36 + PcmAudioCodec.recordBytes);
    expect(data.getUint32(40, Endian.little), PcmAudioCodec.recordBytes);
    expect(wav.length, PcmAudioCodec.recordBytes + 44);
  });

  test('wraps a legal Phase 11 max_duration capture longer than 8 s', () {
    final pcm = Uint8List(PcmAudioCodec.recordBytes + 16000); // 8.5 s
    final wav = PcmAudioCodec.wavFromPcm(pcm);
    final data = ByteData.sublistView(wav);
    expect(data.getUint32(4, Endian.little), 36 + pcm.length);
    expect(data.getUint32(40, Endian.little), pcm.length);
    expect(data.getUint32(24, Endian.little), 16000);
    expect(wav.length, pcm.length + 44);
  });

  test('wraps the longest legal Phase 11 dynamic capture', () {
    final pcm = Uint8List(PcmAudioCodec.phase11MaxCaptureBytes);
    final wav = PcmAudioCodec.wavFromPcm(pcm);
    final data = ByteData.sublistView(wav);
    expect(PcmAudioCodec.phase11HistoryMs, 2000);
    expect(PcmAudioCodec.phase11MaxDurationMs, 8000);
    expect(PcmAudioCodec.phase11MaxCaptureMs, 9500);
    expect(PcmAudioCodec.phase11MaxCaptureSamples, 152000);
    expect(PcmAudioCodec.phase11MaxCaptureBytes, 304000);
    expect(String.fromCharCodes(wav.take(4)), 'RIFF');
    expect(String.fromCharCodes(wav.skip(36).take(4)), 'data');
    expect(data.getUint32(4, Endian.little), 36 + pcm.length);
    expect(data.getUint32(40, Endian.little), pcm.length);
    expect(wav.length, PcmAudioCodec.phase11MaxCaptureBytes + 44);
  });

  test('rejects PCM past the Phase 11 dynamic capture contract', () {
    expect(
      () => PcmAudioCodec.wavFromPcm(
        Uint8List(PcmAudioCodec.phase11MaxCaptureBytes + 2),
      ),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => PcmAudioCodec.wavFromPcm(
        Uint8List(PcmAudioCodec.phase11MaxCaptureBytes + 320),
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('keeps the playback bound separate from the capture contract', () {
    expect(
      () => PcmAudioCodec.validatePcm(
        Uint8List(PcmAudioCodec.maxPlaybackBytes + 2),
      ),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => PcmAudioCodec.validatePcm(
        Uint8List(PcmAudioCodec.phase11MaxCaptureBytes),
      ),
      returnsNormally,
    );
    expect(PcmAudioCodec.recordBytes, lessThan(PcmAudioCodec.phase11MaxCaptureBytes));
  });

  test('band-limited conversion maps 24 kHz to 16 kHz', () {
    final pcm = Uint8List(2400 * 2);
    final data = ByteData.sublistView(pcm);
    for (var i = 0; i < 2400; i++) {
      data.setInt16(
        i * 2,
        (10000 * math.sin(2 * math.pi * 1000 * i / 24000)).round(),
        Endian.little,
      );
    }
    final converted = PcmAudioCodec.resample24kTo16k(pcm);
    expect(converted.length, 3200);
    expect(PcmAudioCodec.stats(converted).peak, greaterThan(8000));
  });
}

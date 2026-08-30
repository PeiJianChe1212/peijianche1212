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
    expect(wav.length, PcmAudioCodec.recordBytes + 44);
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

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:peijianche_app/physical/esp32_physical_client.dart';
import 'package:peijianche_app/physical/pcm_audio_codec.dart';

void main() {
  test('rejects public destinations before sending a request', () async {
    var called = false;
    final client = Esp32PhysicalClient(
      client: MockClient((_) async {
        called = true;
        return http.Response('{}', 200);
      }),
    );
    await expectLater(
      client.status(host: 'example.com', key: 'secret'),
      throwsA(isA<FormatException>()),
    );
    expect(called, isFalse);
  });

  test('accepts only a healthy idle Phase 9 status', () async {
    final client = Esp32PhysicalClient(
      client: MockClient((request) async {
        expect(request.url.toString(), 'http://192.168.2.215:8080/status');
        expect(request.headers['X-PeiLink-Key'], 'secret');
        return http.Response(
          jsonEncode({
            'ok': true,
            'phase': 9,
            'state': 'idle',
            'sample_rate': 16000,
            'bits': 16,
            'channels': 1,
            'record_seconds': 8,
            'max_playback_bytes': 1048576,
            'rx_errors': 0,
            'tx_errors': 0,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    expect(
      (await client.status(host: '192.168.2.215', key: 'secret')).phase,
      9,
    );
  });

  test('never follows a device redirect', () async {
    var calls = 0;
    final client = Esp32PhysicalClient(
      client: MockClient((request) async {
        calls++;
        expect(request.followRedirects, isFalse);
        return http.Response(
          '',
          302,
          headers: {'location': 'http://192.168.2.99:8080/status'},
        );
      }),
    );
    await expectLater(
      client.status(host: '192.168.2.215', key: 'secret'),
      throwsA(isA<PhysicalProtocolException>()),
    );
    expect(calls, 1);
  });

  test('accepts healthy Phase 11 VAD status with fixed fallback', () async {
    final client = Esp32PhysicalClient(
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'ok': true,
            'phase': 11,
            'state': 'idle',
            'sample_rate': 16000,
            'bits': 16,
            'channels': 1,
            'record_seconds': 8,
            'capture_mode': 'vad',
            'fixed_fallback': true,
            'max_playback_bytes': 1048576,
            'rx_errors': 0,
            'tx_errors': 0,
          }),
          200,
          headers: {'content-type': 'application/json'},
        ),
      ),
    );
    final status = await client.status(host: '192.168.2.215', key: 'secret');
    expect(status.phase, 11);
    expect(status.captureMode, 'vad');
    expect(status.fixedFallback, isTrue);
  });

  for (final vadState in const ['complete', 'max_duration']) {
    test('accepts dynamic $vadState PCM from Phase 11', () async {
      final pcm = _pcm(48000, 900);
      final client = Esp32PhysicalClient(
        client: MockClient(
          (_) async =>
              _recordResponse(pcm, captureMode: 'vad', vadState: vadState),
        ),
      );
      final capture = await client.record(host: '192.168.2.215', key: 'secret');
      expect(capture.pcm, pcm);
      expect(capture.captureMode, 'vad');
      expect(capture.vadState, vadState);
      expect(capture.recordingId, 17);
    });
  }

  test('maps Phase 11 no_speech to a non-ASR capture result', () async {
    final client = Esp32PhysicalClient(
      client: MockClient(
        (_) async => http.Response(
          '',
          204,
          headers: {'x-capture-mode': 'vad', 'x-vad-state': 'no_speech'},
        ),
      ),
    );
    await expectLater(
      client.record(host: '192.168.2.215', key: 'secret'),
      throwsA(isA<PhysicalNoSpeechException>()),
    );
  });

  test('accepts explicit fixed 8s fallback after VAD error', () async {
    final pcm = _pcm(PcmAudioCodec.recordBytes, 900);
    final client = Esp32PhysicalClient(
      client: MockClient(
        (_) async => _recordResponse(
          pcm,
          captureMode: 'fixed_fallback',
          vadState: 'error',
        ),
      ),
    );
    final capture = await client.record(host: '192.168.2.215', key: 'secret');
    expect(capture.pcm.length, PcmAudioCodec.recordBytes);
    expect(capture.captureMode, 'fixed_fallback');
    expect(capture.vadState, 'error');
  });

  test('keeps accepting the legacy Phase 9 fixed 8s response', () async {
    final pcm = _pcm(PcmAudioCodec.recordBytes, 900);
    final stats = PcmAudioCodec.stats(pcm);
    final client = Esp32PhysicalClient(
      client: MockClient(
        (_) async => http.Response.bytes(
          pcm,
          200,
          headers: {
            'content-type': 'application/octet-stream',
            'content-length': '${pcm.length}',
            'x-audio-sample-rate': '16000',
            'x-audio-bits': '16',
            'x-audio-channels': '1',
            'x-audio-peak': '${stats.peak}',
            'x-audio-crc32': PcmAudioCodec.crc32(
              pcm,
            ).toRadixString(16).padLeft(8, '0'),
          },
        ),
      ),
    );
    final capture = await client.record(host: '192.168.2.215', key: 'secret');
    expect(capture.captureMode, 'fixed');
    expect(capture.vadState, isNull);
    expect(capture.pcm.length, PcmAudioCodec.recordBytes);
  });

  group('Phase 11 dynamic PCM length contract', () {
    test('pins the derived contract from the frozen firmware semantics', () {
      // 2000 ms history + (8000 ms - 500 ms already consumed) speaking.
      expect(PcmAudioCodec.phase11HistoryMs, 2000);
      expect(PcmAudioCodec.phase11MaxDurationMs, 8000);
      expect(PcmAudioCodec.phase11MaxCaptureMs, 9500);
      expect(PcmAudioCodec.phase11MaxCaptureSamples, 152000);
      expect(PcmAudioCodec.phase11MaxCaptureBytes, 304000);
      // The legacy fixed capture stays exactly 8 s.
      expect(PcmAudioCodec.recordSeconds, 8);
      expect(PcmAudioCodec.recordBytes, 256000);
    });

    test('accepts a max_duration capture at the legacy 8 s length', () async {
      final pcm = _pcm(PcmAudioCodec.recordBytes, 900);
      final client = Esp32PhysicalClient(
        client: MockClient(
          (_) async => _recordResponse(
            pcm,
            captureMode: 'vad',
            vadState: 'max_duration',
          ),
        ),
      );
      final capture = await client.record(host: '192.168.2.215', key: 'secret');
      expect(capture.pcm.length, PcmAudioCodec.recordBytes);
      expect(capture.vadState, 'max_duration');
    });

    test('accepts dynamic PCM longer than the legacy 8 s capture', () async {
      final pcm = _pcm(PcmAudioCodec.recordBytes + 16000, 900); // 8.5 s
      final client = Esp32PhysicalClient(
        client: MockClient(
          (_) async =>
              _recordResponse(pcm, captureMode: 'vad', vadState: 'max_duration'),
        ),
      );
      final capture = await client.record(host: '192.168.2.215', key: 'secret');
      expect(capture.pcm.length, PcmAudioCodec.recordBytes + 16000);
      expect(capture.vadState, 'max_duration');
    });

    test('accepts the longest legal dynamic capture', () async {
      final pcm = _pcm(PcmAudioCodec.phase11MaxCaptureBytes, 900);
      final client = Esp32PhysicalClient(
        client: MockClient(
          (_) async =>
              _recordResponse(pcm, captureMode: 'vad', vadState: 'max_duration'),
        ),
      );
      final capture = await client.record(host: '192.168.2.215', key: 'secret');
      expect(capture.pcm.length, PcmAudioCodec.phase11MaxCaptureBytes);
      expect(capture.pcm.length, 304000);
      expect(capture.vadState, 'max_duration');
    });

    test('rejects dynamic PCM one sample past the contract', () async {
      final pcm = _pcm(PcmAudioCodec.phase11MaxCaptureBytes + 2, 900);
      final client = Esp32PhysicalClient(
        client: MockClient(
          (_) async =>
              _recordResponse(pcm, captureMode: 'vad', vadState: 'max_duration'),
        ),
      );
      await expectLater(
        client.record(host: '192.168.2.215', key: 'secret'),
        throwsA(isA<PhysicalInvalidRecordingException>()),
      );
    });

    test('rejects dynamic PCM one block past the contract', () async {
      final pcm = _pcm(PcmAudioCodec.phase11MaxCaptureBytes + 320, 900);
      final client = Esp32PhysicalClient(
        client: MockClient(
          (_) async =>
              _recordResponse(pcm, captureMode: 'vad', vadState: 'complete'),
        ),
      );
      await expectLater(
        client.record(host: '192.168.2.215', key: 'secret'),
        throwsA(isA<PhysicalInvalidRecordingException>()),
      );
    });

    test('rejects dynamic PCM whose CRC does not match', () async {
      final pcm = _pcm(PcmAudioCodec.phase11MaxCaptureBytes, 900);
      final client = Esp32PhysicalClient(
        client: MockClient(
          (_) async => _recordResponse(
            pcm,
            captureMode: 'vad',
            vadState: 'max_duration',
            crcOverride: PcmAudioCodec.crc32(pcm) ^ 0x1,
          ),
        ),
      );
      await expectLater(
        client.record(host: '192.168.2.215', key: 'secret'),
        throwsA(isA<PhysicalInvalidRecordingException>()),
      );
    });

    test('rejects dynamic PCM whose length header does not match', () async {
      final pcm = _pcm(PcmAudioCodec.phase11MaxCaptureBytes, 900);
      final client = Esp32PhysicalClient(
        client: MockClient(
          (_) async => _recordResponse(
            pcm,
            captureMode: 'vad',
            vadState: 'max_duration',
            contentLengthOverride: pcm.length - 2,
          ),
        ),
      );
      await expectLater(
        client.record(host: '192.168.2.215', key: 'secret'),
        throwsA(isA<PhysicalInvalidRecordingException>()),
      );
    });

    test('rejects an odd-length dynamic capture', () async {
      final pcm = _oddPcm(PcmAudioCodec.recordBytes + 1);
      final client = Esp32PhysicalClient(
        client: MockClient(
          (_) async => http.Response.bytes(
            pcm,
            200,
            headers: {
              'content-type': 'application/octet-stream',
              'content-length': '${pcm.length}',
              'x-audio-sample-rate': '16000',
              'x-audio-bits': '16',
              'x-audio-channels': '1',
              'x-audio-peak': '900',
              'x-audio-crc32': PcmAudioCodec.crc32(
                pcm,
              ).toRadixString(16).padLeft(8, '0'),
              'x-capture-mode': 'vad',
              'x-vad-state': 'complete',
              'x-audio-recording-id': '17',
            },
          ),
        ),
      );
      await expectLater(
        client.record(host: '192.168.2.215', key: 'secret'),
        throwsA(isA<PhysicalInvalidRecordingException>()),
      );
    });

    for (final mode in const ['fixed_fallback', 'legacy']) {
      test('keeps the $mode fixed capture exactly 8 s', () async {
        final pcm = _pcm(PcmAudioCodec.recordBytes + 2, 900);
        final response = mode == 'legacy'
            ? http.Response.bytes(
                pcm,
                200,
                headers: {
                  'content-type': 'application/octet-stream',
                  'content-length': '${pcm.length}',
                  'x-audio-sample-rate': '16000',
                  'x-audio-bits': '16',
                  'x-audio-channels': '1',
                  'x-audio-peak': '900',
                  'x-audio-crc32': PcmAudioCodec.crc32(
                    pcm,
                  ).toRadixString(16).padLeft(8, '0'),
                },
              )
            : _recordResponse(
                pcm,
                captureMode: 'fixed_fallback',
                vadState: 'error',
              );
        final client = Esp32PhysicalClient(
          client: MockClient((_) async => response),
        );
        await expectLater(
          client.record(host: '192.168.2.215', key: 'secret'),
          throwsA(isA<PhysicalInvalidRecordingException>()),
        );
      });
    }
  });
}

http.Response _recordResponse(
  Uint8List pcm, {
  required String captureMode,
  required String vadState,
  int? contentLengthOverride,
  int? crcOverride,
}) {
  final stats = PcmAudioCodec.stats(pcm);
  return http.Response.bytes(
    pcm,
    200,
    headers: {
      'content-type': 'application/octet-stream',
      'content-length': '${contentLengthOverride ?? pcm.length}',
      'x-audio-sample-rate': '16000',
      'x-audio-bits': '16',
      'x-audio-channels': '1',
      'x-audio-peak': '${stats.peak}',
      'x-audio-crc32': (crcOverride ?? PcmAudioCodec.crc32(pcm))
          .toRadixString(16)
          .padLeft(8, '0'),
      'x-capture-mode': captureMode,
      'x-vad-state': vadState,
      'x-audio-recording-id': '17',
    },
  );
}

Uint8List _pcm(int length, int amplitude) {
  final pcm = Uint8List(length);
  final data = ByteData.sublistView(pcm);
  for (var offset = 0; offset < length; offset += 2) {
    data.setInt16(offset, amplitude, Endian.little);
  }
  return pcm;
}

Uint8List _oddPcm(int length) {
  final pcm = Uint8List(length);
  final data = ByteData.sublistView(pcm);
  for (var offset = 0; offset + 2 <= length; offset += 2) {
    data.setInt16(offset, 900, Endian.little);
  }
  return pcm;
}

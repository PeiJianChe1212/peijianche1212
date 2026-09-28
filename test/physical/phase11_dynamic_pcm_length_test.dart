import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:peijianche_app/models/chat_message.dart';
import 'package:peijianche_app/physical/doubao_speech_clients.dart';
import 'package:peijianche_app/physical/esp32_physical_client.dart';
import 'package:peijianche_app/physical/pcm_audio_codec.dart';
import 'package:peijianche_app/physical/pcm_audio_gain.dart';
import 'package:peijianche_app/physical/physical_host_settings.dart';
import 'package:peijianche_app/physical/physical_session_controller.dart';

/// Phase 11 dynamic VAD PCM length integration coverage.
///
/// Runs the real [Esp32PhysicalClient] response parser (over a mocked HTTP
/// transport) through the real [PhysicalSessionController] turn pipeline, and
/// reproduces the exact preparation the cloud ASR client performs before any
/// network I/O: [PcmAudioGain.applyAdaptiveGain] followed by
/// [PcmAudioCodec.wavFromPcm]. Nothing here talks to the device, the
/// microphone or the cloud.
void main() {
  const settings = PhysicalHostSettings(
    esp32Host: '192.168.2.215',
    requestKey: 'device-key',
    volcengineApiKey: 'speech-key',
    characterId: 'character-id',
  );

  final accepted = <({String label, int length, bool legacy})>[
    (
      label: 'Phase 9 legacy 8 s fixed capture',
      length: PcmAudioCodec.recordBytes,
      legacy: true,
    ),
    (
      label: 'Phase 11 max_duration at 8 s',
      length: PcmAudioCodec.recordBytes,
      legacy: false,
    ),
    (
      label: 'Phase 11 max_duration at 8.5 s',
      length: PcmAudioCodec.recordBytes + 16000,
      legacy: false,
    ),
    (
      label: 'Phase 11 max_duration at 9.5 s',
      length: PcmAudioCodec.phase11MaxCaptureBytes,
      legacy: false,
    ),
  ];

  for (final entry in accepted) {
    test('${entry.label} reaches ASR preparation', () async {
      final pcm = _pcm(entry.length, 900);
      final asr = _Asr();
      final controller = _controller(
        Esp32PhysicalClient(
          client: _deviceClient(pcm, legacy: entry.legacy),
        ),
        asr,
      );
      addTearDown(controller.dispose);

      await controller.startEndToEndTurn(settings);

      expect(asr.calls, 1);
      expect(asr.received.single.length, entry.length);
      expect(asr.preparedWav.single.length, entry.length + 44);
      expect(
        ByteData.sublistView(
          asr.preparedWav.single,
        ).getUint32(40, Endian.little),
        entry.length,
      );
      expect(controller.stage, PhysicalSessionStage.ready);
      expect(controller.deviceReady, isTrue);
      expect(controller.turnCount, 1);
      expect(controller.transcript, '用户说了一句话。');
    });
  }

  for (final (label, excess) in const <(String, int)>[
    ('one sample', 2),
    ('one block', 320),
  ]) {
    test('dynamic capture $label past the contract never reaches ASR', () async {
      final pcm = _pcm(PcmAudioCodec.phase11MaxCaptureBytes + excess, 900);
      final asr = _Asr();
      final controller = _controller(
        Esp32PhysicalClient(client: _deviceClient(pcm)),
        asr,
      );
      addTearDown(controller.dispose);

      await controller.startEndToEndTurn(settings);

      expect(asr.calls, 0);
      expect(controller.latestCaptureForDiagnostics, isNull);
      expect(controller.stage, PhysicalSessionStage.ready);
      expect(controller.deviceReady, isTrue);
      expect(controller.canRecord, isTrue);
    });
  }

  test('CRC mismatch on the longest legal capture never reaches ASR', () async {
    final pcm = _pcm(PcmAudioCodec.phase11MaxCaptureBytes, 900);
    final asr = _Asr();
    final controller = _controller(
      Esp32PhysicalClient(client: _deviceClient(pcm, breakCrc: true)),
      asr,
    );
    addTearDown(controller.dispose);

    await controller.startEndToEndTurn(settings);

    expect(asr.calls, 0);
    expect(controller.latestCaptureForDiagnostics, isNull);
    expect(controller.stage, PhysicalSessionStage.ready);
  });
}

PhysicalSessionController _controller(Esp32PhysicalClient device, _Asr asr) {
  return PhysicalSessionController(
    device: device,
    asr: asr,
    tts: _Tts(),
    coreReply:
        (
          String characterId,
          String userText,
          List<ChatMessage> transientContext,
        ) async =>
            '<PEILINK_DISPLAY>（点头。）收到。</PEILINK_DISPLAY>'
            '<PEILINK_SPOKEN>收到。</PEILINK_SPOKEN>',
    modelConfigured: () async => true,
  );
}

/// Mocked ESP32 transport: `/status`, `/record` and `/audio` only.
///
/// [legacy] omits the `X-Capture-Mode` / `X-VAD-State` headers, which is the
/// Phase 9 fixed-response shape the client must keep treating as an exact 8 s
/// capture.
MockClient _deviceClient(
  Uint8List pcm, {
  bool breakCrc = false,
  bool legacy = false,
}) {
  return MockClient((request) async {
    switch (request.url.path) {
      case '/status':
        return http.Response(
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
        );
      case '/record':
        final stats = PcmAudioCodec.stats(pcm);
        final crc = PcmAudioCodec.crc32(pcm);
        return http.Response.bytes(
          pcm,
          200,
          headers: {
            'content-type': 'application/octet-stream',
            'content-length': '${pcm.length}',
            'x-audio-sample-rate': '16000',
            'x-audio-bits': '16',
            'x-audio-channels': '1',
            'x-audio-peak': '${stats.peak}',
            'x-audio-crc32': (breakCrc ? crc ^ 0x1 : crc)
                .toRadixString(16)
                .padLeft(8, '0'),
            if (!legacy) 'x-capture-mode': 'vad',
            if (!legacy) 'x-vad-state': 'max_duration',
            'x-audio-recording-id': '17',
          },
        );
      case '/audio':
        return http.Response(
          jsonEncode({
            'ok': true,
            'played': true,
            'received_bytes': request.bodyBytes.length,
            'state': 'idle',
            'rx_errors': 0,
            'tx_errors': 0,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
    }
    return http.Response('{}', 404);
  });
}

/// Offline stand-in for [DoubaoAsrClient]: performs the same local preparation
/// (adaptive gain, then WAV wrapping) and returns text without uploading.
class _Asr extends DoubaoAsrClient {
  int calls = 0;
  final List<Uint8List> received = [];
  final List<Uint8List> preparedWav = [];

  @override
  Future<String> transcribe({
    required Uint8List pcm,
    required String apiKey,
    String boostingTableId = '',
    void Function(AsrTranscribeStats stats)? onStats,
  }) async {
    calls++;
    received.add(pcm);
    final gain = PcmAudioGain.applyAdaptiveGain(pcm);
    preparedWav.add(PcmAudioCodec.wavFromPcm(gain.output));
    return '用户说了一句话。';
  }

  @override
  void dispose() {}
}

class _Tts extends DoubaoTtsClient {
  @override
  Future<Uint8List> synthesize({
    required String text,
    required String apiKey,
  }) async => _pcm(4800, 900);

  @override
  void dispose() {}
}

Uint8List _pcm(int length, int amplitude) {
  final pcm = Uint8List(length);
  final data = ByteData.sublistView(pcm);
  for (var offset = 0; offset < length; offset += 2) {
    data.setInt16(offset, amplitude, Endian.little);
  }
  return pcm;
}

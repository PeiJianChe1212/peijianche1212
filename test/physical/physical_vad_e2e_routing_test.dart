import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/models/chat_message.dart';
import 'package:peijianche_app/physical/doubao_speech_clients.dart';
import 'package:peijianche_app/physical/esp32_physical_client.dart';
import 'package:peijianche_app/physical/pcm_audio_codec.dart';
import 'package:peijianche_app/physical/physical_host_settings.dart';
import 'package:peijianche_app/physical/physical_session_controller.dart';

void main() {
  const settings = PhysicalHostSettings(
    esp32Host: '192.168.2.215',
    requestKey: 'device-key',
    volcengineApiKey: 'speech-key',
    characterId: 'character-id',
  );

  test('VAD no_speech stops before ASR and leaves the device ready', () async {
    final device = _VadDevice.noSpeech();
    final asr = _Asr();
    final controller = _controller(device, asr);
    addTearDown(controller.dispose);

    await controller.startEndToEndTurn(settings);

    expect(device.recordCalls, 1);
    expect(asr.calls, 0);
    expect(device.playCalls, 0);
    expect(controller.turnCount, 0);
    expect(controller.stage, PhysicalSessionStage.ready);
    expect(controller.message, '未检测到可识别语音');
  });

  for (final state in const ['complete', 'max_duration']) {
    test('VAD $state dynamic PCM reaches ASR unchanged', () async {
      final pcm = _pcm(state == 'complete' ? 48000 : 256000, 900);
      final device = _VadDevice.capture(
        pcm,
        captureMode: 'vad',
        vadState: state,
      );
      final asr = _Asr();
      final controller = _controller(device, asr);
      addTearDown(controller.dispose);

      await controller.startEndToEndTurn(settings);

      expect(asr.calls, 1);
      expect(asr.received.single, same(pcm));
      expect(device.playCalls, 1);
      expect(controller.turnCount, 1);
      expect(controller.stage, PhysicalSessionStage.ready);
    });
  }

  test('VAD error fixed 8s fallback reaches ASR', () async {
    final pcm = _pcm(PcmAudioCodec.recordBytes, 900);
    final device = _VadDevice.capture(
      pcm,
      captureMode: 'fixed_fallback',
      vadState: 'error',
    );
    final asr = _Asr();
    final controller = _controller(device, asr);
    addTearDown(controller.dispose);

    await controller.startEndToEndTurn(settings);

    expect(asr.calls, 1);
    expect(asr.received.single.length, PcmAudioCodec.recordBytes);
    expect(device.playCalls, 1);
    expect(controller.turnCount, 1);
  });
}

PhysicalSessionController _controller(_VadDevice device, _Asr asr) {
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

class _VadDevice extends Esp32PhysicalClient {
  _VadDevice._(this._capture, this._noSpeech);

  factory _VadDevice.noSpeech() => _VadDevice._(null, true);

  factory _VadDevice.capture(
    Uint8List pcm, {
    required String captureMode,
    required String vadState,
  }) => _VadDevice._(
    PhysicalCapture(
      pcm: pcm,
      stats: PcmAudioCodec.stats(pcm),
      crc32: PcmAudioCodec.crc32(pcm),
      captureMode: captureMode,
      vadState: vadState,
    ),
    false,
  );

  final PhysicalCapture? _capture;
  final bool _noSpeech;
  int recordCalls = 0;
  int playCalls = 0;

  @override
  Future<Esp32Status> status({
    required String host,
    required String key,
  }) async => const Esp32Status(
    ok: true,
    phase: 11,
    state: 'idle',
    sampleRate: 16000,
    bits: 16,
    channels: 1,
    recordSeconds: 8,
    maxPlaybackBytes: 1048576,
    rxErrors: 0,
    txErrors: 0,
    captureMode: 'vad',
    fixedFallback: true,
  );

  @override
  Future<PhysicalCapture> record({
    required String host,
    required String key,
  }) async {
    recordCalls++;
    if (_noSpeech) {
      throw const PhysicalNoSpeechException('未检测到可识别语音');
    }
    return _capture!;
  }

  @override
  Future<void> play({
    required String host,
    required String key,
    required Uint8List pcm,
    required double gain,
  }) async {
    playCalls++;
  }

  @override
  void dispose() {}
}

class _Asr extends DoubaoAsrClient {
  int calls = 0;
  final List<Uint8List> received = [];

  @override
  Future<String> transcribe({
    required Uint8List pcm,
    required String apiKey,
    String boostingTableId = '',
    void Function(AsrTranscribeStats stats)? onStats,
  }) async {
    calls++;
    received.add(pcm);
    return '老裴，你在干嘛？';
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

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/physical/doubao_speech_clients.dart';
import 'package:peijianche_app/physical/esp32_physical_client.dart';
import 'package:peijianche_app/physical/pcm_audio_codec.dart';
import 'package:peijianche_app/physical/physical_host_settings.dart';
import 'package:peijianche_app/physical/physical_session_controller.dart';

void main() {
  const settings = PhysicalHostSettings(
    esp32Host: 'device.local',
    requestKey: 'device-key',
    volcengineApiKey: 'speech-key',
    characterId: 'character-id',
  );

  test('dispose during record blocks all later stages', () async {
    final device = _Device(blockRecord: true);
    final asr = _Asr();
    final tts = _Tts();
    final controller = _controller(device, asr, tts);
    final future = controller.startEndToEndTurn(settings);
    await device.recordStarted.future;

    controller.dispose();
    device.recordGate.complete();
    await future;

    _assertNoSideEffects(controller, tts, device);
    expect(asr.calls, 0);
    expect(device.playCalls, 0);
    expect(controller.turnCount, 0);
  });

  test('dispose during ASR blocks LLM TTS and playback', () async {
    final device = _Device();
    final asr = _Asr(block: true);
    final tts = _Tts();
    final controller = _controller(device, asr, tts);
    final future = controller.startEndToEndTurn(settings);
    await asr.started.future;

    controller.dispose();
    asr.gate.complete();
    await future;

    _assertNoSideEffects(controller, tts, device);
    expect(asr.calls, 1);
    expect(device.playCalls, 0);
    expect(controller.turnCount, 0);
    expect(controller.transcript, isEmpty);
  });

  test('dispose during LLM blocks TTS playback and append', () async {
    final device = _Device();
    final asr = _Asr();
    final tts = _Tts();
    final coreGate = Completer<String>();
    final coreStarted = Completer<void>();
    final controller = PhysicalSessionController(
      device: device,
      asr: asr,
      tts: tts,
      coreReply: (_, _, _) async {
        coreStarted.complete();
        return coreGate.future;
      },
      modelConfigured: () async => true,
    );
    final future = controller.startEndToEndTurn(settings);
    await asr.completed.future;
    await coreStarted.future;

    controller.dispose();
    coreGate.complete('（动作）“本来只有这句话。”');
    await future;

    expect(tts.calls, 0);
    expect(device.playCalls, 0);
    expect(controller.turnCount, 0);
    expect(controller.displayReply, isEmpty);
    expect(controller.spokenReply, isEmpty);
    expect(controller.speechContractDiagnostics, isNull);
    expect(controller.ttsInputExact, isNull);
    controller.notifyListeners();
  });

  test('dispose during TTS blocks playback and append', () async {
    final device = _Device();
    final asr = _Asr();
    final tts = _Tts(block: true);
    final controller = _controller(device, asr, tts);
    final future = controller.startEndToEndTurn(settings);
    await tts.started.future;

    controller.dispose();
    tts.gate.complete();
    await future;

    expect(device.playCalls, 0);
    expect(controller.turnCount, 0);
    controller.notifyListeners();
  });

  test('dispose during playback does not append after return', () async {
    final device = _Device(blockPlay: true);
    final asr = _Asr();
    final tts = _Tts();
    final controller = _controller(device, asr, tts);
    final future = controller.startEndToEndTurn(settings);
    await device.playStarted.future;

    controller.dispose();
    device.playGate.complete();
    await future;

    expect(device.playCalls, 1);
    expect(controller.turnCount, 0);
    expect(controller.stage, PhysicalSessionStage.playing);
    controller.notifyListeners();
  });
}

PhysicalSessionController _controller(
  _Device device,
  _Asr asr,
  _Tts tts,
) {
  final controller = PhysicalSessionController(
    device: device,
    asr: asr,
    tts: tts,
    coreReply: (_, _, _) async => '（动作）“唯一对白。”',
    modelConfigured: () async => true,
  );
  return controller;
}

void _assertNoSideEffects(
  PhysicalSessionController controller,
  _Tts tts,
  _Device device,
) {
  expect(tts.calls, 0);
  expect(device.playCalls, 0);
  expect(controller.turnCount, 0);
  expect(controller.transcript, isEmpty);
  expect(controller.displayReply, isEmpty);
  expect(controller.spokenReply, isEmpty);
  expect(controller.speechContractDiagnostics, isNull);
  expect(controller.ttsInputExact, isNull);
  controller.notifyListeners();
}

class _Device extends Esp32PhysicalClient {
  _Device({this.blockRecord = false, this.blockPlay = false});
  final bool blockRecord;
  final bool blockPlay;
  final Completer<void> recordStarted = Completer<void>();
  final Completer<void> recordGate = Completer<void>();
  final Completer<void> playStarted = Completer<void>();
  final Completer<void> playGate = Completer<void>();
  int statusCalls = 0;
  int recordCalls = 0;
  int playCalls = 0;

  @override
  Future<Esp32Status> status({
    required String host,
    required String key,
  }) async {
    statusCalls++;
    return const Esp32Status(
      ok: true,
      phase: 9,
      state: 'idle',
      sampleRate: PcmAudioCodec.sampleRate,
      bits: PcmAudioCodec.bits,
      channels: PcmAudioCodec.channels,
      recordSeconds: PcmAudioCodec.recordSeconds,
      maxPlaybackBytes: PcmAudioCodec.maxPlaybackBytes,
      rxErrors: 0,
      txErrors: 0,
    );
  }

  @override
  Future<PhysicalCapture> record({
    required String host,
    required String key,
  }) async {
    recordCalls++;
    recordStarted.complete();
    if (blockRecord) {
      await recordGate.future;
    } else {
      recordGate.complete();
    }
    final pcm = _pcm(PcmAudioCodec.recordBytes);
    return PhysicalCapture(
      pcm: pcm,
      stats: PcmAudioCodec.stats(pcm),
      crc32: PcmAudioCodec.crc32(pcm),
    );
  }

  @override
  Future<void> play({
    required String host,
    required String key,
    required Uint8List pcm,
    required double gain,
  }) async {
    playCalls++;
    playStarted.complete();
    if (blockPlay) {
      await playGate.future;
    } else {
      playGate.complete();
    }
  }

  @override
  void dispose() {}
}

class _Asr extends DoubaoAsrClient {
  _Asr({this.block = false});
  final bool block;
  final Completer<void> started = Completer<void>();
  final Completer<void> completed = Completer<void>();
  final Completer<void> gate = Completer<void>();
  int calls = 0;

  @override
  Future<String> transcribe({
    required Uint8List pcm,
    required String apiKey,
    String boostingTableId = '',
    void Function(AsrTranscribeStats stats)? onStats,
  }) async {
    calls++;
    started.complete();
    final text = '唯一语音。';
    if (block) {
      await gate.future;
    }
    completed.complete();
    return text;
  }

  @override
  void dispose() {}
}

class _Tts extends DoubaoTtsClient {
  _Tts({this.block = false});
  final bool block;
  final Completer<void> started = Completer<void>();
  final Completer<void> gate = Completer<void>();
  int calls = 0;

  @override
  Future<Uint8List> synthesize({
    required String text,
    required String apiKey,
  }) async {
    calls++;
    started.complete();
    if (block) {
      await gate.future;
    }
    return _pcm(4800);
  }

  @override
  void dispose() {}
}

Uint8List _pcm(int length) {
  final pcm = Uint8List(length);
  final data = ByteData.sublistView(pcm);
  for (var offset = 0; offset < pcm.length; offset += 2) {
    data.setInt16(offset, 1000, Endian.little);
  }
  return pcm;
}

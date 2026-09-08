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

  test('ten consecutive end-to-end turns succeed with turn-scoped state', () async {
    final device = _FakeDevice();
    final asrTexts = [
      for (var i = 1; i <= 10; i++) '识别文本$i。',
    ];
    final asr = _FakeAsr(asrTexts);
    final tts = _FakeTts();
    var coreCalls = 0;
    final controller = PhysicalSessionController(
      device: device,
      asr: asr,
      tts: tts,
      coreReply: (_, _, _) async {
        coreCalls++;
        return '角色回复$coreCalls。';
      },
      modelConfigured: () async => true,
    );
    addTearDown(controller.dispose);

    for (var round = 1; round <= 10; round++) {
      await controller.startEndToEndTurn(settings);

      expect(controller.stage, PhysicalSessionStage.ready, reason: 'round $round');
      expect(controller.isBusy, isFalse, reason: 'round $round');
      final expectedTurns = round < 8 ? round : 8;
      expect(controller.turnCount, expectedTurns, reason: 'round $round');
      expect(
        controller.transcript,
        '识别文本$round。',
        reason: 'round=$round asrCalls=${asr.calls} consumed=${asr.consumed}',
      );
      expect(controller.displayReply, '角色回复$round。');
      expect(controller.spokenReply, '角色回复$round。');
      expect(controller.ttsInputExact, '角色回复$round。');
      expect(controller.ttsInputMatchesSpoken, isTrue);
      expect(controller.speechContractDiagnostics, isNotNull);
      expect(controller.transcript, isNot(contains('识别文本${round - 1}。')));
      expect(controller.spokenReply, isNot(contains('角色回复${round - 1}。')));
    }

    expect(device.statusCalls, 10);
    expect(device.recordCalls, 10);
    expect(asr.calls, 10);
    expect(coreCalls, 10);
    expect(tts.calls, 10);
    expect(device.playCalls, 10);
    expect(controller.turnCount, 8);
  });

  test('every stage failure is followed by a clean successful turn', () async {
    const scenarios = [
      'record',
      'asr',
      'asr-timeout',
      'llm',
      'llm-timeout',
      'tts',
      'tts-timeout',
      'play',
    ];

    for (final scenario in scenarios) {
      final device = _FakeDevice();
      final asr = _FakeAsr(['第一轮ASR。', '第二轮ASR。']);
      final tts = _FakeTts();
      var coreCalls = 0;
      final controller = PhysicalSessionController(
        device: device,
        asr: asr,
        tts: tts,
        coreReply: (_, _, _) async {
          coreCalls++;
          if (scenario == 'llm' && coreCalls == 1) {
            throw StateError('llm failure');
          }
          if (scenario == 'llm-timeout' && coreCalls == 1) {
            await Future<void>.delayed(const Duration(milliseconds: 1));
            throw TimeoutException('llm timeout');
          }
          return '角色回复$coreCalls。';
        },
        modelConfigured: () async => true,
      );
      addTearDown(controller.dispose);

      if (scenario == 'record') device.failNextRecord = true;
      if (scenario == 'play') device.failNextPlay = true;
      asr.failNext = scenario == 'asr';
      asr.timeoutNext = scenario == 'asr-timeout';
      tts.failNext = scenario == 'tts';
      tts.timeoutNext = scenario == 'tts-timeout';

      await controller.startEndToEndTurn(settings);

      final deviceFailure =
          scenario == 'record' || scenario == 'play';
      expect(
        controller.stage,
        deviceFailure
            ? PhysicalSessionStage.error
            : PhysicalSessionStage.ready,
        reason: scenario,
      );
      expect(controller.isBusy, isFalse, reason: scenario);
      expect(controller.turnCount, 0, reason: scenario);
      expect(controller.canContinue, isFalse, reason: scenario);

      if (scenario == 'record' ||
          scenario == 'asr' ||
          scenario == 'asr-timeout') {
        expect(controller.transcript, isEmpty, reason: scenario);
        expect(controller.displayReply, isEmpty, reason: scenario);
        expect(controller.spokenReply, isEmpty, reason: scenario);
        expect(controller.speechContractDiagnostics, isNull, reason: scenario);
        expect(controller.ttsInputExact, isNull, reason: scenario);
      } else if (scenario == 'llm' || scenario == 'llm-timeout') {
        expect(controller.transcript, '第一轮ASR。', reason: scenario);
        expect(controller.displayReply, isEmpty, reason: scenario);
        expect(controller.spokenReply, isEmpty, reason: scenario);
        expect(controller.speechContractDiagnostics, isNull, reason: scenario);
        expect(controller.ttsInputExact, isNull, reason: scenario);
      } else {
        expect(controller.transcript, '第一轮ASR。', reason: scenario);
        expect(controller.displayReply, '角色回复1。', reason: scenario);
        expect(controller.spokenReply, '角色回复1。', reason: scenario);
        expect(controller.speechContractDiagnostics, isNotNull, reason: scenario);
        if (scenario == 'tts' ||
            scenario == 'tts-timeout' ||
            scenario == 'play') {
          expect(controller.ttsInputExact, '角色回复1。', reason: scenario);
        }
      }
      expect(tts.calls, const {'record', 'asr', 'asr-timeout', 'llm', 'llm-timeout'}.contains(scenario) ? 0 : 1, reason: scenario);
      expect(device.playCalls, scenario == 'play' ? 1 : 0, reason: scenario);

      await controller.startEndToEndTurn(settings);

      expect(controller.stage, PhysicalSessionStage.ready, reason: scenario);
      expect(controller.isBusy, isFalse, reason: scenario);
      expect(controller.turnCount, 1, reason: scenario);
      final expectedTranscript = const {
        'record',
        'asr',
        'asr-timeout',
      }.contains(scenario)
          ? '第一轮ASR。'
          : '第二轮ASR。';
      final expectedReply = const {
        'record',
        'asr',
        'asr-timeout',
      }.contains(scenario)
          ? '角色回复1。'
          : '角色回复2。';
      expect(controller.transcript, expectedTranscript, reason: scenario);
      expect(controller.displayReply, expectedReply, reason: scenario);
      expect(controller.spokenReply, expectedReply, reason: scenario);
      expect(controller.ttsInputExact, expectedReply, reason: scenario);
      expect(controller.ttsInputMatchesSpoken, isTrue, reason: scenario);
      expect(controller.speechContractDiagnostics, isNotNull, reason: scenario);
      expect(tts.texts.last, expectedReply, reason: scenario);
      expect(device.playCalls, scenario == 'play' ? 2 : 1, reason: scenario);
    }
  });

  test('spoken-empty turn is followed by a normal spoken next turn', () async {
    final device = _FakeDevice();
    final asr = _FakeAsr(['空语音轮', '正常语音轮']);
    final tts = _FakeTts();
    var coreCalls = 0;
    final controller = PhysicalSessionController(
      device: device,
      asr: asr,
      tts: tts,
      coreReply: (_, _, _) async {
        coreCalls++;
        if (coreCalls == 1) return '（只有动作，没有对白）';
        return '正常回复。';
      },
      modelConfigured: () async => true,
    );
    addTearDown(controller.dispose);

    await controller.startEndToEndTurn(settings);

    expect(controller.stage, PhysicalSessionStage.ready);
    expect(controller.isBusy, isFalse);
    expect(controller.spokenReply, isEmpty);
    expect(controller.ttsInputExact, isNull);
    expect(tts.calls, 0);
    expect(device.playCalls, 0);
    expect(controller.turnCount, 0);
    expect(controller.lastSpeechFilterNote, contains('empty_safe_result'));

    await controller.startEndToEndTurn(settings);

    expect(controller.stage, PhysicalSessionStage.ready);
    expect(controller.spokenReply, '正常回复。');
    expect(tts.texts, ['正常回复。']);
    expect(device.playCalls, 1);
    expect(controller.turnCount, 1);
  });

  test('re-entry during a running turn never starts a second chain', () async {
    final device = _FakeDevice();
    final asrGate = Completer<void>();
    final asr = _FakeAsr(['唯一轮次。'], gate: asrGate);
    final tts = _FakeTts();
    var coreCalls = 0;
    final controller = PhysicalSessionController(
      device: device,
      asr: asr,
      tts: tts,
      coreReply: (_, _, _) async {
        coreCalls++;
        return '唯一回复。';
      },
      modelConfigured: () async => true,
    );
    addTearDown(controller.dispose);

    final first = controller.startEndToEndTurn(settings);
    final duplicate = controller.startEndToEndTurn(settings);
    asrGate.complete();
    await Future.wait([first, duplicate]);

    expect(device.statusCalls, 1);
    expect(device.recordCalls, 1);
    expect(asr.calls, 1);
    expect(coreCalls, 1);
    expect(tts.calls, 1);
    expect(device.playCalls, 1);
    expect(controller.turnCount, 1);
    expect(controller.stage, PhysicalSessionStage.ready);
    expect(controller.isBusy, isFalse);
  });
}

class _FakeDevice extends Esp32PhysicalClient {
  int statusCalls = 0;
  int recordCalls = 0;
  int playCalls = 0;
  bool failNextRecord = false;
  bool failNextPlay = false;

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
    if (failNextRecord) {
      failNextRecord = false;
      throw const PhysicalProtocolException('record failure');
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
    if (failNextPlay) {
      failNextPlay = false;
      throw const PhysicalProtocolException('play failure');
    }
  }

  @override
  void dispose() {}
}

class _FakeAsr extends DoubaoAsrClient {
  _FakeAsr(this.results, {this.gate});
  final List<String> results;
  final Completer<void>? gate;
  bool failNext = false;
  bool timeoutNext = false;
  int calls = 0;
  final List<String> consumed = [];

  @override
  Future<String> transcribe({
    required Uint8List pcm,
    required String apiKey,
    String boostingTableId = '',
    void Function(AsrTranscribeStats stats)? onStats,
  }) async {
    await gate?.future;
    calls++;
    if (failNext || timeoutNext) {
      final timeout = timeoutNext;
      failNext = false;
      timeoutNext = false;
      if (timeout) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
        throw TimeoutException('asr timeout');
      }
      throw const SpeechCloudException('asr failure');
    }
    final result = results.removeAt(0);
    consumed.add(result);
    return result;
  }

  @override
  void dispose() {}
}

class _FakeTts extends DoubaoTtsClient {
  bool failNext = false;
  bool timeoutNext = false;
  int calls = 0;
  final List<String> texts = [];

  @override
  Future<Uint8List> synthesize({
    required String text,
    required String apiKey,
  }) async {
    calls++;
    texts.add(text);
    if (failNext || timeoutNext) {
      final timeout = timeoutNext;
      failNext = false;
      timeoutNext = false;
      if (timeout) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
        throw TimeoutException('tts timeout');
      }
      throw const SpeechCloudException('tts failure');
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

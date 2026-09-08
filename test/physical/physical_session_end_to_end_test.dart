import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/models/chat_message.dart';
import 'package:peijianche_app/physical/doubao_speech_clients.dart';
import 'package:peijianche_app/physical/esp32_physical_client.dart';
import 'package:peijianche_app/physical/pcm_audio_codec.dart';
import 'package:peijianche_app/physical/physical_host_settings.dart';
import 'package:peijianche_app/physical/physical_session_controller.dart';
import 'fixtures/verified_raw_reply.dart';

void main() {
  const settings = PhysicalHostSettings(
    esp32Host: 'device.local',
    requestKey: 'device-key',
    volcengineApiKey: 'speech-key',
    characterId: 'character-id',
  );

  test(
    'end-to-end turn calls each stage once and may run again after success',
    () async {
      final device = _FakeDevice();
      final asr = _FakeAsr(['第一句。', '第二句。']);
      final tts = _FakeTts();
      var coreCalls = 0;
      final coreTexts = <String>[];
      final controller = PhysicalSessionController(
        device: device,
        asr: asr,
        tts: tts,
        coreReply: (_, userText, _) async {
          coreTexts.add(userText);
          coreCalls++;
          return '回复$coreCalls';
        },
        modelConfigured: () async => true,
      );
      addTearDown(controller.dispose);

      await controller.startEndToEndTurn(settings);

      expect(device.statusCalls, 1);
      expect(device.recordCalls, 1);
      expect(asr.calls, 1);
      expect(coreCalls, 1);
      expect(tts.calls, 1);
      expect(device.playCalls, 1);
      expect(controller.stage, PhysicalSessionStage.ready);
      expect(controller.deviceReady, isTrue);
      expect(controller.canRecord, isTrue);
      expect(controller.canContinue, isFalse);
      expect(controller.turnCount, 1);
      expect(controller.transcript, '第一句。');
      expect(controller.spokenReply, '回复1');
      expect(tts.texts, ['回复1']);
      expect(device.playedPcm!.length, 3200);

      await controller.startEndToEndTurn(settings);

      expect(device.statusCalls, 2);
      expect(device.recordCalls, 2);
      expect(asr.calls, 2);
      expect(coreCalls, 2);
      expect(tts.calls, 2);
      expect(device.playCalls, 2);
      expect(controller.turnCount, 2);
      expect(controller.stage, PhysicalSessionStage.ready);
      expect(tts.texts.last, '回复2');
    },
  );

  test('diagnostics capture actual TTS argument and reset before next model check', () async {
    final modelGate = Completer<bool>();
    var modelChecks = 0;
    final tts = _FakeTts();
    late PhysicalSessionController controller;
    tts.onText = (text) {
      expect(controller.ttsInputExact, text);
      expect(controller.spokenReply, text);
      expect(controller.ttsInputMatchesSpoken, isTrue);
    };
    controller = PhysicalSessionController(
      device: _FakeDevice(), asr: _FakeAsr(['用户消息']), tts: tts,
      coreReply: (_, _, _) async =>
        '<PEILINK_DISPLAY>（轻笑。）你好。</PEILINK_DISPLAY>'
        '<PEILINK_SPOKEN>你好。\n第二句。</PEILINK_SPOKEN>',
      modelConfigured: () async => ++modelChecks == 1 ? true : await modelGate.future,
    );
    addTearDown(controller.dispose);
    await controller.startEndToEndTurn(settings);
    expect(controller.speechContractDiagnostics!.contractParsed, isTrue);
    expect(controller.ttsInputExact, '你好。\n第二句。');
    expect(tts.texts.single, controller.ttsInputExact);
    final next = controller.startEndToEndTurn(settings);
    expect(controller.speechContractDiagnostics, isNull);
    expect(controller.ttsInputExact, isNull);
    expect(controller.ttsInputMatchesSpoken, isNull);
    modelGate.complete(false);
    await next;
    expect(controller.speechContractDiagnostics, isNull);
    expect(tts.calls, 1);
  });

  test('verified raw leak is fixed at actual TTS boundary; action-only stops TTS', () async {
    for (final raw in [verifiedRawReply, '（只有动作，没有对白）', '他尾音上扬。']) {
      final device = _FakeDevice();
      final tts = _FakeTts();
      final controller = PhysicalSessionController(
        device: device, asr: _FakeAsr(['用户输入']), tts: tts,
        coreReply: (_, _, _) async => raw,
        modelConfigured: () async => true,
      );
      addTearDown(controller.dispose);
      await controller.startEndToEndTurn(settings);
      expect(controller.displayReply, raw);
      expect(controller.speechContractDiagnostics!.contractParsed, isFalse);
      if (raw == verifiedRawReply) {
        expect(tts.texts, [verifiedSpokenReply]);
        expect(controller.ttsInputExact, verifiedSpokenReply);
        expect(controller.ttsInputMatchesSpoken, isTrue);
        expect(device.playCalls, 1);
      } else {
        expect(controller.spokenReply, isEmpty);
        expect(controller.ttsInputExact, isNull);
        expect(tts.calls, 0);
        expect(device.playCalls, 0);
        expect(controller.lastSpeechFilterNote, contains('empty_safe_result'));
      }
    }
  });

  test('model not configured stops before status or record', () async {
    final device = _FakeDevice();
    final asr = _FakeAsr(['不应调用']);
    final tts = _FakeTts();
    final controller = PhysicalSessionController(
      device: device,
      asr: asr,
      tts: tts,
      coreReply: (_, _, _) async => '不应调用',
      modelConfigured: () async => false,
    );
    addTearDown(controller.dispose);

    await controller.startEndToEndTurn(settings);

    expect(device.statusCalls, 0);
    expect(device.recordCalls, 0);
    expect(asr.calls, 0);
    expect(tts.calls, 0);
    expect(device.playCalls, 0);
    expect(controller.turnCount, 0);
    expect(controller.message, '请先配置正式聊天模型');
  });

  test('every failure stops the chain and never appends a turn', () async {
    const scenarios = [
      'status',
      'record',
      'asr',
      'asr-empty',
      'core',
      'spoken-empty',
      'tts',
      'pcm',
      'play',
    ];
    for (final failure in scenarios) {
      final device = _FakeDevice()
        ..failStatus = failure == 'status'
        ..failRecord = failure == 'record'
        ..failPlay = failure == 'play';
      final asr = _FakeAsr(
        failure == 'asr-empty' ? const [''] : const ['用户消息'],
        fail: failure == 'asr',
      );
      final tts = _FakeTts(
        fail: failure == 'tts',
        badPcm: failure == 'pcm',
      );
      var coreCalls = 0;
      final controller = PhysicalSessionController(
        device: device,
        asr: asr,
        tts: tts,
        coreReply: (_, _, _) async {
          coreCalls++;
          if (failure == 'core') throw StateError('core failure');
          if (failure == 'spoken-empty') return '';
          return '回复';
        },
        modelConfigured: () async => true,
      );
      addTearDown(controller.dispose);

      await controller.startEndToEndTurn(settings);

      final expectedStage = (failure == 'status' ||
              failure == 'record' ||
              failure == 'play')
          ? PhysicalSessionStage.error
          : PhysicalSessionStage.ready;
      expect(controller.stage, expectedStage, reason: failure);
      expect(controller.turnCount, 0, reason: failure);
      expect(controller.canContinue, isFalse, reason: failure);
      expect(controller.ttsReview, isNull, reason: failure);

      final reachedAsr = !const {'status', 'record'}.contains(failure);
      expect(asr.calls, reachedAsr ? 1 : 0, reason: failure);
      final reachedCore = const {
        'core',
        'spoken-empty',
        'tts',
        'pcm',
        'play',
      }.contains(failure);
      expect(coreCalls, reachedCore ? 1 : 0, reason: failure);
      final reachedTts = const {'tts', 'pcm', 'play'}.contains(failure);
      expect(tts.calls, reachedTts ? 1 : 0, reason: failure);
      expect(
        device.playCalls,
        failure == 'play' ? 1 : 0,
        reason: failure,
      );
    }
  });

  test('failed turn never reuses previous capture reply or tts data', () async {
    final device = _FakeDevice();
    final asr = _FakeAsr(['成功轮']);
    final tts = _FakeTts();
    final controller = PhysicalSessionController(
      device: device,
      asr: asr,
      tts: tts,
      coreReply: (_, _, _) async => '上一轮回复',
      modelConfigured: () async => true,
    );
    addTearDown(controller.dispose);

    await controller.startEndToEndTurn(settings);
    expect(controller.turnCount, 1);
    expect(controller.transcript, '成功轮');
    expect(controller.spokenReply, '上一轮回复');
    expect(device.playedPcm, isNotNull);

    device.failRecord = true;
    await controller.startEndToEndTurn(settings);

    expect(controller.turnCount, 1);
    expect(controller.transcript, isEmpty);
    expect(controller.spokenReply, isEmpty);
    expect(controller.ttsReview, isNull);
    expect(controller.canContinue, isFalse);
    expect(device.recordCalls, 2);
    expect(asr.calls, 1);
    expect(tts.calls, 1);
    expect(device.playCalls, 1);
  });

  test('duplicate end-to-end triggers produce only one chain', () async {
    final device = _FakeDevice();
    final asr = _FakeAsr(['唯一一轮']);
    final tts = _FakeTts();
    final controller = PhysicalSessionController(
      device: device,
      asr: asr,
      tts: tts,
      coreReply: (_, _, _) async => '唯一回复',
      modelConfigured: () async => true,
    );
    addTearDown(controller.dispose);

    final first = controller.startEndToEndTurn(settings);
    final duplicate = controller.startEndToEndTurn(settings);
    await Future.wait([first, duplicate]);

    expect(device.statusCalls, 1);
    expect(device.recordCalls, 1);
    expect(asr.calls, 1);
    expect(tts.calls, 1);
    expect(device.playCalls, 1);
    expect(controller.turnCount, 1);
  });

  test('E2E TTS receives filtered spokenReply instead of raw narration', () async {
    const raw = '他顿了顿，声音放轻：“我没事。”';
    final device = _FakeDevice();
    final asr = _FakeAsr(['过滤轮']);
    final tts = _FakeTts();
    final controller = PhysicalSessionController(
      device: device,
      asr: asr,
      tts: tts,
      coreReply: (_, _, _) async => raw,
      modelConfigured: () async => true,
    );
    addTearDown(controller.dispose);

    await controller.startEndToEndTurn(settings);

    expect(controller.spokenReply, '我没事。');
    expect(tts.texts, ['我没事。']);
    expect(raw, '他顿了顿，声音放轻：“我没事。”');
    expect(controller.lastSpeechFilterNote, contains('quoted_dialogue_extracted'));
  });

  test('dual-output stores display and sends only spoken to TTS', () async {
    final contexts = <List<ChatMessage>>[];
    final device = _FakeDevice();
    final asr = _FakeAsr(['第一轮', '第二轮']);
    final tts = _FakeTts();
    var calls = 0;
    final controller = PhysicalSessionController(
      device: device,
      asr: asr,
      tts: tts,
      coreReply: (_, _, transient) async {
        contexts.add(List.of(transient));
        calls++;
        if (calls == 1) {
          return '<PEILINK_DISPLAY>\n'
              '轻笑一声，放下钢笔。刚才处理完那些事，打算休息。你呢？\n'
              '</PEILINK_DISPLAY>\n'
              '<PEILINK_SPOKEN>\n'
              '刚才处理完那些事，打算休息。你呢？\n'
              '</PEILINK_SPOKEN>';
        }
        return '第二轮回复';
      },
      modelConfigured: () async => true,
    );
    addTearDown(controller.dispose);

    await controller.startEndToEndTurn(settings);

    expect(controller.displayReply, contains('轻笑一声，放下钢笔'));
    expect(controller.spokenReply, isNot(contains('轻笑')));
    expect(tts.texts.single, controller.spokenReply);
    expect(controller.turns.single.displayText, controller.displayReply);
    expect(controller.turns.single.assistantSpokenText, controller.spokenReply);
    expect(controller.lastSpeechFilterNote, isEmpty);

    await controller.startEndToEndTurn(settings);

    final secondContext = contexts[1];
    final assistantContents = secondContext
        .where((message) => message.role == 'assistant')
        .map((message) => message.content)
        .join('\n');
    expect(assistantContents, contains('轻笑一声，放下钢笔'));
    expect(assistantContents, isNot(contains('PEILINK_DISPLAY')));
    expect(assistantContents, isNot(contains('PEILINK_SPOKEN')));
  });

  test('timing records every phase and does not change call order', () async {
    final events = <String>[];
    final device = _FakeDevice(events: events);
    final asr = _FakeAsr(['计时轮'], events: events);
    final tts = _FakeTts(events: events);
    final controller = PhysicalSessionController(
      device: device,
      asr: asr,
      tts: tts,
      coreReply: (_, _, _) async {
        events.add('core');
        return '计时回复';
      },
      modelConfigured: () async => true,
    );
    addTearDown(controller.dispose);

    await controller.startEndToEndTurn(settings);

    final timing = controller.lastEndToEndTiming!;
    expect(timing.failedStage, isNull);
    expect(timing.statusMs, isNotNull);
    expect(timing.recordMs, isNotNull);
    expect(timing.asrMs, isNotNull);
    expect(timing.llmMs, isNotNull);
    expect(timing.ttsMs, isNotNull);
    expect(timing.resampleMs, isNotNull);
    expect(timing.audioMs, isNotNull);
    expect(timing.totalMs, isNotNull);
    expect(events, ['status', 'record', 'asr', 'core', 'tts', 'audio']);
  });

  test('failed timing keeps only completed stages and marks the failure', () async {
    for (final failure in [
      'status',
      'record',
      'asr',
      'llm',
      'tts',
      'pcm',
      'audio',
    ]) {
      final device = _FakeDevice()
        ..failStatus = failure == 'status'
        ..failRecord = failure == 'record'
        ..failPlay = failure == 'audio';
      final asr = _FakeAsr(['消息'], fail: failure == 'asr');
      final tts = _FakeTts(
        fail: failure == 'tts',
        badPcm: failure == 'pcm',
      );
      final controller = PhysicalSessionController(
        device: device,
        asr: asr,
        tts: tts,
        coreReply: (_, _, _) async {
          if (failure == 'llm') throw StateError('llm failure');
          return '回复';
        },
        modelConfigured: () async => true,
      );
      addTearDown(controller.dispose);

      await controller.startEndToEndTurn(settings);
      final timing = controller.lastEndToEndTiming!;
      expect(timing.totalMs, isNotNull, reason: failure);

      if (failure != 'status') {
        expect(timing.statusMs, isNotNull, reason: failure);
      } else {
        expect(timing.statusMs, isNull, reason: failure);
      }
      if (failure == 'record') {
        expect(timing.recordMs, isNull, reason: failure);
      } else if (failure != 'status') {
        expect(timing.recordMs, isNotNull, reason: failure);
      }
      if (failure == 'asr') {
        expect(timing.asrMs, isNull, reason: failure);
      } else if (failure == 'llm' ||
          failure == 'tts' ||
          failure == 'pcm' ||
          failure == 'audio') {
        expect(timing.asrMs, isNotNull, reason: failure);
      }
      if (failure == 'llm') {
        expect(timing.llmMs, isNull, reason: failure);
      } else if (failure == 'tts' || failure == 'pcm' || failure == 'audio') {
        expect(timing.llmMs, isNotNull, reason: failure);
      }
      if (failure == 'tts') {
        expect(timing.ttsMs, isNull, reason: failure);
      } else if (failure == 'pcm' || failure == 'audio') {
        expect(timing.ttsMs, isNotNull, reason: failure);
      }
      if (failure == 'pcm') {
        expect(timing.resampleMs, isNull, reason: failure);
      } else if (failure == 'audio') {
        expect(timing.resampleMs, isNotNull, reason: failure);
      }
      if (failure == 'audio') {
        expect(timing.audioMs, isNull, reason: failure);
      }

      final expected = switch (failure) {
        'status' => PhysicalE2EFailureStage.status,
        'record' => PhysicalE2EFailureStage.record,
        'asr' => PhysicalE2EFailureStage.asr,
        'llm' => PhysicalE2EFailureStage.llm,
        'tts' => PhysicalE2EFailureStage.tts,
        'pcm' => PhysicalE2EFailureStage.resample,
        _ => PhysicalE2EFailureStage.audio,
      };
      expect(timing.failedStage, expected, reason: failure);
    }
  });

  test('timing never carries previous values into the next turn', () async {
    final device = _FakeDevice();
    final controller = PhysicalSessionController(
      device: device,
      asr: _FakeAsr(['成功轮']),
      tts: _FakeTts(),
      coreReply: (_, _, _) async => '成功回复',
      modelConfigured: () async => true,
    );
    addTearDown(controller.dispose);

    await controller.startEndToEndTurn(settings);
    final first = controller.lastEndToEndTiming!;
    expect(first.failedStage, isNull);

    device.failRecord = true;
    await controller.startEndToEndTurn(settings);
    final second = controller.lastEndToEndTiming!;

    expect(identical(first, second), isFalse);
    expect(second.failedStage, PhysicalE2EFailureStage.record);
    expect(second.recordMs, isNull);
    expect(second.audioMs, isNull);
    expect(second.statusMs, isNotNull);
  });
}

class _FakeDevice extends Esp32PhysicalClient {
  _FakeDevice({this.events});
  final List<String>? events;
  int statusCalls = 0;
  int recordCalls = 0;
  int playCalls = 0;
  bool failStatus = false;
  bool failRecord = false;
  bool invalidRecord = false;
  bool failPlay = false;
  Completer<void>? statusGate;
  Uint8List? playedPcm;

  @override
  Future<Esp32Status> status({
    required String host,
    required String key,
  }) async {
    statusCalls++;
    events?.add('status');
    await statusGate?.future;
    if (failStatus) throw const PhysicalProtocolException('status failure');
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
    events?.add('record');
    if (failRecord) throw const PhysicalProtocolException('record failure');
    if (invalidRecord) {
      throw const PhysicalInvalidRecordingException('invalid recording');
    }
    final pcm = _pcm(PcmAudioCodec.recordBytes, 1000);
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
    events?.add('audio');
    playedPcm = pcm;
    if (failPlay) throw const PhysicalProtocolException('play failure');
  }

  @override
  void dispose() {}
}

class _FakeAsr extends DoubaoAsrClient {
  _FakeAsr(this.results, {this.fail = false, this.events});
  final List<String> results;
  final bool fail;
  final List<String>? events;
  int calls = 0;

  @override
  Future<String> transcribe({
    required Uint8List pcm,
    required String apiKey,
    String boostingTableId = '',
    void Function(AsrTranscribeStats stats)? onStats,
  }) async {
    calls++;
    events?.add('asr');
    if (fail) throw const SpeechCloudException('asr failure');
    return results[calls - 1];
  }

  @override
  void dispose() {}
}

class _FakeTts extends DoubaoTtsClient {
  _FakeTts({this.fail = false, this.badPcm = false, this.events});
  final bool fail;
  final bool badPcm;
  final List<String>? events;
  int calls = 0;
  final List<String> texts = [];
  void Function(String)? onText;

  @override
  Future<Uint8List> synthesize({
    required String text,
    required String apiKey,
  }) async {
    calls++;
    events?.add('tts');
    texts.add(text);
    onText?.call(text);
    if (fail) throw const SpeechCloudException('tts failure');
    return _pcm(4800, badPcm ? 32767 : 1000);
  }

  @override
  void dispose() {}
}

Uint8List _pcm(int length, int amplitude) {
  final pcm = Uint8List(length);
  final data = ByteData.sublistView(pcm);
  for (var offset = 0; offset < pcm.length; offset += 2) {
    data.setInt16(offset, amplitude, Endian.little);
  }
  return pcm;
}

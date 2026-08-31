import 'dart:async';
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
    esp32Host: 'device.local',
    requestKey: 'device-key',
    volcengineApiKey: 'speech-key',
    characterId: 'character-id',
  );

  test(
    'second completed turn receives the first turn as transient context',
    () async {
      final device = _Device();
      final asr = _Asr(['我刚买了个蛋糕。', '草莓的。']);
      final tts = _Tts();
      final contexts = <List<ChatMessage>>[];
      final controller = PhysicalSessionController(
        device: device,
        asr: asr,
        tts: tts,
        coreReply: (_, userText, transient) async {
          contexts.add(List.of(transient));
          return userText.startsWith('我刚') ? '什么味的？' : '草莓蛋糕不错。';
        },
        modelConfigured: () async => true,
      );
      addTearDown(controller.dispose);

      await controller.check(settings);
      await controller.record(settings);
      await controller.continueConversation(settings);
      expect(controller.stage, PhysicalSessionStage.ready);
      expect(controller.turnCount, 1);

      await controller.record(settings);
      await controller.continueConversation(settings);

      expect(contexts.first, isEmpty);
      expect(contexts.last.map((item) => item.content), ['我刚买了个蛋糕。', '什么味的？']);
      expect(controller.turnCount, 2);
      expect(device.playCalls, 2);
      expect(asr.calls, 2);
      expect(tts.calls, 2);

      controller.clearSession();
      expect(controller.turns, isEmpty);
      expect(controller.turnCount, 0);
    },
  );

  test(
    'a completed operation appends exactly once and duplicate taps do nothing',
    () async {
      final device = _Device();
      final asr = _Asr(['第一轮']);
      final tts = _Tts();
      final coreGate = Completer<void>();
      var coreCalls = 0;
      final controller = PhysicalSessionController(
        device: device,
        asr: asr,
        tts: tts,
        coreReply: (_, _, _) async {
          coreCalls++;
          await coreGate.future;
          return '回复';
        },
        modelConfigured: () async => true,
      );
      addTearDown(controller.dispose);
      await controller.check(settings);
      await controller.record(settings);

      final first = controller.continueConversation(settings);
      final duplicate = controller.continueConversation(settings);
      await Future<void>.delayed(Duration.zero);
      coreGate.complete();
      await Future.wait([first, duplicate]);

      expect(asr.calls, 1);
      expect(coreCalls, 1);
      expect(tts.calls, 1);
      expect(device.playCalls, 1);
      expect(controller.turnCount, 1);
    },
  );

  test('core, TTS, and playback failures never append a turn', () async {
    for (final failure in ['core', 'tts', 'play']) {
      final device = _Device(failPlay: failure == 'play');
      final asr = _Asr(['用户消息']);
      final tts = _Tts(fail: failure == 'tts');
      final controller = PhysicalSessionController(
        device: device,
        asr: asr,
        tts: tts,
        coreReply: (_, _, _) async {
          if (failure == 'core') throw StateError('core failure');
          return '回复';
        },
        modelConfigured: () async => true,
      );
      await controller.check(settings);
      await controller.record(settings);
      await controller.continueConversation(settings);
      expect(
        controller.stage,
        failure == 'play'
            ? PhysicalSessionStage.error
            : PhysicalSessionStage.ready,
        reason: failure,
      );
      expect(controller.canRecord, failure != 'play', reason: failure);
      expect(controller.deviceReady, failure != 'play', reason: failure);
      expect(controller.turnCount, 0, reason: failure);
      controller.dispose();
    }
  });

  test('ASR failure returns to ready without retrying or appending', () async {
    final asr = _Asr(const [], fail: true);
    final controller = PhysicalSessionController(
      device: _Device(),
      asr: asr,
      tts: _Tts(),
      coreReply: (_, _, _) async => '不应调用',
      modelConfigured: () async => true,
    );
    addTearDown(controller.dispose);
    await controller.check(settings);
    await controller.record(settings);
    await controller.continueConversation(settings);

    expect(asr.calls, 1);
    expect(controller.stage, PhysicalSessionStage.ready);
    expect(controller.canRecord, isTrue);
    expect(controller.turnCount, 0);
  });

  test('record communication failure requires a new status check', () async {
    final device = _Device(failRecord: true);
    final controller = PhysicalSessionController(
      device: device,
      asr: _Asr(['不应调用']),
      tts: _Tts(),
      coreReply: (_, _, _) async => '不应调用',
      modelConfigured: () async => true,
    );
    addTearDown(controller.dispose);
    await controller.check(settings);
    await controller.record(settings);

    expect(controller.stage, PhysicalSessionStage.error);
    expect(controller.deviceReady, isFalse);
    expect(controller.canRecord, isFalse);
    expect(controller.turnCount, 0);

    device.failRecord = false;
    await controller.check(settings);
    expect(controller.deviceReady, isTrue);
    expect(controller.canRecord, isTrue);
  });

  test('invalid recording returns to ready and never appends a turn', () async {
    final controller = PhysicalSessionController(
      device: _Device(invalidRecord: true),
      asr: _Asr(['不应调用']),
      tts: _Tts(),
      coreReply: (_, _, _) async => '不应调用',
      modelConfigured: () async => true,
    );
    addTearDown(controller.dispose);
    await controller.check(settings);
    await controller.record(settings);

    expect(controller.stage, PhysicalSessionStage.ready);
    expect(controller.deviceReady, isTrue);
    expect(controller.canRecord, isTrue);
    expect(controller.turnCount, 0);
  });

  test('character switch clears only the physical session turns', () async {
    final controller = PhysicalSessionController(
      device: _Device(),
      asr: _Asr(['第一角色消息']),
      tts: _Tts(),
      coreReply: (_, _, _) async => '第一角色回复',
      modelConfigured: () async => true,
    );
    addTearDown(controller.dispose);
    controller.selectCharacter('pei-jian-che');
    await controller.check(settings);
    await controller.record(settings);
    await controller.continueConversation(settings);
    expect(controller.turnCount, 1);

    controller.selectCharacter('another-character');
    expect(controller.turnCount, 0);
  });

  test('busy operation prevents clearing or switching the session', () async {
    final device = _Device();
    final controller = PhysicalSessionController(
      device: device,
      asr: _Asr(['消息']),
      tts: _Tts(),
      coreReply: (_, _, _) async => '回复',
      modelConfigured: () async => true,
    );
    addTearDown(controller.dispose);
    controller.selectCharacter('first');
    await controller.check(settings);
    await controller.record(settings);
    await controller.continueConversation(settings);
    expect(controller.turnCount, 1);

    device.statusGate = Completer<void>();
    final checking = controller.check(settings);
    controller.clearSession();
    controller.selectCharacter('second');
    expect(controller.turnCount, 1);
    device.statusGate!.complete();
    await checking;
    expect(controller.turnCount, 1);
  });

  test('debug Stage C D and E actions do not append session turns', () async {
    final controller = PhysicalSessionController(
      device: _Device(),
      asr: _Asr(['调试消息']),
      tts: _Tts(),
      coreReply: (_, _, _) async => '调试回复',
      modelConfigured: () async => true,
    );
    addTearDown(controller.dispose);
    await controller.check(settings);
    await controller.record(settings);
    await controller.recognizeOnly(settings);
    await controller.replyOnly(settings);
    await controller.synthesizeOnly(settings, text: '调试语音');
    expect(controller.turnCount, 0);
  });

  test(
    'new recording clears stale TTS review without clearing completed turns',
    () async {
      final controller = PhysicalSessionController(
        device: _Device(),
        asr: _Asr(['消息']),
        tts: _Tts(),
        coreReply: (_, _, _) async => '回复',
        modelConfigured: () async => true,
      );
      addTearDown(controller.dispose);
      await controller.check(settings);
      await controller.synthesizeOnly(settings, text: '旧调试语音');
      expect(controller.ttsReview, isNotNull);
      await controller.check(settings);
      await controller.record(settings);
      expect(controller.ttsReview, isNull);
    },
  );

  test(
    'replyOnly locks before its asynchronous model configuration check',
    () async {
      final modelGate = Completer<void>();
      var modelChecks = 0;
      var coreCalls = 0;
      final controller = PhysicalSessionController(
        device: _Device(),
        asr: _Asr(['消息']),
        tts: _Tts(),
        coreReply: (_, _, _) async {
          coreCalls++;
          return '回复';
        },
        modelConfigured: () async {
          modelChecks++;
          await modelGate.future;
          return true;
        },
      );
      addTearDown(controller.dispose);
      await controller.check(settings);
      await controller.record(settings);
      await controller.recognizeOnly(settings);

      final first = controller.replyOnly(settings);
      final duplicate = controller.replyOnly(settings);
      modelGate.complete();
      await Future.wait([first, duplicate]);

      expect(modelChecks, 1);
      expect(coreCalls, 1);
    },
  );
}

class _Device extends Esp32PhysicalClient {
  _Device({
    this.failPlay = false,
    this.failRecord = false,
    this.invalidRecord = false,
  });
  final bool failPlay;
  bool failRecord;
  final bool invalidRecord;
  Completer<void>? statusGate;
  int playCalls = 0;

  @override
  Future<Esp32Status> status({
    required String host,
    required String key,
  }) async {
    await statusGate?.future;
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
    if (failRecord) throw const PhysicalProtocolException('record failure');
    if (invalidRecord) {
      throw const PhysicalInvalidRecordingException('invalid recording');
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
    if (failPlay) throw const PhysicalProtocolException('play failure');
  }

  @override
  void dispose() {}
}

class _Asr extends DoubaoAsrClient {
  _Asr(this.results, {this.fail = false});
  final List<String> results;
  final bool fail;
  int calls = 0;

  @override
  Future<String> transcribe({
    required Uint8List pcm,
    required String apiKey,
    String boostingTableId = '',
  }) async {
    calls++;
    if (fail) throw const SpeechCloudException('asr failure');
    return results[calls - 1];
  }

  @override
  void dispose() {}
}

class _Tts extends DoubaoTtsClient {
  _Tts({this.fail = false});
  final bool fail;
  int calls = 0;

  @override
  Future<Uint8List> synthesize({
    required String text,
    required String apiKey,
  }) async {
    calls++;
    if (fail) throw const SpeechCloudException('tts failure');
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

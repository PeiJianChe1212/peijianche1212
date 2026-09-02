import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/physical/doubao_speech_clients.dart';
import 'package:peijianche_app/physical/esp32_physical_client.dart';
import 'package:peijianche_app/physical/pcm_audio_codec.dart';
import 'package:peijianche_app/physical/physical_host_settings.dart';
import 'package:peijianche_app/physical/physical_session_controller.dart';

void main() {
  test(
    'recognizeOnly stops after formal ASR and preserves review capture',
    () async {
      final device = _FakeDevice();
      final asr = _FakeAsr();
      final tts = _FakeTts();
      var coreCalls = 0;
      final controller = PhysicalSessionController(
        device: device,
        asr: asr,
        tts: tts,
        coreReply: (_, _, _) async {
          coreCalls++;
          return '（轻笑）行，测吧。<|PEILINK_MSG|>一二三四五。';
        },
        modelConfigured: () async => true,
      );
      addTearDown(controller.dispose);
      const settings = PhysicalHostSettings(
        esp32Host: '192.168.2.215',
        requestKey: 'device-key',
        volcengineApiKey: 'speech-key',
        characterId: 'character-id',
      );

      await controller.check(settings);
      await controller.record(settings);
      expect(controller.canRecognizeOnly, isTrue);

      await controller.recognizeOnly(settings);

      expect(asr.calls, 1);
      expect(controller.transcript, '测试测试，裴实体化第一次录音。');
      expect(controller.message, 'ASR 识别完成，已停止在 Stage C');
      expect(controller.canContinue, isTrue);
      expect(controller.canRecognizeOnly, isFalse);
      expect(coreCalls, 0);
      expect(tts.calls, 0);
      expect(device.playCalls, 0);

      await controller.replyOnly(settings);

      expect(coreCalls, 1);
      expect(controller.spokenReply, '行，测吧。\n一二三四五。');
      expect(controller.message, 'Core 回复完成，已停止在 Stage D');
      expect(controller.canContinue, isTrue);
      expect(controller.canReplyOnly, isFalse);
      expect(asr.calls, 1);
      expect(tts.calls, 0);
      expect(device.playCalls, 0);

      await controller.synthesizeOnly(settings, text: '你这是在给录音设备报数，还是在测试我听力？');

      expect(tts.calls, 1);
      expect(controller.message, 'TTS 数据验收完成，已停止在 Stage E');
      expect(controller.ttsReview, isNotNull);
      expect(controller.ttsReview!.pcm.length, 3200);
      expect(controller.ttsReview!.stats.isEffectivelySilent, isFalse);
      expect(controller.ttsReview!.stats.hasExcessiveClipping, isFalse);
      expect(device.playCalls, 0);

      await controller.playReviewedOnly(settings);

      expect(tts.calls, 1);
      expect(device.playCalls, 1);
      expect(controller.message, 'Stage F 单次播放完成');
    },
  );
}

class _FakeDevice extends Esp32PhysicalClient {
  int playCalls = 0;

  @override
  Future<Esp32Status> status({
    required String host,
    required String key,
  }) async => const Esp32Status(
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

  @override
  Future<PhysicalCapture> record({
    required String host,
    required String key,
  }) async {
    final pcm = Uint8List(PcmAudioCodec.recordBytes);
    final samples = ByteData.sublistView(pcm);
    for (var offset = 0; offset < pcm.length; offset += 2) {
      samples.setInt16(offset, 1000, Endian.little);
    }
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
  }

  @override
  void dispose() {}
}

class _FakeAsr extends DoubaoAsrClient {
  int calls = 0;

  @override
  Future<String> transcribe({
    required Uint8List pcm,
    required String apiKey,
    String boostingTableId = '',
    void Function(AsrTranscribeStats stats)? onStats,
  }) async {
    calls++;
    expect(pcm.length, PcmAudioCodec.recordBytes);
    return '测试测试，裴实体化第一次录音。';
  }

  @override
  void dispose() {}
}

class _FakeTts extends DoubaoTtsClient {
  int calls = 0;

  @override
  Future<Uint8List> synthesize({
    required String text,
    required String apiKey,
  }) async {
    calls++;
    final pcm = Uint8List(4800);
    final data = ByteData.sublistView(pcm);
    for (var offset = 0; offset < pcm.length; offset += 2) {
      data.setInt16(offset, 1000, Endian.little);
    }
    return pcm;
  }

  @override
  void dispose() {}
}

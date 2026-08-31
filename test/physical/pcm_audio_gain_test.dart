import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/physical/pcm_audio_codec.dart';
import 'package:peijianche_app/physical/pcm_audio_gain.dart';

/// 生成指定 RMS 和 Peak 的正弦波 PCM 数据。
Uint8List _generateSinePcm({
  required int samples,
  required double rms,
  int frequency = 440,
  int sampleRate = 16000,
}) {
  final pcm = Uint8List(samples * 2);
  final data = ByteData.sublistView(pcm);
  // 正弦波 RMS = amplitude / sqrt(2)，所以 amplitude = RMS * sqrt(2)
  final amplitude = (rms * math.sqrt2).round();
  for (var i = 0; i < samples; i++) {
    final sample =
        (amplitude * math.sin(2 * math.pi * frequency * i / sampleRate))
            .round()
            .clamp(-32768, 32767);
    data.setInt16(i * 2, sample, Endian.little);
  }
  return pcm;
}

/// 生成全零 PCM（静音）。
Uint8List _generateSilencePcm(int samples) {
  return Uint8List(samples * 2);
}

/// 生成接近满量程的高电平 PCM。
Uint8List _generateLoudPcm({
  required int samples,
  double amplitudeRatio = 0.9,
  int frequency = 440,
  int sampleRate = 16000,
}) {
  final pcm = Uint8List(samples * 2);
  final data = ByteData.sublistView(pcm);
  final amplitude = (32767 * amplitudeRatio).round();
  for (var i = 0; i < samples; i++) {
    final sample =
        (amplitude * math.sin(2 * math.pi * frequency * i / sampleRate))
            .round();
    data.setInt16(i * 2, sample, Endian.little);
  }
  return pcm;
}

void main() {
  group('PcmAudioGain 自适应增益', () {
    const testSamples = 16000; // 1 秒 @ 16kHz

    test('低电平样本被提升', () {
      // RMS ≈ 300（低于 minRmsThreshold=500）
      final pcm = _generateSinePcm(samples: testSamples, rms: 300);
      final inputStats = PcmAudioCodec.stats(pcm);

      final result = PcmAudioGain.applyAdaptiveGain(pcm);

      expect(result.appliedGain, greaterThan(1.0));
      expect(result.outputStats.rms, greaterThan(inputStats.rms));
      expect(result.outputStats.peak, greaterThan(inputStats.peak));
      expect(result.reason, GainReason.lowLevelBoosted);
      // 目标 RMS 约为 1000
      expect(result.outputStats.rms, closeTo(1000, 200));
    });

    test('中等电平样本适度提升', () {
      // RMS ≈ 700（在 500~1500 之间）
      final pcm = _generateSinePcm(samples: testSamples, rms: 700);
      final inputStats = PcmAudioCodec.stats(pcm);

      final result = PcmAudioGain.applyAdaptiveGain(pcm);

      expect(result.appliedGain, greaterThan(1.0));
      expect(result.appliedGain, lessThan(2.0));
      expect(result.outputStats.rms, greaterThan(inputStats.rms));
      expect(result.reason, GainReason.mediumLevelAdjusted);
    });

    test('高电平样本不提升', () {
      // RMS ≈ 2000（高于 maxRmsThreshold=1500）
      final pcm = _generateSinePcm(samples: testSamples, rms: 2000);
      final inputStats = PcmAudioCodec.stats(pcm);

      final result = PcmAudioGain.applyAdaptiveGain(pcm);

      expect(result.appliedGain, closeTo(1.0, 0.001));
      expect(result.outputStats.rms, closeTo(inputStats.rms, 0.1));
      expect(result.outputStats.peak, equals(inputStats.peak));
      expect(result.reason, GainReason.alreadyLoudEnough);
    });

    test('全零静音不增益', () {
      final pcm = _generateSilencePcm(testSamples);

      final result = PcmAudioGain.applyAdaptiveGain(pcm);

      expect(result.appliedGain, equals(1.0));
      expect(result.outputStats.rms, equals(0.0));
      expect(result.outputStats.peak, equals(0));
      expect(result.reason, GainReason.silenceNoGain);
    });

    test('近静音不被无限放大', () {
      // RMS ≈ 3（低于 silenceRmsThreshold=5）
      final pcm = _generateSinePcm(samples: testSamples, rms: 3);

      final result = PcmAudioGain.applyAdaptiveGain(pcm);

      expect(result.appliedGain, equals(1.0));
      expect(result.reason, GainReason.silenceNoGain);
      // 输出不应被放大到满量程
      expect(result.outputStats.peak, lessThan(100));
    });

    test('最大增益限制', () {
      // RMS ≈ 50（极低电平，理论增益 = 1000/50 = 20，但应被限制为 5）
      final pcm = _generateSinePcm(samples: testSamples, rms: 50);

      final result = PcmAudioGain.applyAdaptiveGain(pcm);

      expect(result.appliedGain, lessThanOrEqualTo(PcmAudioGain.maxGain));
      expect(result.appliedGain, closeTo(PcmAudioGain.maxGain, 0.1));
    });

    test('无严重削波', () {
      // RMS ≈ 400（接近 minRmsThreshold，增益约 2.5）
      final pcm = _generateSinePcm(samples: testSamples, rms: 400);

      final result = PcmAudioGain.applyAdaptiveGain(pcm);

      expect(result.hasExcessiveClipping, isFalse);
      expect(result.clippingRatio, lessThanOrEqualTo(PcmAudioGain.maxClippingRatio));
    });

    test('Peak 保护防止削波', () {
      // 生成 Peak 很高但 RMS 较低的信号（突发峰值）
      final pcm = Uint8List(testSamples * 2);
      final data = ByteData.sublistView(pcm);
      for (var i = 0; i < testSamples; i++) {
        // 大部分时间低电平，偶发高峰值
        final sample = i % 100 == 0 ? 15000 : 100;
        data.setInt16(i * 2, sample, Endian.little);
      }

      final result = PcmAudioGain.applyAdaptiveGain(pcm);

      // 输出 Peak 不应超过 targetPeak 太多
      expect(result.outputStats.peak, lessThanOrEqualTo(PcmAudioGain.targetPeak + 100));
      expect(result.hasExcessiveClipping, isFalse);
    });

    test('原始 PCM bytes 不发生修改', () {
      final pcm = _generateSinePcm(samples: testSamples, rms: 300);
      final originalBytes = Uint8List.fromList(pcm);

      PcmAudioGain.applyAdaptiveGain(pcm);

      // 原始数据应完全不变
      expect(pcm, equals(originalBytes));
    });

    test('输出仍为 PCM16 mono', () {
      final pcm = _generateSinePcm(samples: testSamples, rms: 300);

      final result = PcmAudioGain.applyAdaptiveGain(pcm);

      // 输出长度应与输入相同（16-bit mono）
      expect(result.output.length, equals(pcm.length));
      expect(result.output.length.isEven, isTrue);
      // 输出应为有效 PCM（可通过 validatePcm）
      expect(() => PcmAudioCodec.validatePcm(result.output), returnsNormally);
    });

    test('输出字节数与输入一致', () {
      final pcm = _generateSinePcm(samples: testSamples, rms: 500);

      final result = PcmAudioGain.applyAdaptiveGain(pcm);

      expect(result.output.lengthInBytes, equals(pcm.lengthInBytes));
    });
  });

  group('三个历史样本模拟验证', () {
    const testSamples = 128000; // 8 秒 @ 16kHz

    test('失败样本（RMS≈328, Peak≈3196）被提升到目标范围', () {
      // 模拟失败样本电平
      final pcm = _generateSinePcm(samples: testSamples, rms: 328);

      final result = PcmAudioGain.applyAdaptiveGain(pcm);

      expect(result.appliedGain, greaterThan(2.0));
      expect(result.outputStats.rms, greaterThan(800));
      expect(result.outputStats.rms, lessThan(1500));
      expect(result.clipped, equals(0));
      expect(result.reason, GainReason.lowLevelBoosted);
    });

    test('A方向样本（RMS≈668, Peak≈5917）适度提升', () {
      final pcm = _generateSinePcm(samples: testSamples, rms: 668);
      final inputStats = PcmAudioCodec.stats(pcm);

      final result = PcmAudioGain.applyAdaptiveGain(pcm);

      expect(result.appliedGain, greaterThan(1.0));
      expect(result.appliedGain, lessThan(2.5));
      expect(result.outputStats.rms, greaterThan(inputStats.rms));
      expect(result.clipped, equals(0));
      expect(result.reason, GainReason.mediumLevelAdjusted);
    });

    test('历史成功样本（RMS≈1970, Peak≈30989）不提升', () {
      // 用高电平正弦波模拟（实际 RMS 会略低于目标，但足够测试高电平分支）
      final pcm = _generateLoudPcm(samples: testSamples, amplitudeRatio: 0.9);
      final inputStats = PcmAudioCodec.stats(pcm);

      final result = PcmAudioGain.applyAdaptiveGain(pcm);

      expect(result.appliedGain, closeTo(1.0, 0.001));
      expect(result.outputStats.rms, closeTo(inputStats.rms, 0.1));
      expect(result.reason, GainReason.alreadyLoudEnough);
    });
  });

  group('GainResult 属性', () {
    test('clippingRatio 计算正确', () {
      final pcm = _generateSinePcm(samples: 16000, rms: 300);
      final result = PcmAudioGain.applyAdaptiveGain(pcm);

      expect(result.clippingRatio, equals(result.clipped / result.outputStats.samples));
    });

    test('hasExcessiveClipping 判断正确', () {
      final pcm = _generateSinePcm(samples: 16000, rms: 300);
      final result = PcmAudioGain.applyAdaptiveGain(pcm);

      // 正常低电平增益不应有严重削波
      expect(result.hasExcessiveClipping, isFalse);
    });
  });

  group('边界条件测试', () {
    test('极低噪声不会被放大成假语音', () {
      // RMS ≈ 2，Peak ≈ 10（远低于静音阈值）
      final pcm = _generateSinePcm(samples: 16000, rms: 2);

      final result = PcmAudioGain.applyAdaptiveGain(pcm);

      expect(result.appliedGain, equals(1.0));
      expect(result.reason, GainReason.silenceNoGain);
      expect(result.outputStats.peak, lessThan(100));
      expect(result.output, equals(pcm));
    });

    test('短瞬态大 Peak + 低 RMS 时不会因 Peak 完全禁止合理增益', () {
      // 构造：大部分样本低电平，偶发一个大 Peak
      final pcm = Uint8List(16000 * 2);
      final data = ByteData.sublistView(pcm);
      for (var i = 0; i < 16000; i++) {
        // 每 1000 个样本出现一个大峰值，其余为低电平
        final sample = i % 1000 == 0 ? 15000 : 200;
        data.setInt16(i * 2, sample, Endian.little);
      }

      final result = PcmAudioGain.applyAdaptiveGain(pcm);

      // RMS 低（约 200*sqrt(2)≈283），应被增益
      expect(result.appliedGain, greaterThan(1.0));
      // 但 Peak 保护会限制增益，使输出 Peak 不超过 targetPeak 太多
      expect(result.outputStats.peak, lessThanOrEqualTo(PcmAudioGain.targetPeak + 100));
      expect(result.hasExcessiveClipping, isFalse);
    });

    test('输入接近满量程时保持原样', () {
      // amplitudeRatio = 0.95，Peak ≈ 31128，RMS ≈ 22000
      final pcm = _generateLoudPcm(samples: 16000, amplitudeRatio: 0.95);
      final inputStats = PcmAudioCodec.stats(pcm);

      final result = PcmAudioGain.applyAdaptiveGain(pcm);

      expect(result.appliedGain, closeTo(1.0, 0.001));
      expect(result.outputStats.peak, equals(inputStats.peak));
      expect(result.outputStats.rms, closeTo(inputStats.rms, 0.1));
      expect(result.reason, GainReason.alreadyLoudEnough);
    });

    test('正负极值边界 -32768 / 32767 不溢出', () {
      // 构造包含极值的 PCM
      final pcm = Uint8List(4 * 2); // 4 个样本
      final data = ByteData.sublistView(pcm);
      data.setInt16(0, 32767, Endian.little);
      data.setInt16(2, -32768, Endian.little);
      data.setInt16(4, 0, Endian.little);
      data.setInt16(6, 100, Endian.little);

      // 低电平增益（RMS 低，但有大 Peak）
      final result = PcmAudioGain.applyAdaptiveGain(pcm);

      // 输出不应溢出 int16 范围
      final outputData = ByteData.sublistView(result.output);
      for (var i = 0; i < result.output.length; i += 2) {
        final sample = outputData.getInt16(i, Endian.little);
        expect(sample, greaterThanOrEqualTo(-32768));
        expect(sample, lessThanOrEqualTo(32767));
      }
    });

    test('奇数字节输入抛出 FormatException', () {
      final oddPcm = Uint8List(3); // 3 字节，奇数

      expect(
        () => PcmAudioGain.applyAdaptiveGain(oddPcm),
        throwsA(isA<FormatException>()),
      );
    });

    test('空输入抛出 FormatException', () {
      final emptyPcm = Uint8List(0);

      expect(
        () => PcmAudioGain.applyAdaptiveGain(emptyPcm),
        throwsA(isA<FormatException>()),
      );
    });

    test('原始输入 Uint8List 不发生 mutation', () {
      final pcm = _generateSinePcm(samples: 16000, rms: 300);
      final originalBytes = Uint8List.fromList(pcm);

      PcmAudioGain.applyAdaptiveGain(pcm);

      // 原始数据应完全不变
      expect(pcm, equals(originalBytes));
    });

    test('同一输入重复处理结果稳定（幂等性）', () {
      final pcm = _generateSinePcm(samples: 16000, rms: 400);

      final result1 = PcmAudioGain.applyAdaptiveGain(pcm);
      final result2 = PcmAudioGain.applyAdaptiveGain(pcm);

      expect(result1.appliedGain, equals(result2.appliedGain));
      expect(result1.output, equals(result2.output));
      expect(result1.clipped, equals(result2.clipped));
      expect(result1.reason, equals(result2.reason));
    });

    test('增益后输出长度与输入一致', () {
      final pcm = _generateSinePcm(samples: 16000, rms: 300);

      final result = PcmAudioGain.applyAdaptiveGain(pcm);

      expect(result.output.length, equals(pcm.length));
      expect(result.output.lengthInBytes, equals(pcm.lengthInBytes));
    });

    test('静音输入返回原始数据副本而非同一引用', () {
      final pcm = _generateSilencePcm(16000);

      final result = PcmAudioGain.applyAdaptiveGain(pcm);

      expect(result.output, equals(pcm));
      expect(identical(result.output, pcm), isFalse); // 是副本，不是同一引用
    });
  });
}

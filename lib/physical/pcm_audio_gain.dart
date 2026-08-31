import 'dart:typed_data';

import 'pcm_audio_codec.dart';

/// ASR 上传前的自适应增益处理。
///
/// 设计原则：
/// - 仅生成用于 ASR 上传的处理副本，原始 ESP32 PCM 完全不变
/// - 使用 RMS 作为主要电平判断，Peak 作为削波保护
/// - 低电平语音自动适度提升，已经足够大的录音不增益
/// - 静音/近静音不增益，避免放大背景噪声
/// - 最大增益安全上限，防止过度放大
/// - 安全限幅，不允许明显削波
/// - 不影响 TTS 和 /audio 播放链
abstract final class PcmAudioGain {
  /// RMS 低于此值时需要明显增益。
  static const double minRmsThreshold = 500.0;

  /// 增益目标 RMS。
  static const double targetRms = 1000.0;

  /// RMS 高于此值时不增益。
  static const double maxRmsThreshold = 1500.0;

  /// 增益后目标 Peak（约 55% 满量程，留有足够余量）。
  static const int targetPeak = 18000;

  /// 最大允许增益（×5）。
  static const double maxGain = 5.0;

  /// 最小增益（不衰减）。
  static const double minGain = 1.0;

  /// 静音 RMS 阈值，低于此值不增益。
  static const double silenceRmsThreshold = 5.0;

  /// 静音 Peak 阈值，低于此值不增益。
  static const int silencePeakThreshold = 20;

  /// 最大允许削波比例（0.1%）。
  static const double maxClippingRatio = 0.001;

  /// 削波超标时的增益缩减比例。
  static const double clippingGainReduction = 0.8;

  /// 削波超标时的最大重试次数。
  static const int maxClippingRetries = 2;

  /// 对 PCM 数据应用自适应增益，返回处理结果。
  ///
  /// 不修改原始 [pcm]，返回新的 Uint8List 副本。
  static GainResult applyAdaptiveGain(Uint8List pcm) {
    PcmAudioCodec.validatePcm(pcm, maximum: PcmAudioCodec.maxPlaybackBytes * 3 ~/ 2);

    final inputStats = PcmAudioCodec.stats(pcm);

    // 静音/近静音不增益，避免放大背景噪声
    if (inputStats.rms < silenceRmsThreshold ||
        inputStats.peak < silencePeakThreshold) {
      return GainResult(
        output: Uint8List.fromList(pcm),
        appliedGain: 1.0,
        inputStats: inputStats,
        outputStats: inputStats,
        clipped: 0,
        reason: GainReason.silenceNoGain,
      );
    }

    var gain = _calculateBaseGain(inputStats.rms);
    gain = gain.clamp(minGain, maxGain);

    // Peak 保护：仅在需要增益（gain > 1.0）时检查，
    // 不衰减已经足够大的信号
    if (gain > 1.0) {
      final expectedPeak = inputStats.peak * gain;
      if (expectedPeak > targetPeak) {
        gain = targetPeak / inputStats.peak;
      }
    }

    // 应用增益，必要时因削波重试
    var retries = 0;
    while (true) {
      final result = _applyGainWithClipping(pcm, gain);
      final clippingRatio = result.clipped / inputStats.samples;

      if (clippingRatio <= maxClippingRatio || retries >= maxClippingRetries) {
        return GainResult(
          output: result.output,
          appliedGain: gain,
          inputStats: inputStats,
          outputStats: PcmAudioCodec.stats(result.output),
          clipped: result.clipped,
          reason: _determineReason(inputStats, gain),
        );
      }

      // 削波超标，降低增益重试
      gain *= clippingGainReduction;
      retries++;
    }
  }

  /// 根据 RMS 计算基础增益。
  static double _calculateBaseGain(double inputRms) {
    if (inputRms < minRmsThreshold) {
      return targetRms / inputRms;
    }
    if (inputRms < maxRmsThreshold) {
      // 平滑过渡：从 minRmsThreshold 时的增益渐变到 maxRmsThreshold 时的 1.0
      final t = (inputRms - minRmsThreshold) /
          (maxRmsThreshold - minRmsThreshold);
      final gainAtMin = targetRms / minRmsThreshold;
      return gainAtMin + (minGain - gainAtMin) * t;
    }
    return minGain;
  }

  /// 应用增益并统计削波。
  static _GainApplication _applyGainWithClipping(Uint8List pcm, double gain) {
    final output = Uint8List(pcm.length);
    final outputData = ByteData.sublistView(output);
    final inputData = ByteData.sublistView(pcm);
    var clipped = 0;

    for (var offset = 0; offset < pcm.length; offset += 2) {
      final sample = inputData.getInt16(offset, Endian.little);
      final scaled = (sample * gain).round();
      if (scaled > 32767) {
        outputData.setInt16(offset, 32767, Endian.little);
        clipped++;
      } else if (scaled < -32768) {
        outputData.setInt16(offset, -32768, Endian.little);
        clipped++;
      } else {
        outputData.setInt16(offset, scaled, Endian.little);
      }
    }

    return _GainApplication(output: output, clipped: clipped);
  }

  /// 确定增益原因。
  static GainReason _determineReason(PcmStats inputStats, double gain) {
    if (gain <= minGain + 0.001) {
      return GainReason.alreadyLoudEnough;
    }
    if (inputStats.rms < minRmsThreshold) {
      return GainReason.lowLevelBoosted;
    }
    return GainReason.mediumLevelAdjusted;
  }
}

/// 增益应用结果。
class GainResult {
  const GainResult({
    required this.output,
    required this.appliedGain,
    required this.inputStats,
    required this.outputStats,
    required this.clipped,
    required this.reason,
  });

  /// 处理后的 PCM 数据（新副本，不影响原始数据）。
  final Uint8List output;

  /// 实际应用的增益倍数。
  final double appliedGain;

  /// 输入 PCM 统计。
  final PcmStats inputStats;

  /// 输出 PCM 统计。
  final PcmStats outputStats;

  /// 削波样本数。
  final int clipped;

  /// 增益原因。
  final GainReason reason;

  /// 削波比例。
  double get clippingRatio =>
      outputStats.samples == 0 ? 0 : clipped / outputStats.samples;

  /// 是否有明显削波（超过 0.1%）。
  bool get hasExcessiveClipping =>
      clippingRatio > PcmAudioGain.maxClippingRatio;
}

/// 增益原因枚举。
enum GainReason {
  /// 静音/近静音，不增益。
  silenceNoGain,

  /// 低电平，已提升。
  lowLevelBoosted,

  /// 中等电平，适度调整。
  mediumLevelAdjusted,

  /// 已经足够大，不增益。
  alreadyLoudEnough,
}

class _GainApplication {
  const _GainApplication({required this.output, required this.clipped});

  final Uint8List output;
  final int clipped;
}

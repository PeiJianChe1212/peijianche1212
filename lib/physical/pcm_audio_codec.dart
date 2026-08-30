import 'dart:math' as math;
import 'dart:typed_data';

abstract final class PcmAudioCodec {
  static const sampleRate = 16000;
  static const providerSampleRate = 24000;
  static const bits = 16;
  static const channels = 1;
  static const recordSeconds = 8;
  static const recordBytes = sampleRate * recordSeconds * 2;
  static const maxPlaybackBytes = 1024 * 1024;

  static int crc32(List<int> bytes) {
    var crc = 0xffffffff;
    for (final byte in bytes) {
      crc ^= byte;
      for (var bit = 0; bit < 8; bit++) {
        crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xedb88320 : crc >> 1;
      }
    }
    return (crc ^ 0xffffffff) & 0xffffffff;
  }

  static Uint8List wavFromPcm(Uint8List pcm) {
    validatePcm(pcm, maximum: recordBytes);
    final result = Uint8List(44 + pcm.length);
    final data = ByteData.sublistView(result);
    void ascii(int offset, String value) {
      for (var i = 0; i < value.length; i++) {
        result[offset + i] = value.codeUnitAt(i);
      }
    }

    ascii(0, 'RIFF');
    data.setUint32(4, 36 + pcm.length, Endian.little);
    ascii(8, 'WAVE');
    ascii(12, 'fmt ');
    data.setUint32(16, 16, Endian.little);
    data.setUint16(20, 1, Endian.little);
    data.setUint16(22, channels, Endian.little);
    data.setUint32(24, sampleRate, Endian.little);
    data.setUint32(28, sampleRate * channels * bits ~/ 8, Endian.little);
    data.setUint16(32, channels * bits ~/ 8, Endian.little);
    data.setUint16(34, bits, Endian.little);
    ascii(36, 'data');
    data.setUint32(40, pcm.length, Endian.little);
    result.setRange(44, result.length, pcm);
    return result;
  }

  static void validatePcm(Uint8List pcm, {int maximum = maxPlaybackBytes}) {
    if (pcm.isEmpty || pcm.length > maximum || pcm.length.isOdd) {
      throw const FormatException('PCM 长度无效');
    }
    for (final signature in const ['RIFF', 'OggS', 'ID3', 'fLaC']) {
      if (pcm.length >= signature.length &&
          String.fromCharCodes(pcm.take(signature.length)) == signature) {
        throw const FormatException('音频不是裸 PCM');
      }
    }
  }

  static PcmStats stats(Uint8List pcm) {
    validatePcm(pcm, maximum: maxPlaybackBytes * 3 ~/ 2);
    final data = ByteData.sublistView(pcm);
    var peak = 0;
    var sumSquares = 0.0;
    var clipped = 0;
    for (var offset = 0; offset < pcm.length; offset += 2) {
      final sample = data.getInt16(offset, Endian.little);
      final absolute = sample == -32768 ? 32768 : sample.abs();
      peak = math.max(peak, absolute);
      sumSquares += sample * sample;
      if (absolute >= 32767) clipped++;
    }
    final count = pcm.length ~/ 2;
    return PcmStats(
      peak: peak,
      rms: math.sqrt(sumSquares / count),
      clipped: clipped,
      samples: count,
    );
  }

  static Uint8List resample24kTo16k(Uint8List pcm) {
    validatePcm(pcm, maximum: maxPlaybackBytes * 3 ~/ 2);
    final input = ByteData.sublistView(pcm);
    final source = List<int>.generate(
      pcm.length ~/ 2,
      (index) => input.getInt16(index * 2, Endian.little),
      growable: false,
    );
    final outputCount = source.length * sampleRate ~/ providerSampleRate;
    final result = Uint8List(outputCount * 2);
    final output = ByteData.sublistView(result);
    const radius = 16;
    const cutoff = 0.95 * sampleRate / providerSampleRate;
    for (var outputIndex = 0; outputIndex < outputCount; outputIndex++) {
      final position = outputIndex * providerSampleRate / sampleRate;
      final center = position.floor();
      var weighted = 0.0;
      var weights = 0.0;
      for (var index = center - radius + 1; index <= center + radius; index++) {
        if (index < 0 || index >= source.length) continue;
        final distance = position - index;
        final sinc = distance == 0
            ? cutoff
            : math.sin(math.pi * cutoff * distance) / (math.pi * distance);
        final window = 0.5 * (1 + math.cos(math.pi * distance / radius));
        final weight = sinc * window;
        weighted += source[index] * weight;
        weights += weight;
      }
      final value = (weights == 0 ? 0 : weighted / weights).round().clamp(
        -32768,
        32767,
      );
      output.setInt16(outputIndex * 2, value, Endian.little);
    }
    validatePcm(result);
    return result;
  }
}

class PcmStats {
  const PcmStats({
    required this.peak,
    required this.rms,
    required this.clipped,
    required this.samples,
  });
  final int peak;
  final double rms;
  final int clipped;
  final int samples;
  bool get isEffectivelySilent => rms < 5 || peak < 20;
  bool get hasExcessiveClipping => clipped > samples ~/ 100;
}

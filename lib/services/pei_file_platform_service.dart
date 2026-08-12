import 'package:flutter/services.dart';

class SelectedPeiFile {
  const SelectedPeiFile({required this.name, required this.bytes});
  final String name;
  final Uint8List bytes;
}

class PeiFilePlatformService {
  const PeiFilePlatformService();
  static const _channel = MethodChannel('peilink/pei_file');

  Future<SelectedPeiFile?> pickFile() async {
    final result = await _channel.invokeMapMethod<String, dynamic>('pick');
    if (result == null) return null;
    final bytes = result['bytes'];
    if (bytes is! Uint8List) throw const FormatException('无法读取选择的文件。');
    return SelectedPeiFile(
      name: result['name']?.toString() ?? '角色.pei',
      bytes: bytes,
    );
  }

  Future<bool> saveFile({
    required String suggestedName,
    required Uint8List bytes,
  }) async =>
      await _channel.invokeMethod<bool>('save', {
        'name': suggestedName,
        'bytes': bytes,
      }) ??
      false;
}

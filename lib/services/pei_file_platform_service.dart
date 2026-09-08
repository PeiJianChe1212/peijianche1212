import 'package:flutter/services.dart';

import '../platform/file_exchange/file_exchange.dart';

class SelectedPeiFile {
  const SelectedPeiFile({required this.name, required this.bytes});
  final String name;
  final Uint8List bytes;
}

class PeiFilePlatformService implements FileExchange {
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

  @override
  Future<ExchangedFile?> pick() async {
    final selected = await pickFile();
    return selected == null
        ? null
        : ExchangedFile(name: selected.name, bytes: selected.bytes);
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

  @override
  Future<bool> save({
    required String suggestedName,
    required Uint8List bytes,
  }) => saveFile(suggestedName: suggestedName, bytes: bytes);
}

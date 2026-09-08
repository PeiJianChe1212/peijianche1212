import 'dart:typed_data';

class ExchangedFile {
  const ExchangedFile({required this.name, required this.bytes});
  final String name;
  final Uint8List bytes;
}

abstract interface class FileExchange {
  Future<ExchangedFile?> pick();
  Future<bool> save({required String suggestedName, required Uint8List bytes});
}

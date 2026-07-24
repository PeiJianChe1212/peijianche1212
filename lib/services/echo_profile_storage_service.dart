import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'character_scope_service.dart';

class EchoProfile {
  const EchoProfile({this.coverPath = ''});

  final String coverPath;

  EchoProfile copyWith({String? coverPath}) {
    return EchoProfile(coverPath: coverPath ?? this.coverPath);
  }

  Map<String, dynamic> toJson() => {'coverPath': coverPath};

  factory EchoProfile.fromJson(Map<dynamic, dynamic> json) {
    return EchoProfile(coverPath: json['coverPath']?.toString() ?? '');
  }
}

class EchoProfileStorageService {
  const EchoProfileStorageService({required this.ownerId});

  final String ownerId;

  Future<File> _profileFile() async {
    return CharacterScopeService(ownerId).dataFile('echo_profile.json');
  }

  Future<EchoProfile> loadProfile() async {
    final file = await _profileFile();
    if (!await file.exists()) return const EchoProfile();
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map) return EchoProfile.fromJson(decoded);
    } catch (_) {}
    return const EchoProfile();
  }

  Future<void> saveProfile(EchoProfile profile) async {
    final file = await _profileFile();
    await file.writeAsString(jsonEncode(profile.toJson()), flush: true);
  }

  Future<String> saveCoverCopy(String sourcePath) async {
    final source = File(sourcePath);
    if (!await source.exists()) throw StateError('选择的封面图片已经不存在。');

    final directory = await CharacterScopeService(ownerId).characterDirectory();
    final coverDirectory = Directory('${directory.path}/echo_cover');
    if (!await coverDirectory.exists()) {
      await coverDirectory.create(recursive: true);
    }

    final extension = _extensionOf(sourcePath);
    final target = File('${coverDirectory.path}/cover$extension');
    for (final file in coverDirectory.listSync().whereType<File>()) {
      if (file.path != target.path) {
        try {
          await file.delete();
        } catch (_) {}
      }
    }
    await source.copy(target.path);
    return target.path;
  }

  Future<String> saveCoverBytes(Uint8List bytes) async {
    final directory = await CharacterScopeService(ownerId).characterDirectory();
    final coverDirectory = Directory('${directory.path}/echo_cover');
    if (!await coverDirectory.exists()) {
      await coverDirectory.create(recursive: true);
    }

    for (final file in coverDirectory.listSync().whereType<File>()) {
      try {
        await file.delete();
      } catch (_) {}
    }

    final target = File('${coverDirectory.path}/cover.png');
    await target.writeAsBytes(bytes, flush: true);
    return target.path;
  }

  String _extensionOf(String path) {
    final dot = path.lastIndexOf('.');
    if (dot < 0 || dot == path.length - 1) return '.jpg';
    final extension = path.substring(dot).toLowerCase();
    return extension.length <= 6 ? extension : '.jpg';
  }
}

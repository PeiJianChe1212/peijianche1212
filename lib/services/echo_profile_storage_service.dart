import 'dart:convert';
import 'dart:io';

import 'character_scope_service.dart';

class EchoProfile {
  const EchoProfile({
    this.coverPath = '',
    this.signature = '',
    this.coverScale = 1,
    this.coverOffsetX = 0,
    this.coverOffsetY = 0,
  });

  final String coverPath;
  final String signature;
  final double coverScale;
  final double coverOffsetX;
  final double coverOffsetY;

  EchoProfile copyWith({
    String? coverPath,
    String? signature,
    double? coverScale,
    double? coverOffsetX,
    double? coverOffsetY,
  }) {
    return EchoProfile(
      coverPath: coverPath ?? this.coverPath,
      signature: signature ?? this.signature,
      coverScale: coverScale ?? this.coverScale,
      coverOffsetX: coverOffsetX ?? this.coverOffsetX,
      coverOffsetY: coverOffsetY ?? this.coverOffsetY,
    );
  }

  Map<String, dynamic> toJson() => {
    'coverPath': coverPath,
    'signature': signature,
    if (coverScale != 1) 'coverScale': coverScale,
    if (coverOffsetX != 0) 'coverOffsetX': coverOffsetX,
    if (coverOffsetY != 0) 'coverOffsetY': coverOffsetY,
  };

  factory EchoProfile.fromJson(Map<dynamic, dynamic> json) {
    return EchoProfile(
      coverPath: json['coverPath']?.toString() ?? '',
      signature: json['signature']?.toString() ?? '',
      coverScale: _number(json['coverScale'], 1).clamp(1, 4),
      coverOffsetX: _number(json['coverOffsetX'], 0),
      coverOffsetY: _number(json['coverOffsetY'], 0),
    );
  }

  static double _number(dynamic value, double fallback) =>
      value is num ? value.toDouble() : double.tryParse('$value') ?? fallback;
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
}

String echoSignatureText(EchoProfile profile) {
  final signature = profile.signature.trim();
  return signature.isEmpty ? '这里记录我的生活。' : signature;
}

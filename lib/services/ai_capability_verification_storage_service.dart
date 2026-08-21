import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../config/peilink_runtime.dart';
import '../models/ai_capability_health.dart';

class AiCapabilityVerificationStorageService {
  AiCapabilityVerificationStorageService({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  static const _storageKey = 'ai_capability_verification';

  static String get _key => PeiLinkRuntime.secureStorageKey(_storageKey);

  Future<AiCapabilityVerificationSnapshot> load() async {
    final raw = await _storage.read(key: _key);
    if (raw == null || raw.isEmpty) {
      return const AiCapabilityVerificationSnapshot();
    }
    try {
      return AiCapabilityVerificationSnapshot.fromJson(jsonDecode(raw));
    } catch (_) {
      return const AiCapabilityVerificationSnapshot();
    }
  }

  Future<void> save(AiCapabilityVerificationSnapshot snapshot) {
    return _storage.write(key: _key, value: jsonEncode(snapshot.toJson()));
  }
}

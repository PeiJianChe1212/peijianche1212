import 'dart:convert';

import 'package:flutter/material.dart';

import '../models/api_settings.dart';
import '../platform/storage/platform_storage.dart';
import '../config/peilink_runtime.dart';

/// 第三方数据用途分类。
enum ConsentPurpose {
  chat,
  imageGeneration,
  multimodal,
}

extension ConsentPurposeLabel on ConsentPurpose {
  String get label => switch (this) {
        ConsentPurpose.chat => '对话生成',
        ConsentPurpose.imageGeneration => '图片生成',
        ConsentPurpose.multimodal => '多模态理解',
      };
}

/// 未授权异常。底层发送层在无有效 consent 时抛出。
class NoConsentException implements Exception {
  NoConsentException({required this.message});
  final String message;
  @override
  String toString() => message;
}

/// 第三方 AI 服务数据流向告知与同意管理。
class ThirdPartyConsentService {
  ThirdPartyConsentService._();
  static final ThirdPartyConsentService instance = ThirdPartyConsentService._();

  static const _storageKey = 'third_party_consent_v1';
  static const String noticeVersion = '2026-09-v1';

  Future<PlatformStorage> _store() => PeiLinkRuntime.storage();

  Future<Map<String, dynamic>> _loadAll() async {
    final store = await _store();
    if (!await store.exists(_storageKey)) return {};
    try {
      final raw = await store.readText(_storageKey);
      if (raw.trim().isEmpty) return {};
      final decoded = jsonDecode(raw);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : {};
    } catch (_) {
      return {};
    }
  }

  Future<void> _saveAll(Map<String, dynamic> data) async {
    final store = await _store();
    await store.writeText(_storageKey, jsonEncode(data));
  }

  String _consentKey(AIProvider provider, String baseUrl, ConsentPurpose purpose) {
    final normalized = baseUrl.trim().toLowerCase();
    return '${provider.name}::$normalized::${purpose.name}';
  }

  Future<bool> hasConsent(
    AIProvider provider,
    String baseUrl,
    ConsentPurpose purpose,
  ) async {
    final all = await _loadAll();
    final key = _consentKey(provider, baseUrl, purpose);
    final entry = all[key];
    if (entry is! Map) return false;
    return entry['consented'] == true &&
        entry['noticeVersion'] == noticeVersion;
  }

  Future<void> grantConsent(
    AIProvider provider,
    String baseUrl,
    ConsentPurpose purpose,
  ) async {
    final all = await _loadAll();
    final key = _consentKey(provider, baseUrl, purpose);
    all[key] = {
      'consented': true,
      'noticeVersion': noticeVersion,
      'consentedAt': DateTime.now().toIso8601String(),
      'provider': provider.name,
      'endpoint': baseUrl.trim(),
      'purpose': purpose.name,
    };
    await _saveAll(all);
  }

  Future<void> revokeConsent(
    AIProvider provider,
    String baseUrl,
    ConsentPurpose purpose,
  ) async {
    final all = await _loadAll();
    final key = _consentKey(provider, baseUrl, purpose);
    all.remove(key);
    await _saveAll(all);
  }

  /// 列出所有已授权项（用于设置页管理）。
  Future<List<ConsentRecord>> listGrants() async {
    final all = await _loadAll();
    final result = <ConsentRecord>[];
    for (final entry in all.values) {
      if (entry is! Map) continue;
      if (entry['consented'] != true) continue;
      final provider = AIProviderDetails.fromStored(entry['provider']?.toString());
      final purpose = ConsentPurpose.values
          .where((p) => p.name == entry['purpose'])
          .firstOrNull;
      if (purpose == null) continue;
      result.add(ConsentRecord(
        provider: provider,
        endpoint: entry['endpoint']?.toString() ?? '',
        purpose: purpose,
        consentedAt: entry['consentedAt']?.toString(),
      ));
    }
    return result;
  }

  /// 底层守卫：无有效 consent 时抛出 [NoConsentException]。
  /// 在所有实际 HTTP 请求发出前调用。
  Future<void> requireConsent(
    AIProvider provider,
    String baseUrl,
    ConsentPurpose purpose,
  ) async {
    if (await hasConsent(provider, baseUrl, purpose)) return;
    throw NoConsentException(
      message: '尚未取得对 ${provider.label}（${purpose.label}）的数据授权，请在对话中完成授权后再试。',
    );
  }

  /// UI 层：如果未同意则弹窗。返回用户是否同意。
  Future<bool> requestConsentIfNeeded(
    BuildContext context,
    AIProvider provider,
    String baseUrl,
    ConsentPurpose purpose,
  ) async {
    if (await hasConsent(provider, baseUrl, purpose)) return true;
    if (!context.mounted) return false;

    final consented = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          '第三方 AI 服务说明',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        content: SingleChildScrollView(
          child: Text(
            _buildNotice(provider, baseUrl, purpose),
            style: const TextStyle(fontSize: 14, height: 1.6),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('同意并继续'),
          ),
        ],
      ),
    );

    if (consented == true) {
      await grantConsent(provider, baseUrl, purpose);
      return true;
    }
    return false;
  }

  String _buildNotice(
    AIProvider provider,
    String baseUrl,
    ConsentPurpose purpose,
  ) {
    final buffer = StringBuffer();
    buffer.writeln('你当前选择使用 ${provider.label} 进行${purpose.label}。');
    buffer.writeln();

    if (purpose == ConsentPurpose.chat) {
      buffer.writeln('为了生成回复，PeiLink 会将以下内容发送至该服务接口：');
      buffer.writeln('· 你输入的消息');
      buffer.writeln('· 相关历史对话');
      buffer.writeln('· 为保持角色连续性所需的角色设定与上下文');
    } else if (purpose == ConsentPurpose.imageGeneration) {
      buffer.writeln('为了生成图片，PeiLink 会将图片生成提示词及相关必要上下文发送至该服务接口。');
    } else {
      buffer.writeln('为了理解你发送的图片并生成回复，PeiLink 会将图片和相关文本发送至该服务接口。');
    }
    buffer.writeln();

    if (provider == AIProvider.custom || baseUrl.trim().isEmpty) {
      buffer.writeln(
        '⚠️ 该服务由你自行配置，PeiLink 无法判断该服务提供者的身份、数据保存方式或隐私政策。请确认你信任该服务后再继续。',
      );
    } else {
      buffer.writeln(
        '第三方服务对这些数据的进一步处理受其自身服务条款和隐私政策约束。',
      );
    }
    buffer.writeln();
    buffer.writeln('PeiLink 不会将你的 API Key 作为聊天内容发送。');
    buffer.writeln();
    buffer.writeln('如果你不同意，请取消并更换其他模型或停止本次互动。');
    return buffer.toString();
  }
}

class ConsentRecord {
  const ConsentRecord({
    required this.provider,
    required this.endpoint,
    required this.purpose,
    this.consentedAt,
  });
  final AIProvider provider;
  final String endpoint;
  final ConsentPurpose purpose;
  final String? consentedAt;
}

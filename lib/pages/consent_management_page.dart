import 'package:flutter/material.dart';

import '../models/api_settings.dart';
import '../services/third_party_consent_service.dart';

class ConsentManagementPage extends StatefulWidget {
  const ConsentManagementPage({super.key});

  @override
  State<ConsentManagementPage> createState() => _ConsentManagementPageState();
}

class _ConsentManagementPageState extends State<ConsentManagementPage> {
  List<ConsentRecord> _grants = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final grants = await ThirdPartyConsentService.instance.listGrants();
    if (!mounted) return;
    setState(() {
      _grants = grants;
      _loading = false;
    });
  }

  Future<void> _revoke(ConsentRecord record) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('撤回授权？'),
        content: Text(
          '将撤回对 ${record.provider.label}（${record.purpose.label}）的授权。'
          'API Key、模型配置和聊天记录不会被删除。'
          '下次使用该服务时需要重新授权。',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('撤回')),
        ],
      ),
    );
    if (confirmed == true) {
      await ThirdPartyConsentService.instance.revokeConsent(
        record.provider,
        record.endpoint,
        record.purpose,
      );
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('第三方数据授权')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _grants.isEmpty
              ? const Center(child: Text('暂无已授权的第三方服务'))
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _grants.length,
                  separatorBuilder: (_, _) => const Divider(),
                  itemBuilder: (_, i) {
                    final g = _grants[i];
                    return ListTile(
                      title: Text('${g.provider.label} · ${g.purpose.label}'),
                      subtitle: Text(g.endpoint),
                      trailing: TextButton(
                        onPressed: () => _revoke(g),
                        child: const Text('撤回'),
                      ),
                    );
                  },
                ),
    );
  }
}

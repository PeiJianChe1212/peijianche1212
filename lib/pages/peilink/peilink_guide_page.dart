import 'package:flutter/material.dart';

import '../../models/guide_knowledge.dart';

import '../api_settings_page.dart';
import '../feedback_page.dart';
import 'ai_creation_center_page.dart';

class PeiLinkGuidePage extends StatefulWidget {
  const PeiLinkGuidePage({super.key});

  @override
  State<PeiLinkGuidePage> createState() => _PeiLinkGuidePageState();
}

class _PeiLinkGuidePageState extends State<PeiLinkGuidePage> {
  final _searchController = TextEditingController();
  final _askController = TextEditingController();
  String _query = '';
  String? _acheReply;

  @override
  void dispose() {
    _searchController.dispose();
    _askController.dispose();
    super.dispose();
  }

  void _askAche() {
    final question = _askController.text.trim();
    if (question.isEmpty) return;
    setState(() => _acheReply = GuideKnowledge.answer(question));
  }

  IconData _guideIcon(String topic) {
    if (topic.contains('Echo')) return Icons.waves_rounded;
    if (topic.contains('羁绊')) return Icons.favorite_rounded;
    if (topic.contains('创建')) return Icons.person_add_alt_1_rounded;
    if (topic.contains('API')) return Icons.psychology_rounded;
    if (topic.contains('导入')) return Icons.file_download_outlined;
    return Icons.shield_rounded;
  }

  void _openPage(Widget page) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    final query = _query.trim().toLowerCase();
    final visible = query.isEmpty
        ? GuideKnowledge.entries
        : GuideKnowledge.entries
              .where(
                (item) =>
                    '${item.topic}${item.answer}'.toLowerCase().contains(query),
              )
              .toList();
    return ListView(
      padding: EdgeInsets.fromLTRB(
        18,
        18,
        18,
        110 + MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(18, 12, 14, 12),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFF4F2FC), Color(0xFFEAF2FC)],
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  SizedBox(
                    width: 92,
                    height: 110,
                    child: Image.asset(
                      'assets/images/guide/ache_welcome.png',
                      fit: BoxFit.contain,
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '你好，我是阿澈 👋',
                          style: TextStyle(
                            color: Color(0xFF5964C6),
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        SizedBox(height: 6),
                        Text(
                          '有什么问题可以问我吗？🦋',
                          style: TextStyle(
                            color: Color(0xFF68728A),
                            fontSize: 13,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                key: const ValueKey('ask-ache-field'),
                controller: _askController,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _askAche(),
                decoration: InputDecoration(
                  hintText: '询问 PeiLink 功能……',
                  prefixIcon: const Icon(Icons.chat_bubble_outline_rounded),
                  suffixIcon: IconButton(
                    key: const ValueKey('ask-ache-send'),
                    onPressed: _askAche,
                    icon: const Icon(Icons.arrow_upward_rounded),
                  ),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.84),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              if (_acheReply != null) ...[
                const SizedBox(height: 10),
                Container(
                  key: const ValueKey('ache-reply'),
                  width: double.infinity,
                  padding: const EdgeInsets.all(13),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.72),
                    borderRadius: BorderRadius.circular(17),
                  ),
                  child: Text(
                    _acheReply!,
                    style: const TextStyle(
                      color: Color(0xFF5F687D),
                      fontSize: 13,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _searchController,
          onChanged: (value) => setState(() => _query = value),
          decoration: InputDecoration(
            hintText: '搜索问题或功能…',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: _query.isEmpty
                ? null
                : IconButton(
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _query = '');
                    },
                    icon: const Icon(Icons.close_rounded),
                  ),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.82),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(22),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: _GuideActionCard(
                title: '创建角色',
                subtitle: '开始第一段连接',
                icon: Icons.person_add_alt_1_rounded,
                tint: const Color(0xFFECE9FD),
                onTap: () => _openPage(const AiCreationCenterPage()),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _GuideActionCard(
                title: 'AI 大脑设置',
                subtitle: '配置模型与 API',
                icon: Icons.psychology_rounded,
                tint: const Color(0xFFFBEAF1),
                onTap: () => _openPage(const ApiSettingsPage()),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _GuideActionCard(
          title: '帮助与反馈',
          subtitle: '提交 Bug、建议或体验问题',
          icon: Icons.help_outline_rounded,
          tint: const Color(0xFFEAF4FA),
          onTap: () => _openPage(const FeedbackPage()),
        ),
        const SizedBox(height: 22),
        const Text(
          '新手指南',
          style: TextStyle(
            color: Color(0xFF30354D),
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        if (visible.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 26),
            child: Center(
              child: Text(
                '暂时没有找到相关内容',
                style: TextStyle(color: Colors.black45),
              ),
            ),
          )
        else
          for (final item in visible)
            Card(
              elevation: 0,
              color: Colors.white.withValues(alpha: 0.78),
              margin: const EdgeInsets.only(bottom: 9),
              child: ExpansionTile(
                leading: CircleAvatar(
                  backgroundColor: const Color(0xFFEEF1FC),
                  child: Icon(
                    _guideIcon(item.topic),
                    color: const Color(0xFF7483DD),
                    size: 19,
                  ),
                ),
                title: Text(
                  item.topic,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        item.answer,
                        style: const TextStyle(
                          color: Color(0xFF68727D),
                          height: 1.55,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
      ],
    );
  }
}

class _GuideActionCard extends StatelessWidget {
  const _GuideActionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.tint,
    required this.onTap,
  });
  final String title;
  final String subtitle;
  final IconData icon;
  final Color tint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: tint,
    borderRadius: BorderRadius.circular(20),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: Colors.white.withValues(alpha: 0.74),
              child: Icon(icon, color: const Color(0xFF7682CF)),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Color(0xFF4E58A6),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF7D8496),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

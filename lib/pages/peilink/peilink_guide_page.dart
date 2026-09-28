import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;

import '../../models/guide_knowledge.dart';
import '../../services/feedback_form_launcher.dart';

import '../api_settings_page.dart';
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
  String? _category;
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

  IconData _guideIcon(String category) {
    return switch (category) {
      '开始使用' => Icons.rocket_launch_outlined,
      '聊天' => Icons.chat_bubble_outline_rounded,
      '角色' => Icons.person_outline_rounded,
      'Memory' => Icons.inbox_outlined,
      'Echo' => Icons.waves_rounded,
      'PeiLink Life' => Icons.auto_awesome_rounded,
      '纪念日' => Icons.favorite_border_rounded,
      '群聊' => Icons.groups_2_outlined,
      '外观' => Icons.palette_outlined,
      '数据与重置' => Icons.restart_alt_rounded,
      'API 与模型' => Icons.psychology_rounded,
      _ => Icons.help_outline_rounded,
    };
  }

  void _openPage(Widget page) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    final visible = GuideKnowledge.entries
        .where((item) => _category == null || item.category == _category)
        .where((item) => item.matches(_query))
        .toList();
    return ListView(
      scrollCacheExtent: const ScrollCacheExtent.pixels(10000),
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
                          '🦋 PeiLink Guide',
                          style: TextStyle(
                            color: Color(0xFF5964C6),
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        SizedBox(height: 6),
                        Text(
                          '关于 PeiLink，有什么想知道的？',
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
          key: const ValueKey('guide-search-field'),
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
        const SizedBox(height: 14),
        SizedBox(
          height: 36,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              _CategoryChip(
                label: '全部',
                selected: _category == null,
                onTap: () => setState(() => _category = null),
              ),
              for (final category in GuideKnowledge.categories)
                _CategoryChip(
                  label: category,
                  selected: _category == category,
                  onTap: () => setState(() => _category = category),
                ),
            ],
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
          key: const ValueKey('guide-feedback-entry'),
          title: '反馈与建议',
          subtitle: '前往飞书表单提交反馈',
          icon: Icons.help_outline_rounded,
          tint: const Color(0xFFEAF4FA),
          onTap: () => FeedbackFormLauncher.open(context),
        ),
        const SizedBox(height: 22),
        const Text(
          '使用说明',
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
          for (var index = 0; index < visible.length; index++) ...[
            if (index == 0 ||
                visible[index - 1].category != visible[index].category)
              Padding(
                padding: const EdgeInsets.fromLTRB(3, 10, 3, 8),
                child: Text(
                  visible[index].category,
                  style: const TextStyle(
                    color: Color(0xFF7770A0),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            Card(
              elevation: 0,
              color: Colors.white.withValues(alpha: 0.78),
              margin: const EdgeInsets.only(bottom: 9),
              child: ExpansionTile(
                leading: CircleAvatar(
                  backgroundColor: const Color(0xFFEEF1FC),
                  child: Icon(
                    _guideIcon(visible[index].category),
                    color: const Color(0xFF7483DD),
                    size: 19,
                  ),
                ),
                title: Text(
                  visible[index].topic,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        visible[index].answer,
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
      ],
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      showCheckmark: false,
      selectedColor: const Color(0xFFE7E3FA),
      backgroundColor: Colors.white.withValues(alpha: 0.72),
      side: BorderSide(
        color: selected ? const Color(0xFF8B7ED5) : const Color(0xFFE7E2EC),
      ),
      labelStyle: TextStyle(
        color: selected ? const Color(0xFF6257B2) : const Color(0xFF77717F),
        fontSize: 12,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
      ),
    ),
  );
}

class _GuideActionCard extends StatelessWidget {
  const _GuideActionCard({
    super.key,
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

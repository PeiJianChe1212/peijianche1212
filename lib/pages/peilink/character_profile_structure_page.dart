import 'package:flutter/material.dart';

class CharacterProfileStructurePage extends StatelessWidget {
  const CharacterProfileStructurePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F4F4),
      appBar: AppBar(
        title: const Text('角色档案'),
        centerTitle: true,
        backgroundColor: const Color(0xFFF4F4F4),
        surfaceTintColor: Colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 28),
        children: const [
          _NoticeCard(),
          SizedBox(height: 12),
          _ProfileSection(
            title: '基础资料',
            icon: Icons.badge_outlined,
            fields: ['姓名', '性别', '年龄', '身高', '生日', '职业'],
          ),
          SizedBox(height: 12),
          _ProfileSection(
            title: '外貌',
            icon: Icons.face_retouching_natural_outlined,
            fields: ['发色', '发型', '瞳色', '肤色', '身材', '五官', '特殊标志'],
          ),
          SizedBox(height: 12),
          _ProfileSection(
            title: '性格与表达',
            icon: Icons.psychology_alt_outlined,
            fields: ['核心性格', '说话方式', '情绪表达', '行为习惯', '禁用模板'],
          ),
          SizedBox(height: 12),
          _ProfileSection(
            title: '生活与世界',
            icon: Icons.auto_awesome_outlined,
            fields: ['身份与职业', '生活习惯', '住所与地点', '社交关系', '世界观背景'],
          ),
          SizedBox(height: 12),
          _ProfileSection(
            title: '与你的关系',
            icon: Icons.favorite_border_rounded,
            fields: ['关系定位', '他对你的称呼', '相处边界', '共同经历'],
          ),
        ],
      ),
    );
  }
}

class _NoticeCard extends StatelessWidget {
  const _NoticeCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF4FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD6E8F8)),
      ),
      child: const Text(
        '这是角色档案的第一版框架。当前 Prompt 和已有角色数据不会被修改，后续会分批迁移并开放编辑。',
        style: TextStyle(
          color: Color(0xFF53697A),
          fontSize: 13.5,
          height: 1.55,
        ),
      ),
    );
  }
}

class _ProfileSection extends StatelessWidget {
  const _ProfileSection({
    required this.title,
    required this.icon,
    required this.fields,
  });

  final String title;
  final IconData icon;
  final List<String> fields;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE8E8E8), width: 0.7),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Row(
              children: [
                Icon(icon, size: 20, color: const Color(0xFF506675)),
                const SizedBox(width: 9),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF202020),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: fields
                  .map(
                    (field) => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 11,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF5F6F7),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        field,
                        style: const TextStyle(
                          color: Color(0xFF666666),
                          fontSize: 13,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../models/echo_visitor_record.dart';
import '../../widgets/echo/echo_visitor_card.dart';

class EchoVisitorListPage extends StatelessWidget {
  const EchoVisitorListPage({super.key, required this.visitors});
  final List<EchoVisitorRecord> visitors;

  @override
  Widget build(BuildContext context) {
    final social = visitors
        .where((item) => item.visitorType != EchoVisitorType.user)
        .toList();
    final userVisits = visitors
        .where((item) => item.visitorType == EchoVisitorType.user)
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('最近访客'),
        backgroundColor: Colors.white.withValues(alpha: 0.72),
        surfaceTintColor: Colors.transparent,
      ),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFE9E6FA), Color(0xFFFFF4F2), Color(0xFFE8F1F6)],
          ),
        ),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const _VisitorSectionTitle('AI角色访客'),
            if (social.isEmpty)
              const _VisitorEmpty('这里还没有留下痕迹。等待新的故事发生。')
            else
              ...social.map(
                (record) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: EchoVisitorCard(record: record),
                ),
              ),
            const SizedBox(height: 18),
            const _VisitorSectionTitle('PeiLink World'),
            const _VisitorEmpty('世界还很安静，等待新的故事发生。'),
            const SizedBox(height: 18),
            const _VisitorSectionTitle('你的访问记录'),
            if (userVisits.isEmpty)
              const _VisitorEmpty('这里还没有留下痕迹。等待新的故事发生。')
            else
              ...userVisits.map((record) => _UserVisitTile(record: record)),
          ],
        ),
      ),
    );
  }
}

class _VisitorSectionTitle extends StatelessWidget {
  const _VisitorSectionTitle(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 0, 4, 9),
    child: Text(
      text,
      style: const TextStyle(
        color: Color(0xFF53616A),
        fontSize: 15,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class _VisitorEmpty extends StatelessWidget {
  const _VisitorEmpty(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: _surface(),
    child: Text(
      text,
      style: const TextStyle(color: Color(0xFF87939A), fontSize: 12),
    ),
  );
}

class _UserVisitTile extends StatelessWidget {
  const _UserVisitTile({required this.record});
  final EchoVisitorRecord record;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
    decoration: _surface(),
    child: Row(
      children: [
        const CircleAvatar(
          backgroundColor: Color(0xFFECE8FA),
          child: Icon(Icons.person_rounded, color: Color(0xFF8878C8)),
        ),
        const SizedBox(width: 12),
        const Expanded(child: Text('你')),
        Text(
          _formatVisit(record.visitTime),
          style: const TextStyle(color: Color(0xFF8C979D), fontSize: 11),
        ),
      ],
    ),
  );
}

BoxDecoration _surface() => BoxDecoration(
  color: Colors.white.withValues(alpha: 0.74),
  borderRadius: BorderRadius.circular(18),
  border: Border.all(color: Colors.white.withValues(alpha: 0.78)),
);

String _formatVisit(DateTime time) {
  final now = DateTime.now();
  final hour = time.hour.toString().padLeft(2, '0');
  final minute = time.minute.toString().padLeft(2, '0');
  if (time.year == now.year && time.month == now.month && time.day == now.day) {
    return '今天 $hour:$minute访问';
  }
  return '${time.month}月${time.day}日 $hour:$minute访问';
}

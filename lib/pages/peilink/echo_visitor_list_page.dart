import 'package:flutter/material.dart';

import '../../models/echo_visitor_record.dart';
import '../../widgets/echo/echo_visitor_card.dart';

class EchoVisitorListPage extends StatelessWidget {
  const EchoVisitorListPage({super.key, required this.visitors});
  final List<EchoVisitorRecord> visitors;

  @override
  Widget build(BuildContext context) {
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
            colors: [Color(0xFFE2EBF0), Color(0xFFFFF1ED), Color(0xFFE8EFF3)],
          ),
        ),
        child: visitors.isEmpty
            ? const Center(
                child: Text(
                  '还没有访客记录。',
                  style: TextStyle(color: Color(0xFF87939A)),
                ),
              )
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: visitors.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, index) =>
                    EchoVisitorCard(record: visitors[index]),
              ),
      ),
    );
  }
}

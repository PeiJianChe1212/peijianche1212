import 'dart:io';

import 'package:flutter/material.dart';

import '../../models/echo_visitor_record.dart';

class EchoRecentVisitorsStrip extends StatelessWidget {
  const EchoRecentVisitorsStrip({
    super.key,
    required this.visitors,
    required this.onTap,
  });

  final List<EchoVisitorRecord> visitors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final socialVisitors = visitors
        .where((record) => record.visitorType != EchoVisitorType.user)
        .toList();
    final todayCount = socialVisitors.where((record) {
      final time = record.visitTime;
      return time.year == today.year &&
          time.month == today.month &&
          time.day == today.day;
    }).length;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(15),
          child: Ink(
            height: 42,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor.withValues(alpha: 0.88),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: Colors.white.withValues(alpha: 0.62)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.people_alt_outlined,
                  color: Color(0xFF738B98),
                  size: 17,
                ),
                const SizedBox(width: 8),
                const Text(
                  '最近访客',
                  style: TextStyle(
                    color: Color(0xFF4A5A63),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    todayCount == 0 ? '这里还没有留下痕迹' : '今天 $todayCount 位角色来过',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF7F8C93),
                      fontSize: 11.5,
                    ),
                  ),
                ),
                SizedBox(
                  width: 72,
                  child: Stack(
                    alignment: Alignment.centerRight,
                    children: [
                      for (
                        var index = 0;
                        index < socialVisitors.take(3).length;
                        index++
                      )
                        Positioned(
                          right: index * 18.0,
                          child: _VisitorAvatar(record: socialVisitors[index]),
                        ),
                      if (socialVisitors.isEmpty)
                        const Align(
                          alignment: Alignment.centerRight,
                          child: CircleAvatar(
                            radius: 14,
                            backgroundColor: Color(0xFFE8EEF1),
                            child: Icon(
                              Icons.person_outline_rounded,
                              size: 16,
                              color: Color(0xFF9AABB3),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 5),
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: Color(0xFFA6B2B8),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _VisitorAvatar extends StatelessWidget {
  const _VisitorAvatar({required this.record});
  final EchoVisitorRecord record;
  @override
  Widget build(BuildContext context) {
    final path = record.visitorAvatarPath.trim();
    return CircleAvatar(
      radius: 15,
      backgroundColor: Colors.white,
      child: CircleAvatar(
        radius: 13,
        foregroundImage: path.isNotEmpty && File(path).existsSync()
            ? FileImage(File(path))
            : null,
        backgroundColor: const Color(0xFFE8EEF1),
        child: const Icon(
          Icons.person_rounded,
          size: 15,
          color: Color(0xFF8FA1AA),
        ),
      ),
    );
  }
}

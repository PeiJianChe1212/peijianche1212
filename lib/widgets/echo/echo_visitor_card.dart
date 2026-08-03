import 'dart:io';

import 'package:flutter/material.dart';

import '../../models/echo_visitor_record.dart';

class EchoVisitorCard extends StatelessWidget {
  const EchoVisitorCard({super.key, required this.record});
  final EchoVisitorRecord record;

  @override
  Widget build(BuildContext context) {
    final path = record.visitorAvatarPath.trim();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x70FFFFFF), width: 0.7),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 23,
            backgroundColor: const Color(0xFFEAF0F3),
            foregroundImage: path.isNotEmpty && File(path).existsSync()
                ? FileImage(File(path))
                : null,
            child: const Icon(Icons.person_rounded, color: Color(0xFF8298A4)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  record.visitorName.trim().isEmpty ? '访客' : record.visitorName,
                  style: const TextStyle(
                    color: Color(0xFF42515A),
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  _timeText(record.visitTime),
                  style: const TextStyle(
                    color: Color(0xFF929DA3),
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.directions_walk_rounded,
            color: Color(0xFFA8B8C0),
            size: 20,
          ),
        ],
      ),
    );
  }
}

String _timeText(DateTime time) {
  final now = DateTime.now();
  final difference = now.difference(time);
  if (difference.inMinutes < 1) return '刚刚访问';
  if (difference.inHours < 1) return '${difference.inMinutes} 分钟前';
  if (difference.inDays < 1) return '${difference.inHours} 小时前';
  return '${time.month}月${time.day}日';
}

import 'package:flutter/material.dart';

import '../../models/message_list_status.dart';

class RoleStatusMark extends StatelessWidget {
  const RoleStatusMark({super.key, required this.status});

  final MessageListStatus status;

  Color get _color => switch (status.kind) {
    MessageListStatusKind.online => const Color(0xFF55A995),
    MessageListStatusKind.busy => const Color(0xFFD39A58),
    MessageListStatusKind.resting => const Color(0xFF8179B8),
    MessageListStatusKind.sleeping => const Color(0xFF746EAA),
    MessageListStatusKind.outside => const Color(0xFF6F9FC3),
    MessageListStatusKind.music => const Color(0xFFB279A6),
  };

  IconData? get _icon => switch (status.kind) {
    MessageListStatusKind.online => null,
    MessageListStatusKind.busy => Icons.timelapse_rounded,
    MessageListStatusKind.resting => Icons.nightlight_outlined,
    MessageListStatusKind.sleeping => Icons.bedtime_rounded,
    MessageListStatusKind.outside => Icons.north_east_rounded,
    MessageListStatusKind.music => Icons.music_note_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final icon = _icon;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon == null)
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: _color, shape: BoxShape.circle),
          )
        else
          Icon(icon, size: 11, color: _color),
        const SizedBox(width: 3),
        Text(
          status.label,
          style: TextStyle(
            color: _color,
            fontSize: 10,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';

abstract final class GroupVisuals {
  static const accent = Color(0xFF7668A6);
  static const page = Color(0xFFF5F6FA);
  static BoxDecoration card({double radius = 22}) => BoxDecoration(
    color: const Color(0xF7FFFFFF),
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: const Color(0xFFE9E7F0)),
    boxShadow: const [
      BoxShadow(color: Color(0x096E6489), blurRadius: 16, offset: Offset(0, 4)),
    ],
  );
}

/// Visual selection row only; membership rules remain in the calling page.
class GroupMemberChoice extends StatelessWidget {
  const GroupMemberChoice({
    super.key,
    required this.name,
    required this.avatar,
    required this.selected,
    this.locked = false,
    this.onTap,
  });
  final String name;
  final Widget avatar;
  final bool selected, locked;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    enabled: !locked,
    button: !locked,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: Material(
        color: selected ? const Color(0xFFF0EDF8) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: locked ? null : onTap,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                avatar,
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        locked ? '我 · 固定成员' : 'AI 角色成员',
                        style: const TextStyle(
                          color: Color(0xFF777386),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  locked
                      ? Icons.lock_outline_rounded
                      : selected
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: selected
                      ? GroupVisuals.accent
                      : const Color(0xFFBDB7CA),
                  size: 24,
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

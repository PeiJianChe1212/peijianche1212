import 'package:flutter/material.dart';

/// 轻量级 AI 身份标识徽章。
///
/// 用于在角色聊天、AI World、小游戏房、Space 等互动场景中，
/// 持续提示用户当前互动对象为 AI 角色，而非自然人。
class AiIdentityBadge extends StatelessWidget {
  /// 紧凑模式：仅显示"AI 角色"，用于空间有限的位置。
  const AiIdentityBadge.compact({super.key}) : expanded = false;

  /// 完整模式：显示"AI 角色 · 内容由人工智能生成"。
  const AiIdentityBadge.expanded({super.key}) : expanded = true;

  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final text = expanded ? 'AI 角色 · 内容由人工智能生成' : 'AI 角色';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFF8B91D9).withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: const Color(0xFF8B91D9).withValues(alpha: 0.20),
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.auto_awesome_outlined,
            size: 11,
            color: Color(0xFF6B72C4),
          ),
          const SizedBox(width: 3),
          Text(
            text,
            style: const TextStyle(
              fontSize: 10,
              color: Color(0xFF6B72C4),
              fontWeight: FontWeight.w500,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

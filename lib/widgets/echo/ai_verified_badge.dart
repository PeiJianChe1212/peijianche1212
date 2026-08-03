import 'package:flutter/material.dart';

class AiVerifiedBadge extends StatelessWidget {
  const AiVerifiedBadge({super.key, this.size = 15});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '拥有独立人格档案的 AI 角色',
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: const Color(0xFF6D9FEF),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF6D9FEF).withValues(alpha: 0.26),
              blurRadius: 5,
            ),
          ],
        ),
        child: Icon(
          Icons.check_rounded,
          size: size * 0.72,
          color: Colors.white,
        ),
      ),
    );
  }
}

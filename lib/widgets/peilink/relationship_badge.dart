import 'package:flutter/material.dart';

/// 只负责把角色已有关系字段转换为消息列表中的轻量展示。
class RelationshipBadge extends StatelessWidget {
  const RelationshipBadge({super.key, required this.relationship});

  final String relationship;

  static const _emptyValues = {
    '',
    '无',
    '暂无',
    '未设置',
    '未设定',
    '未填写',
    'unknown',
    'none',
  };

  static String? displayTextFor(String relationship) {
    final value = relationship.trim();
    if (_emptyValues.contains(value.toLowerCase())) return null;

    final symbol = switch (value) {
      _
          when value.contains('恋人') ||
              value.contains('伴侣') ||
              value.contains('爱人') =>
        '♡',
      _
          when value.contains('师尊') ||
              value.contains('师父') ||
              value.contains('导师') =>
        '☯',
      _
          when value.contains('挚友') ||
              value.contains('好友') ||
              value.contains('朋友') =>
        '⚔',
      _ when value.contains('主人') => '◆',
      _ when value.toLowerCase().contains('ai伙伴') || value.contains('伙伴') =>
        '✦',
      _ => null,
    };
    return symbol == null ? value : '$symbol $value';
  }

  @override
  Widget build(BuildContext context) {
    final displayText = displayTextFor(relationship);
    if (displayText == null) return const SizedBox.shrink();

    return Text(
      displayText,
      key: const ValueKey('relationship-badge'),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        color: Color(0xFFB77987),
        fontSize: 11,
        height: 1.1,
        fontWeight: FontWeight.w500,
      ),
    );
  }
}

import 'package:flutter/material.dart';

class EchoCharacterActivityStrip extends StatelessWidget {
  const EchoCharacterActivityStrip({
    super.key,
    required this.currentStatus,
    required this.recentActivity,
  });

  final String currentStatus;
  final String recentActivity;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('echo-character-activity-strip'),
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0x70FFFFFF), width: 0.7),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.auto_awesome_rounded,
            size: 18,
            color: Color(0xFF8B7BD8),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: _ActivityValue(label: '当前状态', value: currentStatus),
          ),
          const SizedBox(
            height: 30,
            child: VerticalDivider(color: Color(0xFFE1E7EA)),
          ),
          Expanded(
            child: _ActivityValue(label: '最近活动', value: recentActivity),
          ),
        ],
      ),
    );
  }
}

class EchoInteractionSummaryEntry extends StatelessWidget {
  const EchoInteractionSummaryEntry({
    super.key,
    required this.interactionCount,
    required this.sharedExperienceCount,
    required this.onTap,
  });

  final int interactionCount;
  final int sharedExperienceCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: const ValueKey('echo-interaction-summary-entry'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0x70FFFFFF), width: 0.7),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.forum_outlined,
                  size: 20,
                  color: Color(0xFF7E91CB),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '互动记录',
                        style: TextStyle(
                          color: Color(0xFF45545C),
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '$interactionCount 次互动 · $sharedExperienceCount 条共同经历',
                        style: const TextStyle(
                          color: Color(0xFF8A969D),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                const Text(
                  '查看摘要',
                  style: TextStyle(color: Color(0xFF718995), fontSize: 11),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: Color(0xFF9EACB3),
                  size: 18,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ActivityValue extends StatelessWidget {
  const _ActivityValue({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: Color(0xFF9AA4AA), fontSize: 9.5),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Color(0xFF5C6971),
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

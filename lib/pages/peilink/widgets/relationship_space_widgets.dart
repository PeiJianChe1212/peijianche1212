import 'package:flutter/material.dart';

class RelationshipArchiveCard extends StatelessWidget {
  const RelationshipArchiveCard({
    super.key,
    required this.relationship,
    required this.metAt,
    required this.daysKnown,
    required this.sharedExperienceCount,
  });

  final String relationship;
  final DateTime? metAt;
  final int? daysKnown;
  final int sharedExperienceCount;

  @override
  Widget build(BuildContext context) {
    final meetingDate = metAt;
    return _RelationshipSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.favorite_rounded,
                size: 19,
                color: Color(0xFFE989A0),
              ),
              const SizedBox(width: 8),
              const Text(
                '羁绊档案',
                style: TextStyle(
                  color: Color(0xFF35434C),
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              _RelationshipPill(label: relationship),
            ],
          ),
          const SizedBox(height: 20),
          const Text(
            '关于你们',
            style: TextStyle(
              color: Color(0xFF596870),
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '从第一次相遇开始，\n这里会记录属于你们的故事。',
            style: TextStyle(
              color: Color(0xFF758188),
              fontSize: 13,
              height: 1.55,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _ArchiveMetric(
                  label: '相识时间',
                  value: meetingDate == null ? '未知' : _formatDate(meetingDate),
                ),
              ),
              const _MetricDivider(),
              Expanded(
                child: _ArchiveMetric(
                  label: '陪伴天数',
                  value: daysKnown == null ? '未知' : '$daysKnown 天',
                ),
              ),
              const _MetricDivider(),
              Expanded(
                child: _ArchiveMetric(
                  label: '共同经历',
                  value: '$sharedExperienceCount 件',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class RelationshipTimelineCard extends StatelessWidget {
  const RelationshipTimelineCard({super.key});

  @override
  Widget build(BuildContext context) {
    return const _RelationshipSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.schedule_rounded, size: 19, color: Color(0xFFE989A0)),
              SizedBox(width: 8),
              Text(
                '关系变化记录',
                style: TextStyle(
                  color: Color(0xFF35434C),
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          SizedBox(height: 24),
          Center(
            child: Column(
              children: [
                Icon(
                  Icons.timeline_rounded,
                  size: 32,
                  color: Color(0xFFB6C3C9),
                ),
                SizedBox(height: 12),
                Text(
                  '未来的重要瞬间，会记录在这里。',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF879298),
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 10),
        ],
      ),
    );
  }
}

class RelationshipGiftEntryCard extends StatelessWidget {
  const RelationshipGiftEntryCard({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          padding: const EdgeInsets.all(16),
          decoration: _surfaceDecoration(context),
          child: const Row(
            children: [
              Icon(
                Icons.card_giftcard_rounded,
                size: 22,
                color: Color(0xFFE989A0),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '礼物收藏',
                      style: TextStyle(
                        color: Color(0xFF35434C),
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      '这里收藏你们收到的礼物。',
                      style: TextStyle(color: Color(0xFF8B969C), fontSize: 12),
                    ),
                  ],
                ),
              ),
              Text(
                '0 件',
                style: TextStyle(
                  color: Color(0xFFC96F86),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(width: 4),
              Icon(Icons.chevron_right_rounded, color: Color(0xFFB5C0C5)),
            ],
          ),
        ),
      ),
    );
  }
}

class _RelationshipSurface extends StatelessWidget {
  const _RelationshipSurface({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: _surfaceDecoration(context),
    child: Padding(padding: const EdgeInsets.all(18), child: child),
  );
}

BoxDecoration _surfaceDecoration(BuildContext context) => BoxDecoration(
  color: Theme.of(context).cardColor,
  borderRadius: BorderRadius.circular(16),
  border: Border.all(color: const Color(0x70FFFFFF), width: 0.7),
  boxShadow: const [
    BoxShadow(color: Color(0x08203744), blurRadius: 12, offset: Offset(0, 4)),
  ],
);

class _RelationshipPill extends StatelessWidget {
  const _RelationshipPill({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: const Color(0x72FFF0F4),
      borderRadius: BorderRadius.circular(13),
    ),
    child: Text(
      label,
      style: const TextStyle(
        color: Color(0xFFC96F86),
        fontSize: 11,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class _ArchiveMetric extends StatelessWidget {
  const _ArchiveMetric({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(
        label,
        style: const TextStyle(color: Color(0xFF929DA3), fontSize: 10.5),
      ),
      const SizedBox(height: 6),
      Text(
        value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Color(0xFF53636B),
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    ],
  );
}

class _MetricDivider extends StatelessWidget {
  const _MetricDivider();
  @override
  Widget build(BuildContext context) => const SizedBox(
    height: 34,
    child: VerticalDivider(width: 1, color: Color(0xFFE1E7EA)),
  );
}

String _formatDate(DateTime time) {
  final month = time.month.toString().padLeft(2, '0');
  final day = time.day.toString().padLeft(2, '0');
  return '${time.year}.$month.$day';
}

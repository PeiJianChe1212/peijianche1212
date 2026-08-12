import 'dart:io';

import 'package:flutter/material.dart';

import '../../models/ai_character.dart';
import '../../models/relationship_growth.dart';
import '../../services/relationship_growth_service.dart';
import 'relationship_gift_page.dart';

class RelationshipGrowthPage extends StatefulWidget {
  const RelationshipGrowthPage({
    super.key,
    required this.character,
    required this.initialProfile,
    required this.chatInteractionCount,
    required this.echoInteractionCount,
    required this.sharedExperienceCount,
  });

  final AiCharacter character;
  final RelationshipGrowthProfile initialProfile;
  final int chatInteractionCount;
  final int echoInteractionCount;
  final int sharedExperienceCount;

  @override
  State<RelationshipGrowthPage> createState() => _RelationshipGrowthPageState();
}

class _RelationshipGrowthPageState extends State<RelationshipGrowthPage> {
  late RelationshipGrowthProfile _profile = widget.initialProfile;

  Future<void> _openGifts() async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => RelationshipGiftPage(
          characterId: widget.character.id,
          characterName: widget.character.characterName,
        ),
      ),
    );
    if (changed != true) return;
    final profile = await RelationshipGrowthService(
      characterId: widget.character.id,
    ).loadOrCreate(metAt: widget.character.createdAt);
    if (mounted) setState(() => _profile = profile);
  }

  @override
  Widget build(BuildContext context) {
    final level = _profile.levelFor();
    final experience = _profile.currentExperienceFor();
    final required = _profile.nextLevelExperienceFor();
    final stage = _profile.stageFor();
    final progress = required == 0 ? 1.0 : experience / required;
    final levelsUntilNextStage = level >= 100 ? 0 : 10 - ((level - 1) % 10);
    final history = [..._profile.history]
      ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF4F0FF), Color(0xFFFFF9FD), Color(0xFFEAF4FF)],
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('关系成长'),
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 38),
          children: [
            _GrowthHero(
              character: widget.character,
              level: level,
              stage: stage,
            ),
            const SizedBox(height: 12),
            _GrowthProgress(
              level: level,
              experience: experience,
              required: required,
              progress: progress,
              levelsUntilNextStage: levelsUntilNextStage,
            ),
            const SizedBox(height: 12),
            _CommonRecords(
              chatCount: widget.chatInteractionCount,
              echoCount: widget.echoInteractionCount,
              giftCount: _profile.gifts.length,
              specialCount: widget.sharedExperienceCount,
              onOpenGifts: _openGifts,
            ),
            const SizedBox(height: 12),
            _GrowthHistory(events: history),
          ],
        ),
      ),
    );
  }
}

class _GrowthHero extends StatelessWidget {
  const _GrowthHero({
    required this.character,
    required this.level,
    required this.stage,
  });

  final AiCharacter character;
  final int level;
  final String stage;

  @override
  Widget build(BuildContext context) {
    final path = character.avatarPath.trim();
    return _GlassSurface(
      child: Row(
        children: [
          Container(
            width: 78,
            height: 78,
            padding: const EdgeInsets.all(3),
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: ClipOval(
              child: path.isNotEmpty && File(path).existsSync()
                  ? Image.file(File(path), fit: BoxFit.cover)
                  : const ColoredBox(
                      color: Color(0xFFE8E3FA),
                      child: Icon(
                        Icons.person_rounded,
                        color: Color(0xFF8B7BD8),
                        size: 40,
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  character.characterName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF34424B),
                    fontSize: 21,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  'Lv.$level  ·  $stage',
                  style: const TextStyle(
                    color: Color(0xFF8574CE),
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GrowthProgress extends StatelessWidget {
  const _GrowthProgress({
    required this.level,
    required this.experience,
    required this.required,
    required this.progress,
    required this.levelsUntilNextStage,
  });

  final int level;
  final int experience;
  final int required;
  final double progress;
  final int levelsUntilNextStage;

  @override
  Widget build(BuildContext context) => _GlassSurface(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              '成长经验',
              style: TextStyle(
                color: Color(0xFF4B5961),
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            Text(
              level >= 100 ? '已达到当前最高等级' : '$experience / $required',
              style: const TextStyle(color: Color(0xFF817590), fontSize: 12),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: progress.clamp(0, 1),
            minHeight: 9,
            backgroundColor: const Color(0x55FFFFFF),
            valueColor: const AlwaysStoppedAnimation(Color(0xFF9B8ADD)),
          ),
        ),
        const SizedBox(height: 9),
        Text(
          level >= 100 ? '关系仍会继续留下记录' : '距离下一等级还需 ${required - experience} 经验',
          style: const TextStyle(color: Color(0xFF8A969D), fontSize: 11),
        ),
      ],
    ),
  );
}

class _CommonRecords extends StatelessWidget {
  const _CommonRecords({
    required this.chatCount,
    required this.echoCount,
    required this.giftCount,
    required this.specialCount,
    required this.onOpenGifts,
  });

  final int chatCount;
  final int echoCount;
  final int giftCount;
  final int specialCount;
  final VoidCallback onOpenGifts;

  @override
  Widget build(BuildContext context) => _GlassSurface(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '共同记录',
          style: TextStyle(
            color: Color(0xFF4B5961),
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            _RecordMetric(label: '聊天', value: '$chatCount 次'),
            _RecordMetric(label: 'Echo互动', value: '$echoCount 次'),
            _RecordMetric(
              label: '礼物',
              value: '$giftCount 件',
              onTap: onOpenGifts,
            ),
            _RecordMetric(label: '特殊事件', value: '$specialCount 件'),
          ],
        ),
      ],
    ),
  );
}

class _RecordMetric extends StatelessWidget {
  const _RecordMetric({required this.label, required this.value, this.onTap});
  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Expanded(
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          children: [
            Text(
              value,
              style: const TextStyle(
                color: Color(0xFF6D61A8),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(color: Color(0xFF929DA3), fontSize: 10),
            ),
          ],
        ),
      ),
    ),
  );
}

class _GrowthHistory extends StatelessWidget {
  const _GrowthHistory({required this.events});
  final List<RelationshipGrowthEvent> events;

  @override
  Widget build(BuildContext context) => _GlassSurface(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '成长轨迹',
          style: TextStyle(
            color: Color(0xFF4B5961),
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        ...events.map(
          (event) => ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            leading: const Icon(
              Icons.auto_awesome_rounded,
              color: Color(0xFF9484D7),
              size: 18,
            ),
            title: Text(event.title),
            subtitle: event.detail.isEmpty ? null : Text(event.detail),
            trailing: Text(
              event.experience == 0 ? '' : '+${event.experience}',
              style: const TextStyle(color: Color(0xFF8A79D0)),
            ),
          ),
        ),
      ],
    ),
  );
}

class _GlassSurface extends StatelessWidget {
  const _GlassSurface({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.72),
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: Colors.white.withValues(alpha: 0.75)),
      boxShadow: const [BoxShadow(color: Color(0x0D6C5C9E), blurRadius: 18)],
    ),
    child: child,
  );
}

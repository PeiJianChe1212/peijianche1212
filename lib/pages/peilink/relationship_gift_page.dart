import 'package:flutter/material.dart';

import '../../models/relationship_growth.dart';
import '../../services/relationship_growth_service.dart';

class RelationshipGiftPage extends StatefulWidget {
  const RelationshipGiftPage({
    super.key,
    required this.characterId,
    required this.characterName,
  });

  final String characterId;
  final String characterName;

  @override
  State<RelationshipGiftPage> createState() => _RelationshipGiftPageState();
}

class _RelationshipGiftPageState extends State<RelationshipGiftPage> {
  RelationshipGrowthProfile? _profile;
  bool _loading = true;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final profile = await RelationshipGrowthService(
      characterId: widget.characterId,
    ).loadOrCreate();
    if (mounted) {
      setState(() {
        _profile = profile;
        _loading = false;
      });
    }
  }

  Future<void> _give(RelationshipGiftType type) async {
    final profile = await RelationshipGrowthService(
      characterId: widget.characterId,
    ).giveGift(type);
    if (!mounted) return;
    setState(() {
      _profile = profile;
      _changed = true;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${widget.characterName} 收到了${type.label}')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final gifts = [...?_profile?.gifts]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) Navigator.pop(context, _changed);
      },
      child: Scaffold(
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          title: const Text('礼物记录'),
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        body: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFF4F0FF), Color(0xFFFFF8FC), Color(0xFFEAF4FF)],
            ),
          ),
          child: SafeArea(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.fromLTRB(18, 12, 18, 36),
                    children: [
                      _GiftPicker(onGive: _give),
                      const SizedBox(height: 14),
                      const Text(
                        '收到的礼物',
                        style: TextStyle(
                          color: Color(0xFF45525A),
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (gifts.isEmpty)
                        const _GiftEmptyState()
                      else
                        ...gifts.map(_GiftRecordTile.new),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class _GiftPicker extends StatelessWidget {
  const _GiftPicker({required this.onGive});
  final ValueChanged<RelationshipGiftType> onGive;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: _giftSurface(),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '赠送一份心意',
          style: TextStyle(
            color: Color(0xFF45525A),
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: RelationshipGiftType.values
              .map(
                (type) => ActionChip(
                  avatar: Icon(
                    _icon(type),
                    size: 17,
                    color: const Color(0xFF8A75D1),
                  ),
                  label: Text(type.label),
                  onPressed: () => onGive(type),
                ),
              )
              .toList(),
        ),
      ],
    ),
  );
}

class _GiftRecordTile extends StatelessWidget {
  const _GiftRecordTile(this.record);
  final RelationshipGiftRecord record;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 9),
    padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
    decoration: _giftSurface(),
    child: Row(
      children: [
        Icon(_icon(record.type), color: const Color(0xFFE18BA4)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '收到礼物：${record.type.label}',
                style: const TextStyle(
                  color: Color(0xFF4B5961),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _formatTime(record.createdAt),
                style: const TextStyle(color: Color(0xFF929DA3), fontSize: 11),
              ),
            ],
          ),
        ),
        Text(
          '+${record.type.experience}',
          style: const TextStyle(
            color: Color(0xFF8A75D1),
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

class _GiftEmptyState extends StatelessWidget {
  const _GiftEmptyState();
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 34),
    decoration: _giftSurface(),
    alignment: Alignment.center,
    child: const Column(
      children: [
        Icon(Icons.card_giftcard_rounded, color: Color(0xFFB39FDC), size: 42),
        SizedBox(height: 10),
        Text('暂无礼物记录', style: TextStyle(color: Color(0xFF8C969C))),
      ],
    ),
  );
}

BoxDecoration _giftSurface() => BoxDecoration(
  color: Colors.white.withValues(alpha: 0.76),
  borderRadius: BorderRadius.circular(20),
  border: Border.all(color: Colors.white.withValues(alpha: 0.8)),
);

IconData _icon(RelationshipGiftType type) => switch (type) {
  RelationshipGiftType.flower => Icons.local_florist_rounded,
  RelationshipGiftType.letter => Icons.mail_rounded,
  RelationshipGiftType.smallGift => Icons.card_giftcard_rounded,
  RelationshipGiftType.collectible => Icons.diamond_outlined,
};

String _formatTime(DateTime time) {
  final month = time.month.toString().padLeft(2, '0');
  final day = time.day.toString().padLeft(2, '0');
  final hour = time.hour.toString().padLeft(2, '0');
  final minute = time.minute.toString().padLeft(2, '0');
  return '${time.year}.$month.$day  $hour:$minute';
}

import 'package:flutter/material.dart';

class EchoGiftCollectionPage extends StatelessWidget {
  const EchoGiftCollectionPage({super.key, required this.characterName});

  final String characterName;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('礼物收藏'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFF3F6F8), Color(0xFFFFF4F0), Color(0xFFE7F0F4)],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(24, 34, 24, 38),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.86),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: Colors.white.withValues(alpha: 0.72)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.card_giftcard_rounded,
                    size: 62,
                    color: Color(0xFFE991A6),
                  ),
                  const SizedBox(height: 22),
                  const Text(
                    '还没有收到礼物',
                    style: TextStyle(
                      color: Color(0xFF3E4A52),
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '这里收藏你和 $characterName 收到的礼物。\n未来的重要礼物，会被记录在这里。',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFF849097),
                      fontSize: 13,
                      height: 1.65,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../models/red_packet_data.dart';

class RedPacketMessageRenderer extends StatelessWidget {
  const RedPacketMessageRenderer({
    super.key,
    required this.data,
    this.currentViewerId = 'user',
    this.onTap,
  });

  final RedPacketData data;
  final String currentViewerId;
  final VoidCallback? onTap;

  bool get _sentByViewer => currentViewerId == data.senderId;

  @override
  Widget build(BuildContext context) {
    final message = data.message.trim().isEmpty ? '恭喜发财' : data.message.trim();
    final colors = _cardColors;
    return Semantics(
      button: onTap != null,
      label: '红包，$message，$_statusText',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
            child: Container(
              width: 228,
              constraints: const BoxConstraints(minHeight: 132),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: colors,
                ),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0x66F4D1AA)),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x360D1020),
                    blurRadius: 22,
                    offset: Offset(0, 10),
                  ),
                  BoxShadow(color: Color(0x28F6BD91), blurRadius: 18),
                ],
              ),
              child: Stack(
                children: [
                  const Positioned(
                    right: -25,
                    top: -32,
                    child: _GlowOrb(size: 92),
                  ),
                  const Positioned.fill(child: _EnvelopeLine()),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(17, 16, 17, 13),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.10),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: const Color(0x88F8D7B1),
                                ),
                              ),
                              child: const Icon(
                                Icons.card_giftcard_rounded,
                                color: Color(0xFFFFDBB2),
                                size: 21,
                              ),
                            ),
                            const SizedBox(width: 11),
                            const Text(
                              '红包',
                              style: TextStyle(
                                color: Color(0xFFFFE4C5),
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.4,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              'PEILINK',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.38),
                                fontSize: 8,
                                letterSpacing: 2.1,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 13),
                        Text(
                          message,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.91),
                            fontSize: 13.5,
                            height: 1.35,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0x14101320),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.22),
                                ),
                              ),
                              child: Text(
                                _statusText,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.82),
                                  fontSize: 11.5,
                                ),
                              ),
                            ),
                            const Spacer(),
                            Icon(
                              data.isOpened
                                  ? Icons.check_circle_outline_rounded
                                  : Icons.arrow_forward_rounded,
                              color: const Color(0xB8FFD6AD),
                              size: 17,
                            ),
                          ],
                        ),
                      ],
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

  List<Color> get _cardColors {
    if (data.isOpened) {
      return const [Color(0xE832374B), Color(0xE824293A)];
    }
    if (_sentByViewer) {
      return const [Color(0xE8B44C68), Color(0xE47E3D59)];
    }
    return const [Color(0xEB343953), Color(0xE9272B43)];
  }

  String get _statusText {
    if (data.isOpened) return '已领取';
    if (_sentByViewer) return '等待对方领取';
    if (data.receiverId.isNotEmpty && currentViewerId != data.receiverId) {
      return '不可领取';
    }
    return '等待领取';
  }
}

class RedPacketOpenedDialog extends StatelessWidget {
  const RedPacketOpenedDialog({
    super.key,
    required this.data,
    required this.senderName,
  });

  final RedPacketData data;
  final String senderName;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 350),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(30),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isDark
                      ? const [Color(0xF22D3046), Color(0xF01A1D2D)]
                      : const [Color(0xF43A3E59), Color(0xF426293C)],
                ),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: const Color(0x66F6D0AA)),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x660B0D18),
                    blurRadius: 42,
                    offset: Offset(0, 22),
                  ),
                  BoxShadow(color: Color(0x36F1A77F), blurRadius: 28),
                ],
              ),
              child: Stack(
                children: [
                  const Positioned(
                    right: -42,
                    top: -36,
                    child: _GlowOrb(size: 150),
                  ),
                  const Positioned(
                    left: -48,
                    bottom: -58,
                    child: _GlowOrb(size: 135),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(27, 30, 27, 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'P E I L I N K',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.34),
                            fontSize: 9,
                            letterSpacing: 2.5,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Container(
                          width: 66,
                          height: 66,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: const LinearGradient(
                              colors: [Color(0xFFFFD9B1), Color(0xFFEFA47E)],
                            ),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x55F0A47B),
                                blurRadius: 24,
                              ),
                            ],
                            border: Border.all(color: const Color(0xFFFFE9D0)),
                          ),
                          child: const Icon(
                            Icons.card_giftcard_rounded,
                            color: Color(0xFF713D4D),
                            size: 31,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          '$senderName 的红包',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.76),
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          '恭喜收到红包',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Color(0xFFFFD7B0),
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          formatRedPacketAmount(data.amount),
                          style: const TextStyle(
                            color: Color(0xFFFFD5AE),
                            fontSize: 42,
                            height: 1.1,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.4,
                          ),
                        ),
                        if (data.message.trim().isNotEmpty) ...[
                          const SizedBox(height: 18),
                          Text(
                            '“${data.message.trim()}”',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.86),
                              fontSize: 15,
                              height: 1.45,
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                        Text(
                          '来自 $senderName',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.43),
                            fontSize: 12.5,
                          ),
                        ),
                        const SizedBox(height: 26),
                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: FilledButton(
                            onPressed: () => Navigator.pop(context),
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFFFFD3AA),
                              foregroundColor: const Color(0xFF3B2830),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(24),
                              ),
                              elevation: 0,
                            ),
                            child: const Text(
                              '知道了',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
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

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [Color(0x35FFD4B0), Color(0x00FFD4B0)],
          ),
        ),
      ),
    );
  }
}

class _EnvelopeLine extends StatelessWidget {
  const _EnvelopeLine();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(child: CustomPaint(painter: _EnvelopeLinePainter()));
  }
}

class _EnvelopeLinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x70F6C99F)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    final path = Path()
      ..moveTo(-8, size.height * 0.67)
      ..quadraticBezierTo(
        size.width * 0.50,
        size.height * 0.86,
        size.width + 8,
        size.height * 0.55,
      );
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

String formatRedPacketAmount(int amount) {
  final safeAmount = amount < 0 ? 0 : amount;
  final yuan = safeAmount ~/ 100;
  final cents = (safeAmount % 100).toString().padLeft(2, '0');
  return '¥$yuan.$cents';
}

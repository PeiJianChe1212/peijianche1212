import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/chat_message.dart';
import '../../models/red_packet_data.dart';

class RedPacketDraft {
  const RedPacketDraft({required this.amount, required this.message});

  /// Amount in cents/fen.
  final int amount;
  final String message;
}

class RedPacketSendDialog extends StatefulWidget {
  const RedPacketSendDialog({super.key});

  @override
  State<RedPacketSendDialog> createState() => _RedPacketSendDialogState();
}

class _RedPacketSendDialogState extends State<RedPacketSendDialog> {
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _messageController = TextEditingController();
  String? _amountError;

  @override
  void dispose() {
    _amountController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  void _submit() {
    final amount = parseYuanToCents(_amountController.text);
    if (amount == null || amount <= 0) {
      setState(() => _amountError = '请输入有效金额，最多两位小数');
      return;
    }
    Navigator.pop(
      context,
      RedPacketDraft(amount: amount, message: _messageController.text.trim()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fieldColor = Colors.white.withValues(alpha: isDark ? 0.075 : 0.10);
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 390),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: Container(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isDark
                      ? const [Color(0xF134374E), Color(0xF21D2032)]
                      : const [Color(0xF443465F), Color(0xF22B2E43)],
                ),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: const Color(0x55F5D0AF)),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x660C0E18),
                    blurRadius: 40,
                    offset: Offset(0, 20),
                  ),
                ],
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0x20FFD5AF),
                            border: Border.all(color: const Color(0x77F3CAA6)),
                          ),
                          child: const Icon(
                            Icons.card_giftcard_rounded,
                            color: Color(0xFFFFD4AC),
                            size: 23,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '发红包',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 21,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'PEILINK PRIVATE GIFT',
                                style: TextStyle(
                                  color: Color(0x78FFFFFF),
                                  fontSize: 8.5,
                                  letterSpacing: 1.6,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: '关闭',
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close_rounded),
                          color: Colors.white60,
                        ),
                      ],
                    ),
                    const SizedBox(height: 25),
                    TextField(
                      key: const ValueKey('red_packet_amount'),
                      controller: _amountController,
                      autofocus: true,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                      ],
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 23,
                        fontWeight: FontWeight.w600,
                      ),
                      cursorColor: const Color(0xFFFFC99D),
                      decoration: _fieldDecoration(
                        label: '金额（元）',
                        hint: '0.00',
                        fillColor: fieldColor,
                        errorText: _amountError,
                        prefixText: '¥ ',
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      key: const ValueKey('red_packet_message'),
                      controller: _messageController,
                      maxLength: 40,
                      maxLines: 2,
                      style: const TextStyle(color: Colors.white, fontSize: 15),
                      cursorColor: const Color(0xFFFFC99D),
                      decoration: _fieldDecoration(
                        label: '留言',
                        hint: '给你的惊喜',
                        fillColor: fieldColor,
                      ),
                    ),
                    const SizedBox(height: 13),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFD95985), Color(0xFFB94772)],
                          ),
                          borderRadius: BorderRadius.circular(25),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x44D65482),
                              blurRadius: 18,
                              offset: Offset(0, 8),
                            ),
                          ],
                        ),
                        child: TextButton(
                          onPressed: _submit,
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(25),
                            ),
                          ),
                          child: const Text(
                            '发送红包',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _fieldDecoration({
    required String label,
    required String hint,
    required Color fillColor,
    String? errorText,
    String? prefixText,
  }) {
    const borderColor = Color(0x33FFFFFF);
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixText: prefixText,
      errorText: errorText,
      labelStyle: const TextStyle(color: Color(0xAFFFFFFF)),
      hintStyle: const TextStyle(color: Color(0x55FFFFFF)),
      prefixStyle: const TextStyle(color: Color(0xFFFFD2A9)),
      counterStyle: const TextStyle(color: Color(0x66FFFFFF)),
      filled: true,
      fillColor: fillColor,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: borderColor),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: borderColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xAAF6C7A0)),
      ),
    );
  }
}

int? parseYuanToCents(String value) {
  final normalized = value.trim();
  if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(normalized)) return null;
  final parts = normalized.split('.');
  final yuan = int.tryParse(parts.first);
  if (yuan == null) return null;
  final fraction = parts.length == 1 ? '' : parts[1];
  final cents = fraction.isEmpty ? 0 : int.parse(fraction.padRight(2, '0'));
  return yuan * 100 + cents;
}

ChatMessage buildRedPacketMessage(
  RedPacketDraft draft, {
  String senderId = 'user',
  String receiverId = '',
}) {
  return ChatMessage(
    role: 'user',
    content: '',
    type: MessageType.redPacket,
    redPacket: RedPacketData(
      amount: draft.amount,
      message: draft.message,
      senderId: senderId,
      receiverId: receiverId,
    ),
  );
}

import 'package:flutter/material.dart';

class ChatInputBar extends StatelessWidget {
  const ChatInputBar({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.isLoading,
    required this.onSend,
    required this.onMore,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isLoading;
  final VoidCallback onSend;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 5, 10, 8),
      child: SafeArea(
        top: false,
        child: Material(
          color: const Color(0xFFF7F7F7).withValues(alpha: 0.96),
          elevation: 4,
          shadowColor: Colors.black.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(24),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(7, 5, 7, 5),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    focusNode: focusNode,
                    minLines: 1,
                    maxLines: 5,
                    textInputAction: TextInputAction.newline,
                    decoration: const InputDecoration(
                      hintText: '输入消息',
                      hintStyle: TextStyle(
                        color: Color(0xFF9DA1A6),
                        fontSize: 16,
                      ),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 11,
                        vertical: 8,
                      ),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      isDense: true,
                    ),
                    style: const TextStyle(
                      fontSize: 16,
                      height: 1.35,
                      color: Color(0xFF171717),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                AnimatedBuilder(
                  animation: controller,
                  builder: (context, _) {
                    final hasText = controller.text.trim().isNotEmpty;
                    if (hasText) {
                      return SizedBox(
                        height: 38,
                        child: FilledButton(
                          onPressed: isLoading ? null : onSend,
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF07C160),
                            disabledBackgroundColor: const Color(0xFFB8DCC8),
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            minimumSize: const Size(0, 38),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(19),
                            ),
                          ),
                          child: const Text(
                            '发送',
                            style: TextStyle(fontSize: 15),
                          ),
                        ),
                      );
                    }

                    return IconButton(
                      tooltip: '更多功能',
                      onPressed: isLoading ? null : onMore,
                      icon: const Icon(Icons.add_circle_outline_rounded, size: 30),
                      color: const Color(0xFF2C2C2C),
                      padding: const EdgeInsets.all(4),
                      constraints: const BoxConstraints(
                        minWidth: 38,
                        minHeight: 38,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

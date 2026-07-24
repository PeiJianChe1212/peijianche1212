import 'package:flutter/material.dart';

class ChatInputBar extends StatelessWidget {
  const ChatInputBar({
    super.key,
    required this.controller,
    required this.isLoading,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool isLoading;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE8E8E8))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              minLines: 1,
              maxLines: 5,
              textInputAction: TextInputAction.send,
              decoration: InputDecoration(
                hintText: '输入消息…',
                filled: true,
                fillColor: const Color(0xFFF1F1F1),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 17,
                  vertical: 11,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: BorderSide.none,
                ),
              ),
              onSubmitted: (_) => onSend(),
            ),
          ),
          const SizedBox(width: 8),
          CircleAvatar(
            radius: 22,
            backgroundColor: isLoading
                ? Colors.grey.shade400
                : Colors.blueGrey.shade600,
            child: IconButton(
              tooltip: '发送',
              icon: const Icon(Icons.arrow_upward_rounded, color: Colors.white),
              onPressed: isLoading ? null : onSend,
            ),
          ),
        ],
      ),
    );
  }
}

import 'dart:io';

import 'package:flutter/material.dart';

import 'chat_input_bar.dart';
import 'chat_more_panel.dart';
import '../theme/peilink_theme_chrome.dart';

class ChatInputArea extends StatelessWidget {
  const ChatInputArea({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.isLoading,
    required this.isMorePanelOpen,
    required this.onSend,
    required this.onMore,
    required this.onInputTap,
    required this.onUserPersona,
    required this.onPickImage,
    required this.onRedPacket,
    required this.onChangeAvatar,
    required this.onUnavailable,
    this.pendingImagePath,
    this.onRemovePendingImage,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isLoading;
  final bool isMorePanelOpen;
  final VoidCallback onSend;
  final VoidCallback onMore;
  final VoidCallback onInputTap;
  final VoidCallback onUserPersona;
  final VoidCallback onPickImage;
  final VoidCallback onRedPacket;
  final VoidCallback onChangeAvatar;
  final ValueChanged<String> onUnavailable;
  final String? pendingImagePath;
  final VoidCallback? onRemovePendingImage;

  @override
  Widget build(BuildContext context) {
    return PeiLinkThemeChatComposer(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (pendingImagePath?.isNotEmpty == true)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 6, 14, 4),
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.file(
                        File(pendingImagePath!),
                        width: 72,
                        height: 72,
                        fit: BoxFit.cover,
                      ),
                    ),
                    Positioned(
                      right: 0,
                      top: 0,
                      child: IconButton.filled(
                        visualDensity: VisualDensity.compact,
                        iconSize: 16,
                        onPressed: onRemovePendingImage,
                        icon: const Icon(Icons.close),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ChatInputBar(
            controller: controller,
            focusNode: focusNode,
            isLoading: isLoading,
            onSend: onSend,
            onMore: onMore,
            isMorePanelOpen: isMorePanelOpen,
            onInputTap: onInputTap,
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: isMorePanelOpen
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Divider(height: 1, color: Color(0xFFE2E2E2)),
                      ChatMorePanel(
                        closeOnSelection: false,
                        onUserPersona: onUserPersona,
                        onPickImage: onPickImage,
                        onRedPacket: onRedPacket,
                        onChangeAvatar: onChangeAvatar,
                        onUnavailable: onUnavailable,
                      ),
                    ],
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

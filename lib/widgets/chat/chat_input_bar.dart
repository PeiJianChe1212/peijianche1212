import 'package:flutter/material.dart';

import '../../theme/app_dimensions.dart';
import '../../theme/app_text_styles.dart';
import '../theme/peilink_theme_chrome.dart';

class ChatInputBar extends StatelessWidget {
  const ChatInputBar({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.isLoading,
    required this.onSend,
    required this.onMore,
    this.isMorePanelOpen = false,
    this.onInputTap,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isLoading;
  final VoidCallback onSend;
  final VoidCallback onMore;
  final bool isMorePanelOpen;
  final VoidCallback? onInputTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 3, 10, 5),
      child: SafeArea(
        top: false,
        child: Material(
          color: Colors.white.withValues(alpha: 0.76),
          elevation: 0,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppDimensions.radiusLarge),
            side: BorderSide(
              color: const Color(0xFF8793E8).withValues(alpha: 0.20),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(7, 3, 7, 3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    focusNode: focusNode,
                    onTap: onInputTap,
                    minLines: 1,
                    maxLines: 5,
                    textInputAction: TextInputAction.newline,
                    decoration: const InputDecoration(
                      hintText: '说点什么…',
                      hintStyle: TextStyle(
                        color: Color(0xFF9DA1A6),
                        fontSize: 16,
                      ),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 11,
                        vertical: 6,
                      ),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      isDense: true,
                    ),
                    style: AppTextStyles.bodyCompact,
                  ),
                ),
                const SizedBox(width: 4),
                AnimatedBuilder(
                  animation: controller,
                  builder: (context, _) {
                    final hasText = controller.text.trim().isNotEmpty;
                    if (hasText) {
                      return SizedBox(
                        height: AppDimensions.inputControlHeight,
                        child: FilledButton(
                          onPressed: isLoading ? null : onSend,
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF7D89E6),
                            disabledBackgroundColor: const Color(0xFFC9CEEC),
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            minimumSize: const Size(
                              0,
                              AppDimensions.inputControlHeight,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                AppDimensions.radiusPill,
                              ),
                            ),
                          ),
                          child: const Text(
                            '发送',
                            style: TextStyle(fontSize: 15),
                          ),
                        ),
                      );
                    }

                    return PeiLinkThemeIconButton(
                      type: PeiLinkThemeIcon.more,
                      tooltip: isMorePanelOpen ? '收起功能栏' : '更多功能',
                      onPressed: isLoading ? null : onMore,
                      icon: AnimatedRotation(
                        turns: isMorePanelOpen ? 0.125 : 0,
                        duration: const Duration(milliseconds: 180),
                        child: const Icon(
                          Icons.add_circle_outline_rounded,
                          size: 27,
                        ),
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

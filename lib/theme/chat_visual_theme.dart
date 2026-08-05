import 'package:flutter/material.dart';

enum ChatBubbleTailStyle { none, rounded }

@immutable
class ChatBubbleTheme {
  const ChatBubbleTheme({
    required this.id,
    required this.name,
    required this.userBubbleColor,
    required this.aiBubbleColor,
    required this.borderRadius,
    required this.tailStyle,
  });

  final String id;
  final String name;
  final Color userBubbleColor;
  final Color aiBubbleColor;
  final double borderRadius;
  final ChatBubbleTailStyle tailStyle;
}

@immutable
class ChatFontTheme {
  const ChatFontTheme({
    required this.id,
    required this.name,
    this.fontFamily,
    this.fontFamilyFallback = const [],
    this.fontWeight = FontWeight.w500,
  });

  final String id;
  final String name;
  final String? fontFamily;
  final List<String> fontFamilyFallback;
  final FontWeight fontWeight;
}

abstract final class ChatVisualThemeCatalog {
  static const ChatBubbleTheme minimal = ChatBubbleTheme(
    id: 'minimal',
    name: 'PeiLink 蓝蝶',
    userBubbleColor: Color(0xFFDCE3FF),
    aiBubbleColor: Color(0xF2FFFFFF),
    borderRadius: 18,
    tailStyle: ChatBubbleTailStyle.rounded,
  );
  static const ChatBubbleTheme qqRounded = ChatBubbleTheme(
    id: 'qq_rounded',
    name: 'QQ圆润款',
    userBubbleColor: Color(0xFFFFD9DF),
    aiBubbleColor: Color(0xF5FFFFFF),
    borderRadius: 18,
    tailStyle: ChatBubbleTailStyle.rounded,
  );
  static const ChatBubbleTheme cloud = ChatBubbleTheme(
    id: 'soft_cloud',
    name: '云朵款',
    userBubbleColor: Color(0xFFE0EDFF),
    aiBubbleColor: Color(0xF2FFFFFF),
    borderRadius: 22,
    tailStyle: ChatBubbleTailStyle.rounded,
  );
  static const ChatBubbleTheme glass = ChatBubbleTheme(
    id: 'glass',
    name: '玻璃款',
    userBubbleColor: Color(0xB8CFE8F4),
    aiBubbleColor: Color(0xB8FFFFFF),
    borderRadius: 16,
    tailStyle: ChatBubbleTailStyle.none,
  );
  static const bubbleThemes = [minimal, qqRounded, cloud, glass];

  static const ChatFontTheme systemFont = ChatFontTheme(
    id: 'system',
    name: '清爽黑体',
    fontFamily: 'PingFang SC',
    fontFamilyFallback: [
      'Source Han Sans SC',
      'Noto Sans CJK SC',
      'Microsoft YaHei',
      'sans-serif',
    ],
    fontWeight: FontWeight.w400,
  );
  static const ChatFontTheme hardPen = ChatFontTheme(
    id: 'hard_pen',
    name: '硬笔行书',
    fontFamily: 'FZKai-Z03',
    fontFamilyFallback: ['STXingkai', 'FZKai-Z03', 'KaiTi', 'serif'],
    fontWeight: FontWeight.w500,
  );
  static const ChatFontTheme kai = ChatFontTheme(
    id: 'kai',
    name: '楷体',
    fontFamily: 'KaiTi',
    fontFamilyFallback: ['STKaiti', 'serif'],
  );
  static const ChatFontTheme gentleRounded = ChatFontTheme(
    id: 'gentle_rounded',
    name: '温柔圆体',
    fontFamily: 'YouYuan',
    fontFamilyFallback: [
      'Yuanti SC',
      'HarmonyOS Sans SC',
      'Microsoft YaHei',
      'sans-serif',
    ],
  );
  static const ChatFontTheme tech = ChatFontTheme(
    id: 'tech',
    name: '科技字体',
    fontFamily: 'Consolas',
    fontFamilyFallback: ['Roboto Mono', 'monospace'],
  );
  static const fontThemes = [systemFont, hardPen, kai, gentleRounded, tech];
}

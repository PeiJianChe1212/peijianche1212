import 'package:flutter/material.dart';

enum ChatBubbleTailStyle { none, rounded, brandWing, softRound }

@immutable
class ChatBubbleTheme {
  const ChatBubbleTheme({
    required this.id,
    required this.name,
    required this.userBubbleColor,
    required this.aiBubbleColor,
    required this.borderRadius,
    required this.tailStyle,
    this.border,
    this.highlight,
    this.cornerShape,
    this.shadows = const [
      BoxShadow(color: Color(0x06000000), blurRadius: 8, offset: Offset(0, 2)),
    ],
    this.description = '圆润、清晰，适合日常聊天',
  });

  final String id;
  final String name;
  final Color userBubbleColor;
  final Color aiBubbleColor;
  final double borderRadius;
  final ChatBubbleTailStyle tailStyle;
  final Border? border;
  final Gradient? highlight;
  final BorderRadius? cornerShape;
  final List<BoxShadow> shadows;
  final String description;

  BoxDecoration decoration({required bool isUser}) => BoxDecoration(
    color: isUser ? userBubbleColor : aiBubbleColor,
    border: border,
    gradient: highlight,
    borderRadius: cornerShape == null
        ? BorderRadius.circular(borderRadius)
        : (isUser
              ? BorderRadius.only(
                  topLeft: cornerShape!.topRight,
                  topRight: cornerShape!.topLeft,
                  bottomLeft: cornerShape!.bottomRight,
                  bottomRight: cornerShape!.bottomLeft,
                )
              : cornerShape),
    boxShadow: shadows,
  );
}

@immutable
class ChatFontTheme {
  const ChatFontTheme({
    required this.id,
    required this.name,
    this.fontFamily,
    this.isAvailable = true,
    this.fontFamilyFallback = const [],
    this.fontWeight = FontWeight.w500,
  });

  final String id;
  final String name;
  final String? fontFamily;

  /// Only system fonts or bundled, verified font assets may be offered.
  final bool isAvailable;

  ChatFontTheme get effectiveFont =>
      isAvailable ? this : ChatVisualThemeCatalog.systemFont;
  final List<String> fontFamilyFallback;
  final FontWeight fontWeight;
}

abstract final class ChatVisualThemeCatalog {
  static const ChatBubbleTheme minimal = ChatBubbleTheme(
    id: 'minimal',
    name: 'PeiLink 蓝蝶',
    userBubbleColor: Color(0xFFDCE3FF),
    aiBubbleColor: Color(0xF2FFFFFF),
    borderRadius: 14,
    tailStyle: ChatBubbleTailStyle.brandWing,
    border: Border.fromBorderSide(
      BorderSide(color: Color(0x708A9AC8), width: .8),
    ),
    shadows: [
      BoxShadow(color: Color(0x107080AD), blurRadius: 5, offset: Offset(0, 2)),
    ],
    description: 'PeiLink 官方款 · 精致短翼 · 柔和蓝紫边缘',
  );
  static const ChatBubbleTheme qqRounded = ChatBubbleTheme(
    id: 'qq_rounded',
    name: 'QQ圆润款',
    userBubbleColor: Color(0xFFFFD9DF),
    aiBubbleColor: Color(0xF5FFFFFF),
    borderRadius: 32,
    tailStyle: ChatBubbleTailStyle.softRound,
    shadows: [
      BoxShadow(color: Color(0x146E4852), blurRadius: 6, offset: Offset(0, 3)),
    ],
    description: '饱满胶囊 · 短圆尾巴',
  );
  static const ChatBubbleTheme cloud = ChatBubbleTheme(
    id: 'soft_cloud',
    name: '云朵款',
    userBubbleColor: Color(0xFFE0EDFF),
    aiBubbleColor: Color(0xF2FFFFFF),
    borderRadius: 26,
    tailStyle: ChatBubbleTailStyle.none,
    cornerShape: BorderRadius.only(
      topLeft: Radius.circular(30),
      topRight: Radius.circular(14),
      bottomLeft: Radius.circular(12),
      bottomRight: Radius.circular(28),
    ),
    shadows: [
      BoxShadow(
        color: Color(0x228CACC7),
        blurRadius: 18,
        spreadRadius: 2,
        offset: Offset(0, 4),
      ),
    ],
    description: '不对称云团 · 无尾轻盈 · 扩散柔影',
  );
  static const ChatBubbleTheme glass = ChatBubbleTheme(
    id: 'glass',
    name: '玻璃款',
    userBubbleColor: Color(0xB8CFE8F4),
    aiBubbleColor: Color(0xB8FFFFFF),
    borderRadius: 10,
    tailStyle: ChatBubbleTailStyle.none,
    border: Border.fromBorderSide(
      BorderSide(color: Color(0xEEFFFFFF), width: 1.3),
    ),
    highlight: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Color(0xAAFFFFFF),
        Color(0x18FFFFFF),
        Color(0x08FFFFFF),
        Color(0x60FFFFFF),
        Color(0x18FFFFFF),
      ],
      stops: [0, .22, .48, .5, 1],
    ),
    shadows: [
      BoxShadow(color: Color(0x24647487), blurRadius: 9, offset: Offset(0, 4)),
      BoxShadow(color: Color(0x30FFFFFF), blurRadius: 1, offset: Offset(0, -1)),
    ],
    description: '半透明玻璃 · 折光高光 · 清晰亮边',
  );
  static const paper = ChatBubbleTheme(
    id: 'paper_note',
    name: '纸笺',
    userBubbleColor: Color(0xFFF3EBD7),
    aiBubbleColor: Color(0xFFFFFBF1),
    borderRadius: 8,
    tailStyle: ChatBubbleTailStyle.none,
    border: Border.fromBorderSide(BorderSide(color: Color(0xFFD8CFBB))),
    shadows: [
      BoxShadow(color: Color(0x10000000), offset: Offset(0, 3), blurRadius: 1),
    ],
    description: '暖纸色 · 小圆角 · 细边框',
  );
  static const candy = ChatBubbleTheme(
    id: 'milk_candy',
    name: '奶糖',
    userBubbleColor: Color(0xFFF5DEE7),
    aiBubbleColor: Color(0xFFEEE8F7),
    borderRadius: 28,
    tailStyle: ChatBubbleTailStyle.rounded,
    border: Border.fromBorderSide(
      BorderSide(color: Color(0xCCFFFFFF), width: 1.5),
    ),
    shadows: [
      BoxShadow(color: Color(0x187D6079), offset: Offset(0, 4), blurRadius: 12),
    ],
    description: '饱满大圆角 · 柔软奶糖色',
  );
  static const outline = ChatBubbleTheme(
    id: 'minimal_outline',
    name: '极简线框',
    userBubbleColor: Color(0xF5F4F7F8),
    aiBubbleColor: Color(0xF5FFFFFF),
    borderRadius: 12,
    tailStyle: ChatBubbleTailStyle.none,
    border: Border.fromBorderSide(
      BorderSide(color: Color(0xFFB4BEC5), width: 1.2),
    ),
    shadows: [],
    description: '浅底细线 · 无阴影',
  );
  static const glimmer = ChatBubbleTheme(
    id: 'soft_glimmer',
    name: '微光',
    userBubbleColor: Color(0xFFE4F0F1),
    aiBubbleColor: Color(0xFFF4F6FE),
    borderRadius: 18,
    tailStyle: ChatBubbleTailStyle.none,
    border: Border.fromBorderSide(
      BorderSide(color: Color(0xFFFFFFFF), width: 1.5),
    ),
    shadows: [
      BoxShadow(color: Color(0x4297BFCF), blurRadius: 14, spreadRadius: 1),
      BoxShadow(color: Color(0x0D526D80), offset: Offset(0, 2), blurRadius: 4),
    ],
    description: '柔和边缘光 · 清透浅色',
  );
  static const journal = ChatBubbleTheme(
    id: 'journal_card',
    name: '手账',
    userBubbleColor: Color(0xFFE8EEDA),
    aiBubbleColor: Color(0xFFFFF1DD),
    borderRadius: 14,
    tailStyle: ChatBubbleTailStyle.none,
    cornerShape: BorderRadius.only(
      topLeft: Radius.circular(3),
      topRight: Radius.circular(16),
      bottomLeft: Radius.circular(16),
      bottomRight: Radius.circular(6),
    ),
    border: Border.fromBorderSide(BorderSide(color: Color(0xFFC9C4AE))),
    shadows: [BoxShadow(color: Color(0x26A29A7D), offset: Offset(3, 3))],
    description: '不对称圆角 · 便签叠层',
  );
  static const bubbleThemes = [
    minimal,
    qqRounded,
    cloud,
    glass,
    paper,
    candy,
    outline,
    glimmer,
    journal,
  ];

  static const ChatFontTheme systemFont = ChatFontTheme(
    id: 'system',
    name: '清爽黑体',
    fontFamily: 'sans-serif',
    fontFamilyFallback: [
      'Source Han Sans SC',
      'Noto Sans CJK SC',
      'Microsoft YaHei',
      'sans-serif',
    ],
    fontWeight: FontWeight.w400,
  );

  /// CJK fallback chain used by every bundled decoration font. Ma Shan Zheng
  /// and Zen Maru Gothic do not cover all simplified glyphs, so a missing glyph
  /// must resolve here instead of rendering tofu.
  static const List<String> _cjkFallback = [
    'PeiLinkKai',
    'Source Han Sans SC',
    'Noto Sans CJK SC',
    'sans-serif',
  ];

  static const ChatFontTheme hardPen = ChatFontTheme(
    id: 'hard_pen',
    name: '手写体',
    fontFamily: 'PeiLinkHandwriting',
    fontFamilyFallback: _cjkFallback,
    fontWeight: FontWeight.w400,
  );
  static const ChatFontTheme kai = ChatFontTheme(
    id: 'kai',
    name: '楷体',
    fontFamily: 'PeiLinkKai',
    fontFamilyFallback: _cjkFallback,
    fontWeight: FontWeight.w400,
  );
  static const ChatFontTheme gentleRounded = ChatFontTheme(
    id: 'gentle_rounded',
    name: '温柔圆体',
    fontFamily: 'PeiLinkGentleRounded',
    fontFamilyFallback: _cjkFallback,
    fontWeight: FontWeight.w400,
  );
  static const ChatFontTheme tech = ChatFontTheme(
    id: 'tech',
    name: '科技字体',
    fontFamily: 'PeiLinkTechMono',
    fontFamilyFallback: ['PeiLinkTechMono', 'monospace'],
    fontWeight: FontWeight.w400,
  );
  static const fontThemes = [systemFont, hardPen, kai, gentleRounded, tech];
}

import 'package:flutter/widgets.dart';

import '../services/peilink_appearance_service.dart';
import '../widgets/theme/peilink_theme_scope.dart';
import 'chat_visual_theme.dart';

ChatBubbleTheme effectiveBubbleTheme(BuildContext context) {
  final appearance = PeiLinkAppearanceScope.of(context);
  return appearance.bubbleThemeMode == BubbleThemeMode.custom
      ? appearance.bubbleTheme
      : PeiLinkThemeScope.of(context).defaultBubbleTheme;
}

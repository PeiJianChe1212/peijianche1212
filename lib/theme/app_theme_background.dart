import 'package:flutter/material.dart';

import 'theme_background.dart';
import '../services/peilink_appearance_service.dart';

abstract final class AppThemeBackground {
  static const ThemeBackground defaultLight = ThemeBackground(
    id: 'default_light',
    name: '默认浅色',
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFF8FAFB), Color(0xFFEAF2F5)],
    ),
    opacity: 0.92,
  );

  static const ThemeBackground starryAiSpace = ThemeBackground(
    id: 'starry_ai_space',
    name: '星夜 AI 空间',
    imagePath: 'assets/backgrounds/starry_ai_space.png',
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFF07172D), Color(0xFF163E69)],
    ),
    opacity: 0.72,
  );

  static const ThemeBackground morningMistSky = ThemeBackground(
    id: 'morning_mist_sky',
    name: '晨雾天空',
    imagePath: 'assets/backgrounds/morning_mist_sky.png',
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFF8FBFF), Color(0xFFDCEBFA)],
    ),
    opacity: 0.76,
  );

  static const ThemeBackground silverMoonNight = ThemeBackground(
    id: 'silver_moon_night',
    name: '银白月夜',
    imagePath: 'assets/backgrounds/silver_moon_night.png',
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFF1B2D46), Color(0xFFC8D9E8)],
    ),
    opacity: 0.7,
  );

  static const ThemeBackground cityNeonNight = ThemeBackground(
    id: 'city_neon_night',
    name: '城市夜景',
    imagePath: 'assets/backgrounds/city_neon_night.png',
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFF101928), Color(0xFF233A55)],
    ),
    opacity: 0.7,
  );

  static const ThemeBackground mirrorLakeFantasy = ThemeBackground(
    id: 'mirror_lake_fantasy',
    name: '镜池幻想',
    imagePath: 'assets/backgrounds/mirror_lake_fantasy.png',
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFF080B10), Color(0xFF4B5967)],
    ),
    opacity: 0.68,
  );

  static const ThemeBackground catPawBlush = ThemeBackground(
    id: 'cat_paw_blush',
    name: '小猫爪印',
    imagePath: 'assets/backgrounds/simple_pack/cat_paw_blush.png',
    gradient: LinearGradient(colors: [Color(0xFFFFFDFC), Color(0xFFFFF8F8)]),
    opacity: 0.82,
  );

  static const ThemeBackground starButterflyBlue = ThemeBackground(
    id: 'star_butterfly_blue',
    name: '星点蝴蝶',
    imagePath: 'assets/backgrounds/simple_pack/star_butterfly_blue.png',
    gradient: LinearGradient(colors: [Color(0xFFFFFFFF), Color(0xFFF7FBFF)]),
    opacity: 0.8,
  );

  static const ThemeBackground creamBear = ThemeBackground(
    id: 'cream_bear',
    name: '奶油小熊',
    imagePath: 'assets/backgrounds/simple_pack/cream_bear.png',
    gradient: LinearGradient(colors: [Color(0xFFFFFCF7), Color(0xFFFFF8F2)]),
    opacity: 0.8,
  );

  static const ThemeBackground mistStar = ThemeBackground(
    id: 'mist_star',
    name: '雾灰小星',
    imagePath: 'assets/backgrounds/simple_pack/mist_star.png',
    gradient: LinearGradient(colors: [Color(0xFFFAFAF9), Color(0xFFF5F4F3)]),
    opacity: 0.78,
  );

  static const ThemeBackground lavenderFlower = ThemeBackground(
    id: 'lavender_flower',
    name: '浅紫花朵',
    imagePath: 'assets/backgrounds/simple_pack/lavender_flower.png',
    gradient: LinearGradient(colors: [Color(0xFFFDFCFF), Color(0xFFF7F4FF)]),
    opacity: 0.8,
  );

  static const ThemeBackground softCloudBlue = ThemeBackground(
    id: 'soft_cloud_blue',
    name: '云朵柔蓝',
    imagePath: 'assets/backgrounds/simple_pack/soft_cloud_blue.png',
    gradient: LinearGradient(colors: [Color(0xFFFCFEFF), Color(0xFFF4FAFE)]),
    opacity: 0.8,
  );

  static const List<ThemeBackground> builtInPack = [
    catPawBlush,
    starButterflyBlue,
    creamBear,
    mistStar,
    lavenderFlower,
    softCloudBlue,
  ];

  static const List<ThemeBackground> legacyAtmospherePack = [
    starryAiSpace,
    morningMistSky,
    silverMoonNight,
    cityNeonNight,
    mirrorLakeFantasy,
    defaultLight,
  ];

  static const ThemeBackground current = catPawBlush;
}

/// 页面内容之下的统一主题背景层。
///
/// [backgroundImage] 为后续角色、用户自定义和世界动态图片背景预留；
/// 背景透明度只作用于背景层，不会降低页面内容的可读性。
class ThemeBackgroundContainer extends StatelessWidget {
  const ThemeBackgroundContainer({
    super.key,
    required this.child,
    this.background,
    this.backgroundImage,
    this.imageFit = BoxFit.cover,
  });

  final Widget child;
  final ThemeBackground? background;
  final ImageProvider<Object>? backgroundImage;
  final BoxFit imageFit;

  @override
  Widget build(BuildContext context) {
    final resolvedBackground =
        background ?? PeiLinkAppearanceScope.of(context).background;
    final configuredImage = resolvedBackground.imagePath;
    final resolvedImage =
        backgroundImage ??
        (configuredImage == null ? null : AssetImage(configuredImage));
    return ThemeBackgroundScope(
      background: resolvedBackground,
      child: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            key: ValueKey('theme-background-${resolvedBackground.id}'),
            decoration: BoxDecoration(gradient: resolvedBackground.gradient),
          ),
          if (resolvedImage != null)
            Opacity(
              opacity: resolvedBackground.opacity,
              child: Image(image: resolvedImage, fit: imageFit),
            ),
          child,
        ],
      ),
    );
  }
}

class ThemeBackgroundScope extends InheritedWidget {
  const ThemeBackgroundScope({
    super.key,
    required this.background,
    required super.child,
  });

  final ThemeBackground background;

  static ThemeBackground of(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<ThemeBackgroundScope>()
            ?.background ??
        AppThemeBackground.current;
  }

  @override
  bool updateShouldNotify(ThemeBackgroundScope oldWidget) {
    return background != oldWidget.background;
  }
}

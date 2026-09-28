import 'package:flutter/material.dart';

import '../../services/peilink_appearance_service.dart';
import '../../services/peilink_theme_service.dart';
import '../../widgets/chat/chat_bubble_surface.dart';
import '../../widgets/chat/message_bubble.dart';
import '../../theme/app_theme_background.dart';
import '../../theme/chat_visual_theme.dart';
import '../../theme/theme_background.dart';
import '../../theme/theme_background_surface.dart';
import '../../theme/peilink_theme_config.dart';
import '../../widgets/theme/peilink_theme_scope.dart';
import '../../widgets/theme/peilink_themed_avatar.dart';

class ThemeDecorationPage extends StatefulWidget {
  const ThemeDecorationPage({super.key});

  @override
  State<ThemeDecorationPage> createState() => _ThemeDecorationPageState();
}

class _ThemeDecorationPageState extends State<ThemeDecorationPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 6, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appearance = PeiLinkAppearanceScope.of(context);
    final themes = PeiLinkThemeScope.controllerOf(context);
    return AnimatedBuilder(
      animation: Listenable.merge([appearance, themes]),
      builder: (context, _) => Scaffold(
        backgroundColor: const Color(0xFFFCFAFA),
        appBar: AppBar(
          title: const Text('个性装扮'),
          centerTitle: true,
          backgroundColor: const Color(0xFFFCFAFA),
          surfaceTintColor: Colors.transparent,
          bottom: TabBar(
            controller: _tabs,
            isScrollable: true,
            tabAlignment: TabAlignment.center,
            indicatorColor: const Color(0xFFFF8498),
            labelColor: const Color(0xFF252525),
            unselectedLabelColor: const Color(0xFF777777),
            tabs: const [
              Tab(text: '推荐'),
              Tab(text: '背景'),
              Tab(text: '头像框'),
              Tab(text: '聊天气泡'),
              Tab(text: '底部导航'),
              Tab(text: '字体'),
            ],
          ),
        ),
        body: TabBarView(
          controller: _tabs,
          children: [
            _RecommendTab(appearance: appearance, themes: themes, tabs: _tabs),
            _BackgroundTab(themes: themes),
            _AvatarFrameTab(themes: themes),
            _BubbleTab(appearance: appearance, themes: themes),
            _BottomNavigationTab(themes: themes),
            _FontTab(appearance: appearance),
          ],
        ),
      ),
    );
  }
}

class _RecommendTab extends StatelessWidget {
  const _RecommendTab({
    required this.appearance,
    required this.themes,
    required this.tabs,
  });

  final PeiLinkAppearanceController appearance;
  final PeiLinkThemeController themes;
  final TabController tabs;

  @override
  Widget build(BuildContext context) {
    final catalog = themes.registry.chatThemes;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        const Text(
          '当前主题',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        PeiLinkThemePreviewCard(theme: themes.chatTheme, large: true),
        const SizedBox(height: 20),
        const Text(
          '主题装扮',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        for (final theme in catalog) ...[
          PeiLinkThemePreviewCard(
            key: ValueKey('theme-card-${theme.id}'),
            theme: theme,
            applied: themes.selectedChatThemeId == theme.id,
            onApply: () async {
              await themes.applyFullTheme(theme.id);
              await appearance.followThemeBubble();
            },
          ),
          const SizedBox(height: 12),
        ],
        Row(
          children: [
            const Expanded(
              child: Text('气泡', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
            TextButton(
              key: const ValueKey('bubble-follow-theme'),
              onPressed:
                  appearance.bubbleThemeMode == BubbleThemeMode.followTheme
                  ? null
                  : appearance.followThemeBubble,
              child: Text(
                appearance.bubbleThemeMode == BubbleThemeMode.followTheme
                    ? '跟随主题 · 使用中'
                    : '切换为跟随主题',
              ),
            ),
            TextButton(
              onPressed: () => tabs.animateTo(3),
              child: const Text('自定义'),
            ),
          ],
        ),
        const SizedBox(height: 22),
        _SectionTitle(title: '背景推荐', onAll: () => tabs.animateTo(1)),
        const SizedBox(height: 10),
        SizedBox(
          height: 116,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: AppThemeBackground.builtInPack.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final item = AppThemeBackground.builtInPack[index];
              return _BackgroundChoice(
                item: item,
                selected: appearance.background.id == item.id,
                onTap: () => appearance.setBackground(item),
              );
            },
          ),
        ),
        const SizedBox(height: 20),
        _SectionTitle(title: '聊天气泡推荐', onAll: () => tabs.animateTo(3)),
        const SizedBox(height: 10),
        ...ChatVisualThemeCatalog.bubbleThemes
            .take(3)
            .map(
              (item) => _BubbleChoice(
                item: item,
                selected: appearance.bubbleTheme.id == item.id,
                onTap: () => appearance.setBubbleTheme(item),
              ),
            ),
        const SizedBox(height: 14),
        _SectionTitle(title: '字体推荐', onAll: () => tabs.animateTo(3)),
        ...ChatVisualThemeCatalog.fontThemes
            .take(4)
            .map(
              (item) => _FontChoice(
                item: item,
                selected: appearance.fontTheme.id == item.id,
                onTap: () => appearance.setFontTheme(item),
              ),
            ),
      ],
    );
  }
}

class PeiLinkThemePreviewCard extends StatelessWidget {
  const PeiLinkThemePreviewCard({
    super.key,
    required this.theme,
    this.applied = false,
    this.large = false,
    this.onApply,
  });
  final PeiLinkThemeConfig theme;
  final bool applied;
  final bool large;
  final VoidCallback? onApply;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .82),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(
        color: applied ? const Color(0xFF6988C7) : const Color(0xFFE0E6F0),
      ),
    ),
    child: Column(
      children: [
        SizedBox(
          height: large ? 210 : 150,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: ThemeBackgroundContainer(
              background: theme.chatBackground,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    Container(
                      height: 22,
                      decoration: BoxDecoration(
                        color: theme.topBarTheme.background,
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    const Spacer(),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        width: 100,
                        height: 30,
                        decoration: theme.defaultBubbleTheme.decoration(
                          isUser: false,
                        ),
                      ),
                    ),
                    const SizedBox(height: 7),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Container(
                        width: 86,
                        height: 30,
                        decoration: theme.defaultBubbleTheme.decoration(
                          isUser: true,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Row(
                      children: [
                        PeiLinkThemedAvatar(
                          size: 30,
                          role: PeiLinkAvatarRole.character,
                          frame: theme.avatarFrameTheme.character,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Container(
                            height: 26,
                            decoration: BoxDecoration(
                              color: theme.bottomBarTheme.background,
                              border: Border.all(
                                color: theme.bottomBarTheme.border,
                              ),
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    theme.name,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    theme.subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF758198),
                    ),
                  ),
                ],
              ),
            ),
            FilledButton(
              onPressed: applied ? null : onApply,
              child: Text(applied ? '使用中' : '应用'),
            ),
          ],
        ),
      ],
    ),
  );
}

class _BackgroundTab extends StatelessWidget {
  const _BackgroundTab({required this.themes});
  final PeiLinkThemeController themes;

  @override
  Widget build(BuildContext context) => GridView.builder(
    padding: const EdgeInsets.all(16),
    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: 2,
      childAspectRatio: 0.78,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
    ),
    itemCount: themes.registry.backgroundRegistry.ids.length + 1,
    itemBuilder: (context, index) {
      if (index == 0) {
        return _ComponentChoice(
          title: '跟随主题',
          selected: themes.backgroundOverrideId == null,
          onTap: () => themes.setBackgroundOverride(null),
          icon: Icons.auto_awesome_rounded,
        );
      }
      final id = themes.registry.backgroundRegistry.ids[index - 1];
      final item = themes.registry.backgroundRegistry.resolve(id)!;
      return _BackgroundChoice(
        item: item,
        selected: themes.backgroundOverrideId == id,
        onTap: () => themes.setBackgroundOverride(id),
        large: true,
      );
    },
  );
}

class _BubbleTab extends StatelessWidget {
  const _BubbleTab({required this.appearance, required this.themes});
  final PeiLinkAppearanceController appearance;
  final PeiLinkThemeController themes;

  @override
  Widget build(BuildContext context) => ListView(
    key: const Key('bubble-theme-list'),
    padding: const EdgeInsets.all(16),
    children: [
      _ComponentChoice(
        title: '跟随主题',
        selected: appearance.bubbleThemeMode == BubbleThemeMode.followTheme,
        onTap: () async {
          await appearance.followThemeBubble();
          try {
            await themes.setBubbleOverride(null);
          } catch (_) {
            // Widget tests and preview hosts may not provide platform storage.
          }
        },
        icon: Icons.auto_awesome_rounded,
      ),
      ...ChatVisualThemeCatalog.bubbleThemes.map(
        (item) => _BubbleChoice(
          item: item,
            selected: appearance.bubbleTheme.id == item.id,
            onTap: () async {
              await appearance.setBubbleTheme(item);
              try {
                await themes.setBubbleOverride(item.id);
              } catch (_) {
                // The existing bubble selector remains the source of truth.
              }
            },
        ),
      ),
    ],
  );
}

class _AvatarFrameTab extends StatelessWidget {
  const _AvatarFrameTab({required this.themes});
  final PeiLinkThemeController themes;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      _ComponentChoice(
        title: '跟随主题',
        selected: themes.avatarFrameOverrideId == null,
        onTap: () => themes.setAvatarFrameOverride(null),
        icon: Icons.auto_awesome_rounded,
      ),
      for (final id in themes.registry.avatarFrameRegistry.ids)
        _ComponentChoice(
          title: id == 'default' ? '默认 / 无头像框' : '蝶梦白狐',
          selected: themes.avatarFrameOverrideId == id,
          onTap: () => themes.setAvatarFrameOverride(id),
          preview: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              PeiLinkThemedAvatar(
                size: 46,
                role: PeiLinkAvatarRole.user,
                frame: themes.registry.avatarFrameRegistry.resolve(id)?.user,
              ),
              const SizedBox(width: 8),
              PeiLinkThemedAvatar(
                size: 46,
                role: PeiLinkAvatarRole.character,
                frame: themes.registry.avatarFrameRegistry
                    .resolve(id)
                    ?.character,
              ),
            ],
          ),
        ),
    ],
  );
}

class _BottomNavigationTab extends StatelessWidget {
  const _BottomNavigationTab({required this.themes});
  final PeiLinkThemeController themes;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      _ComponentChoice(
        title: '跟随主题',
        selected: themes.bottomNavigationOverrideId == null,
        onTap: () => themes.setBottomNavigationOverride(null),
        icon: Icons.auto_awesome_rounded,
      ),
      for (final id in themes.registry.bottomNavigationRegistry.ids)
        _ComponentChoice(
          title: id == 'default' ? '默认' : '蝶梦白狐',
          selected: themes.bottomNavigationOverrideId == id,
          onTap: () => themes.setBottomNavigationOverride(id),
          icon: id == 'default'
              ? Icons.navigation_rounded
              : Icons.flutter_dash_rounded,
        ),
    ],
  );
}

class _ComponentChoice extends StatelessWidget {
  const _ComponentChoice({
    required this.title,
    required this.selected,
    required this.onTap,
    this.icon,
    this.preview,
  });
  final String title;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  final Widget? preview;

  @override
  Widget build(BuildContext context) => Card(
    color: selected ? const Color(0xFFF1F6FF) : Colors.white,
    child: ListTile(
      onTap: onTap,
      leading: preview ?? Icon(icon, color: const Color(0xFF5878B4)),
      title: Text(title),
      trailing: selected
          ? const Icon(Icons.check_circle, color: Color(0xFF5878B4))
          : null,
    ),
  );
}

class _FontTab extends StatelessWidget {
  const _FontTab({required this.appearance});
  final PeiLinkAppearanceController appearance;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: ChatVisualThemeCatalog.fontThemes
        .map(
          (item) => _FontChoice(
            item: item,
            selected: appearance.fontTheme.id == item.id,
            onTap: () => appearance.setFontTheme(item),
          ),
        )
        .toList(),
  );
}

// Kept for the existing background/font preview tabs.
// ignore: unused_element
class _ThemePreview extends StatelessWidget {
  const _ThemePreview({required this.appearance, required this.height});
  final PeiLinkAppearanceController appearance;
  final double height;

  @override
  Widget build(BuildContext context) {
    final background = appearance.background;
    final bubble = appearance.bubbleTheme;
    final font = appearance.fontTheme.effectiveFont;
    return SizedBox(
      height: height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: ThemeBackgroundContainer(
          background: background,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '主题预览',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: background.isDark
                        ? Colors.white
                        : const Color(0xFF353F51),
                  ),
                ),
                const Spacer(),
                _PreviewBubble(
                  text: '你好。',
                  isUser: false,
                  theme: bubble,
                  font: font,
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: _PreviewBubble(
                    text: '今天开心。',
                    isUser: true,
                    theme: bubble,
                    font: font,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PreviewBubble extends StatelessWidget {
  const _PreviewBubble({
    required this.text,
    required this.isUser,
    required this.theme,
    required this.font,
  });
  final String text;
  final bool isUser;
  final ChatBubbleTheme theme;
  final ChatFontTheme font;

  @override
  Widget build(BuildContext context) => ChatBubbleSurface(
    theme: theme,
    isUser: isUser,
    child: Text(
      text,
      style: TextStyle(
        fontFamily: font.fontFamily,
        fontFamilyFallback: font.fontFamilyFallback,
        fontWeight: font.fontWeight,
        fontSize: 16,
        height: 1.42,
        color: MessageBubble.textColorForRole(isUser ? 'user' : 'assistant'),
      ),
    ),
  );
}

class _BackgroundChoice extends StatelessWidget {
  const _BackgroundChoice({
    required this.item,
    required this.selected,
    required this.onTap,
    this.large = false,
  });
  final ThemeBackground item;
  final bool selected;
  final VoidCallback onTap;
  final bool large;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: SizedBox(
      width: large ? double.infinity : 78,
      child: Column(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: selected
                      ? const Color(0xFFFF8799)
                      : const Color(0xFFEAEAEA),
                  width: selected ? 2 : 1,
                ),
              ),
              padding: const EdgeInsets.all(2),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ThemeBackgroundSurface(background: item),
                    if (selected)
                      const Align(
                        alignment: Alignment.bottomRight,
                        child: Padding(
                          padding: EdgeInsets.all(6),
                          child: Icon(
                            Icons.check_circle,
                            color: Color(0xFFFF8799),
                            size: 19,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            item.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11.5),
          ),
        ],
      ),
    ),
  );
}

class _BubbleChoice extends StatelessWidget {
  const _BubbleChoice({
    required this.item,
    required this.selected,
    required this.onTap,
  });
  final ChatBubbleTheme item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    key: ValueKey('bubble-choice-${item.id}'),
    color: selected ? const Color(0xFFFFF4F6) : Colors.white,
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    item.name,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                if (selected)
                  const Icon(
                    Icons.check_circle,
                    color: Color(0xFFFF8799),
                    semanticLabel: '已选中',
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              item.description,
              style: const TextStyle(fontSize: 12, color: Color(0xFF777777)),
            ),
            const SizedBox(height: 12),
            BubbleThemePreview(theme: item),
          ],
        ),
      ),
    ),
  );
}

/// Uses the exact same shell, tail, padding and decoration as live messages.
class BubbleThemePreview extends StatelessWidget {
  const BubbleThemePreview({super.key, required this.theme});
  final ChatBubbleTheme theme;

  @override
  Widget build(BuildContext context) {
    final font = PeiLinkAppearanceScope.of(context).fontTheme.effectiveFont;
    return Column(
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: _PreviewBubble(
            text: '今天过得怎么样？',
            isUser: false,
            theme: theme,
            font: font,
          ),
        ),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerRight,
          child: _PreviewBubble(
            text: '还不错呀～',
            isUser: true,
            theme: theme,
            font: font,
          ),
        ),
      ],
    );
  }
}

class _FontChoice extends StatelessWidget {
  const _FontChoice({
    required this.item,
    required this.selected,
    required this.onTap,
  });
  final ChatFontTheme item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    color: selected ? const Color(0xFFFFF4F6) : Colors.white,
    child: ListTile(
      key: ValueKey('font-choice-${item.id}'),
      enabled: item.isAvailable,
      onTap: item.isAvailable ? onTap : null,
      leading: const CircleAvatar(
        backgroundColor: Color(0xFFFFF0F2),
        child: Text('Aa'),
      ),
      title: Text(item.name),
      subtitle: !item.isAvailable
          ? Text(selected ? '已选字体资源缺失，当前使用系统字体' : '字体资源未内置，暂不可用')
          : null,
      trailing: !item.isAvailable
          ? const Text('暂无预览')
          : Text(
              '今天天气真好呀～',
              key: ValueKey('font-preview-${item.id}'),
              style: TextStyle(
                fontFamily: item.fontFamily,
                fontFamilyFallback: item.fontFamilyFallback,
                fontWeight: item.fontWeight,
                color: selected
                    ? const Color(0xFFFF6F88)
                    : const Color(0xFF555555),
              ),
            ),
    ),
  );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.onAll});
  final String title;
  final VoidCallback onAll;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      TextButton(onPressed: onAll, child: const Text('全部')),
    ],
  );
}

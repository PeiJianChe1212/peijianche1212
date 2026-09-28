import 'package:flutter/material.dart';

import 'config/peilink_runtime.dart';
import 'pages/home_page.dart';
import 'services/character_registry_service.dart';
import 'services/peilink_appearance_service.dart';
import 'services/peilink_theme_service.dart';
import 'services/usage_timer_service.dart';
import 'theme/app_dimensions.dart';
import 'theme/app_text_styles.dart';
import 'widgets/theme/peilink_theme_scope.dart';

Future<void> main() => runPeiLink(PeiLinkBuild.user);

Future<void> runPeiLink(PeiLinkBuild build) async {
  WidgetsFlutterBinding.ensureInitialized();
  PeiLinkRuntime.configure(build);
  UsageTimerService.instance.initialize();
  bool? initialHasVisibleCharacter;
  if (build == PeiLinkBuild.user) {
    final results = await Future.wait<Object>([
      CharacterRegistryService().loadCharacters().then<Object>(
        (characters) => characters.isNotEmpty,
      ),
      Future<Object>.delayed(const Duration(seconds: 3), () => true),
    ]);
    initialHasVisibleCharacter = results.first as bool;
  } else {
    initialHasVisibleCharacter = await CharacterRegistryService()
        .loadCharacters()
        .then((characters) => characters.isNotEmpty);
  }
  runApp(PeiLinkApp(initialHasVisibleCharacter: initialHasVisibleCharacter));
}

class PeiLinkApp extends StatefulWidget {
  const PeiLinkApp({super.key, this.initialHasVisibleCharacter});

  final bool? initialHasVisibleCharacter;

  @override
  State<PeiLinkApp> createState() => _PeiLinkAppState();
}

class _PeiLinkAppState extends State<PeiLinkApp> {
  final _appearance = PeiLinkAppearanceController.instance;
  final _themes = PeiLinkThemeController.instance;

  @override
  void initState() {
    super.initState();
    _appearance.load();
    _themes.load();
  }

  @override
  Widget build(BuildContext context) {
    return PeiLinkThemeScope(
      controller: _themes,
      child: PeiLinkAppearanceScope(
        controller: _appearance,
        child: MaterialApp(
          title: PeiLinkRuntime.appName,
          debugShowCheckedModeBanner: false,
          builder: (context, child) => MediaQuery.withNoTextScaling(
            child: child ?? const SizedBox.shrink(),
          ),
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF8294EF),
              surface: const Color(0xFFF7F7FC),
            ),
            useMaterial3: true,
            fontFamily: 'sans-serif',
            textTheme: const TextTheme(
              titleLarge: AppTextStyles.pageTitle,
              titleMedium: AppTextStyles.sectionTitle,
              bodyLarge: AppTextStyles.body,
              bodyMedium: AppTextStyles.bodyCompact,
              bodySmall: AppTextStyles.caption,
            ),
            appBarTheme: const AppBarTheme(
              toolbarHeight: 52,
              titleTextStyle: AppTextStyles.pageTitle,
            ),
            listTileTheme: const ListTileThemeData(
              minVerticalPadding: 6,
              horizontalTitleGap: 12,
              contentPadding: EdgeInsets.symmetric(horizontal: 16),
            ),
            bottomNavigationBarTheme: const BottomNavigationBarThemeData(
              elevation: 6,
              selectedIconTheme: IconThemeData(
                size: AppDimensions.bottomNavigationIcon,
              ),
              unselectedIconTheme: IconThemeData(
                size: AppDimensions.bottomNavigationIcon,
              ),
            ),
          ),
          navigatorKey: UsageTimerService.instance.navigatorKey,
          navigatorObservers: [UsageTimerService.instance.routeObserver],
          home: HomePage(
            initialHasVisibleCharacter: widget.initialHasVisibleCharacter,
          ),
        ),
      ),
    );
  }
}

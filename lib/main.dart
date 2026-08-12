import 'package:flutter/material.dart';

import 'config/peilink_runtime.dart';
import 'pages/environment_bootstrap_page.dart';
import 'pages/home_page.dart';
import 'services/character_registry_service.dart';
import 'services/peilink_appearance_service.dart';
import 'theme/app_dimensions.dart';
import 'theme/app_text_styles.dart';

Future<void> main() => runPeiLink(PeiLinkBuild.user);

Future<void> runPeiLink(PeiLinkBuild build) async {
  WidgetsFlutterBinding.ensureInitialized();
  PeiLinkRuntime.configure(build);
  bool? initialHasVisibleCharacter;
  if (build == PeiLinkBuild.user) {
    final results = await Future.wait<Object>([
      CharacterRegistryService()
          .loadCharacters()
          .then<Object>((characters) => characters.isNotEmpty)
          .catchError((_) => false),
      Future<Object>.delayed(const Duration(seconds: 3), () => true),
    ]);
    initialHasVisibleCharacter = results.first as bool;
  }
  runApp(
    PeiJianCheApp(initialHasVisibleCharacter: initialHasVisibleCharacter),
  );
}

class PeiJianCheApp extends StatefulWidget {
  const PeiJianCheApp({super.key, this.initialHasVisibleCharacter});

  final bool? initialHasVisibleCharacter;

  @override
  State<PeiJianCheApp> createState() => _PeiJianCheAppState();
}

class _PeiJianCheAppState extends State<PeiJianCheApp> {
  final _appearance = PeiLinkAppearanceController.instance;

  @override
  void initState() {
    super.initState();
    _appearance.load();
  }

  @override
  Widget build(BuildContext context) {
    return PeiLinkAppearanceScope(
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
        home: PeiLinkRuntime.developerToolsEnabled
            ? const EnvironmentBootstrapPage()
            : HomePage(
                initialHasVisibleCharacter: widget.initialHasVisibleCharacter,
              ),
      ),
    );
  }
}

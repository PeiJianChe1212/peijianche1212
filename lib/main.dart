import 'package:flutter/material.dart';

import 'pages/home_page.dart';
import 'services/peilink_appearance_service.dart';
import 'theme/app_dimensions.dart';
import 'theme/app_text_styles.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PeiJianCheApp());
}

class PeiJianCheApp extends StatefulWidget {
  const PeiJianCheApp({super.key});

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
        title: 'PeiLink',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF8294EF),
            surface: const Color(0xFFF7F7FC),
          ),
          useMaterial3: true,
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
        home: const HomePage(),
      ),
    );
  }
}

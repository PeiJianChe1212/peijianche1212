import 'package:flutter/material.dart';

import 'pages/home_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PeiJianCheApp());
}

class PeiJianCheApp extends StatelessWidget {
  const PeiJianCheApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '裴简澈',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueGrey),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

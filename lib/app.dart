import 'package:flutter/material.dart';
import 'core/theme/app_theme.dart';
import 'features/navigation/presentation/screens/splash_screen.dart';

class AbakusApp extends StatelessWidget {
  const AbakusApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Abaküs One',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: const SplashScreen(),
    );
  }
}

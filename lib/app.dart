import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'constants.dart';
import 'providers/settings_provider.dart';
import 'screens/home_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/vfs_screen.dart';
import 'screens/models_screen.dart';

class KinoApp extends StatelessWidget {
  const KinoApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Select only themeMode so unrelated SettingsProvider updates do not
    // rebuild MaterialApp (and its inherited Theme/MediaQuery subtree).
    final themeMode = context.select<SettingsProvider, ThemeMode>(
      (s) => s.themeMode,
    );

    return MaterialApp(
      title: 'Kino',
      debugShowCheckedModeBanner: false,
      themeMode: themeMode,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      home: const HomeScreen(),
      routes: {
        '/settings': (context) => const SettingsScreen(),
        '/vfs': (context) => const VfsScreen(),
        '/models': (context) => const ModelsScreen(),
      },
    );
  }
}

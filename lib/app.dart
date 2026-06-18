import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'constants.dart';
import 'providers/settings_provider.dart';
import 'screens/home_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/vfs_screen.dart';
import 'screens/marketplace_screen.dart';

class ChatmorphismApp extends StatelessWidget {
  const ChatmorphismApp({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();

    return MaterialApp(
      title: 'ChatMorphism',
      debugShowCheckedModeBanner: false,
      themeMode: settings.themeMode,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      home: const HomeScreen(),
      routes: {
        '/settings': (context) => const SettingsScreen(),
        '/vfs': (context) => const VfsScreen(),
        '/marketplace': (context) => const MarketplaceScreen(),
      },
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'app.dart';
import 'database/database_helper.dart';
import 'providers/chat_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/vfs_provider.dart';
import 'services/tool_registry.dart';
import 'services/vfs/vfs_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DatabaseHelper.instance.database;

  final settingsProvider = SettingsProvider();
  await settingsProvider.initialize();

  final vfsService = VfsService();
  await vfsService.init();

  final toolRegistry = ToolRegistry();
  toolRegistry.init();

  final vfsProvider = VfsProvider();
  await vfsProvider.init();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settingsProvider),
        ChangeNotifierProvider(
          create: (_) => ChatProvider(settingsProvider)..initialize(),
        ),
        ChangeNotifierProvider.value(value: vfsProvider),
        ChangeNotifierProvider.value(value: toolRegistry),
      ],
      child: const KinoApp(),
    ),
  );
}

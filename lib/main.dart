import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'app.dart';
import 'database/database_helper.dart';
import 'providers/chat_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/vfs_provider.dart';
import 'services/vfs/vfs_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DatabaseHelper.instance.database;

  final settingsProvider = SettingsProvider();
  await settingsProvider.initialize();

  final vfsService = VfsService();
  await vfsService.init();

  final vfsProvider = VfsProvider();
  await vfsProvider.init();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settingsProvider),
        ChangeNotifierProvider(
          create: (_) {
            final chat = ChatProvider(settingsProvider);
            // Defer async init until after the first frame so create() does not
            // race with the initial InheritedWidget dependency wiring.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              chat.initialize();
            });
            return chat;
          },
        ),
        ChangeNotifierProvider.value(value: vfsProvider),
      ],
      child: const KinoApp(),
    ),
  );
}

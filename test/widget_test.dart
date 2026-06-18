import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:kino/app.dart';
import 'package:kino/database/database_helper.dart';
import 'package:kino/providers/chat_provider.dart';
import 'package:kino/providers/settings_provider.dart';

void main() {
  testWidgets('App renders home screen', (WidgetTester tester) async {
    await DatabaseHelper.instance.database;

    final settings = SettingsProvider();
    await settings.initialize();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: settings),
          ChangeNotifierProvider(
            create: (_) => ChatProvider(settings),
          ),
        ],
        child: const KinoApp(),
      ),
    );

    expect(find.text('Kino'), findsOneWidget);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:chatmorphism/app.dart';
import 'package:chatmorphism/database/database_helper.dart';
import 'package:chatmorphism/providers/chat_provider.dart';
import 'package:chatmorphism/providers/settings_provider.dart';

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
        child: const ChatmorphismApp(),
      ),
    );

    expect(find.text('ChatMorphism'), findsOneWidget);
  });
}

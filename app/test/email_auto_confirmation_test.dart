import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:luckyscan50/main.dart' show storeProvider;
import 'package:luckyscan50/notification_settings_page.dart';
import 'package:luckyscan50/data/wallet_store.dart';
import 'package:luckyscan50/data/email_notifications_client.dart';
import 'package:luckyscan50/data/notification_preferences.dart';

class _Database extends Fake implements Database {}

class _Store extends WalletStore {
  _Store() : super(_Database());
  final values = <String, String>{};
  @override
  Future<String?> setting(String key) async => values[key];
  @override
  Future<void> setSetting(String key, String value) async {
    values[key] = value;
  }
}

class _Email extends EmailNotificationsClient {
  int subscriptions = 0;
  @override
  Future<String> configure(
    WalletStore store,
    NotificationPreferences preferences,
  ) async {
    subscriptions++;
    await store.setSetting(emailStatusKey, 'pending');
    return 'pending';
  }
}

void main() {
  testWidgets(
    'finishing the email field requests confirmation without saving manually',
    (tester) async {
      final store = _Store();
      final email = _Email();
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('luckyscan50/notifications'),
        (_) async => true,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('luckyscan50/notifications'),
          null,
        ),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            storeProvider.overrideWithValue(store),
            emailSettingsClientFactoryProvider.overrideWithValue(() => email),
          ],
          child: const MaterialApp(home: NotificationSettingsPage()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(SwitchListTile, 'Receber avisos por email'),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byType(TextField));
      await tester.enterText(find.byType(TextField), 'reader@example.pt');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(email.subscriptions, 1);
      expect(
        find.text('Confirme o endereço na ligação recebida por email.'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
}

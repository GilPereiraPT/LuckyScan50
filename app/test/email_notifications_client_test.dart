import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:luckyscan50/data/email_notifications_client.dart';
import 'package:luckyscan50/data/notification_preferences.dart';
import 'package:luckyscan50/data/wallet_store.dart';
import 'package:luckyscan50/domain/wallet.dart';

class MemoryStore implements WalletStore {
  final values = <String, String>{};
  final tickets = <Receipt>[];
  @override
  Future<String?> setting(String key) async => values[key];
  @override
  Future<void> setSetting(String key, String value) async { values[key] = value; }
  @override
  Future<List<Receipt>> receipts() async => tickets;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('generates a stable installation token without Gmail credentials', () async {
    final store = MemoryStore();
    final client = EmailNotificationsClient(client: MockClient((_) async => http.Response('{}', 200)));
    addTearDown(client.close);
    final token = await client.token(store);
    expect(token, matches(RegExp(r'^[0-9a-f]{64}$')));
    expect(await client.token(store), token);
  });

  test('subscribes with explicit consent and waits for confirmation', () async {
    final store = MemoryStore();
    final client = EmailNotificationsClient(client: MockClient((request) async {
      expect(request.url.path, '/v1/email/subscription');
      expect(request.method, 'POST');
      expect(request.headers['Authorization'], startsWith('Bearer '));
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['consent'], isTrue);
      expect(body.containsKey('watches'), isFalse);
      return http.Response('{"status":"pending"}', 202);
    }));
    addTearDown(client.close);
    expect(await client.configure(store, const NotificationPreferences(
      email: 'reader@example.pt', emailConsent: true,
    )), 'pending');
  });

  test('does not upload a wallet before email confirmation', () async {
    final store = MemoryStore()..values[emailTokenKey] = 'a' * 64;
    var requests = 0;
    final client = EmailNotificationsClient(client: MockClient((request) async {
      requests++;
      expect(request.method, 'GET');
      return http.Response('{"status":"pending"}', 200);
    }));
    addTearDown(client.close);
    await client.uploadWatches(store, const NotificationPreferences(emailConsent: true));
    expect(requests, 1);
  });

  test('uploads only minimum fields after confirmation', () async {
    final store = MemoryStore()..values[emailTokenKey] = 'a' * 64;
    store.tickets.add(Receipt(
      id: 'receipt1', createdAt: '2026-10-20T12:00:00Z', source: 'manual',
      code: 'private-receipt-code', costCents: 250, imagePath: '/private/image.jpg',
      lines: [BetLine([1, 2, 3, 4, 5], [1, 2])], drawIds: ['083/2026'],
    ));
    final client = EmailNotificationsClient(client: MockClient((request) async {
      if (request.method == 'GET') return http.Response('{"status":"active"}', 200);
      expect(request.method, 'PUT');
      final payload = jsonDecode(request.body) as List;
      expect((payload.first as Map).keys.toSet(), {
        'id', 'drawIds', 'milhaoDrawIds', 'lines', 'milhaoCodes', 'receivedCents',
      });
      expect(request.body, isNot(contains('image.jpg')));
      expect(request.body, isNot(contains('private-receipt-code')));
      return http.Response('{"status":"active"}', 200);
    }));
    addTearDown(client.close);
    await client.uploadWatches(store, const NotificationPreferences(emailConsent: true));
  });

  test('disabling email revokes the existing server subscription', () async {
    final store = MemoryStore()..values[emailTokenKey] = 'a' * 64;
    final client = EmailNotificationsClient(client: MockClient((request) async {
      expect(request.method, 'DELETE');
      return http.Response('{"status":"revoked"}', 200);
    }));
    addTearDown(client.close);
    expect(await client.configure(store, const NotificationPreferences()), 'revoked');
  });

  test('unconfigured server is reported instead of claiming active delivery', () async {
    final client = EmailNotificationsClient(client: MockClient((_) async => http.Response('{}', 503)));
    addTearDown(client.close);
    await expectLater(client.configure(MemoryStore(), const NotificationPreferences(
      emailConsent: true, email: 'reader@example.pt',
    )), throwsFormatException);
  });
}

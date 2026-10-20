import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'notification_preferences.dart';
import 'wallet_store.dart';

const emailTokenKey = 'notifications.email.deviceToken';
const emailStatusKey = 'notifications.email.status';

class EmailNotificationsClient {
  EmailNotificationsClient({
    http.Client? client,
    this.base = 'https://luckyscan50-api.policlinicosdesantoandre.com',
  }) : client = client ?? http.Client();

  final http.Client client;
  final String base;

  Future<Map<String, dynamic>> request(
    String method,
    String path, {
    String? token,
    Object? body,
  }) async {
    final uri = Uri.parse('$base/v1/email/$path');
    if (uri.scheme != 'https' || uri.userInfo.isNotEmpty) {
      throw const FormatException('O serviço de email exige uma ligação HTTPS.');
    }
    final message = http.Request(method, uri)
      ..followRedirects = false
      ..headers['Content-Type'] = 'application/json';
    if (token != null) message.headers['Authorization'] = 'Bearer $token';
    if (body != null) message.body = jsonEncode(body);
    final response = await http.Response.fromStream(
      await client.send(message).timeout(const Duration(seconds: 12)),
    ).timeout(const Duration(seconds: 12));
    if (response.statusCode == 503 || response.statusCode == 404) {
      throw const FormatException(
        'O envio por Gmail ainda não está configurado no servidor. As notificações Android continuam independentes.',
      );
    }
    if (response.statusCode == 429) {
      throw const FormatException('Aguarde antes de pedir outro email de confirmação.');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw const FormatException('Não foi possível atualizar a subscrição de email.');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Resposta inválida do serviço de email.');
    }
    return decoded;
  }

  Future<String> token(WalletStore store) async {
    final existing = await store.setting(emailTokenKey);
    if (existing != null) return existing;
    final random = Random.secure();
    final generated = List.generate(
      32, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    await store.setSetting(emailTokenKey, generated);
    return generated;
  }

  Future<String> configure(
    WalletStore store,
    NotificationPreferences preferences,
  ) async {
    if (!preferences.emailConsent) {
      final existing = await store.setting(emailTokenKey);
      if (existing != null) {
        await request('DELETE', 'subscription', token: existing);
      }
      await store.setSetting(emailStatusKey, 'revoked');
      return 'revoked';
    }
    final result = await request('POST', 'subscription', token: await token(store), body: {
      'email': preferences.email.trim(),
      'consent': true,
      'preferences': {
        'results': preferences.results,
        'prizes': preferences.prizes,
        'expiry': preferences.expiry,
        'leadDays': preferences.leadDays,
      },
    });
    final status = result['status'] as String;
    await store.setSetting(emailStatusKey, status);
    return status;
  }

  Future<String> refresh(WalletStore store) async {
    final existing = await store.setting(emailTokenKey);
    if (existing == null) return 'not_subscribed';
    final result = await request('GET', 'subscription', token: existing);
    final status = result['status'] as String;
    await store.setSetting(emailStatusKey, status);
    return status;
  }

  Future<void> uploadWatches(WalletStore store, NotificationPreferences preferences) async {
    final existing = await store.setting(emailTokenKey);
    if (existing == null || await refresh(store) != 'active') return;
    final receipts = await store.receipts();
    final payload = preferences.prizes || preferences.expiry
        ? receipts.map((receipt) => {
            'id': receipt.id,
            'drawIds': receipt.drawIds,
            'milhaoDrawIds': receipt.milhaoDrawIds,
            'lines': receipt.lines.map((line) => line.toJson()).toList(),
            'milhaoCodes': receipt.milhaoCodes,
            'receivedCents': receipt.receivedCents,
          }).toList()
        : <Map<String, dynamic>>[];
    await request('PUT', 'watches', token: existing, body: payload);
  }

  void close() => client.close();
}

// Serialize updates and read the latest wallet inside the queue. A delayed
// upload must not overwrite a more recent payment/deletion with an old snapshot.
Future<void> _emailQueue = Future<void>.value();
Future<void> synchronizeEmailWallet(WalletStore store) {
  _emailQueue = _emailQueue.then((_) async {
    final client = EmailNotificationsClient();
    try {
      final preferences = await NotificationPreferences.load(store);
      if (!preferences.emailConsent) return;
      await client.uploadWatches(store, preferences);
      await store.setSetting('notifications.email.lastSyncError', '');
    } catch (_) {
      await store.setSetting('notifications.email.lastSyncError',
          'Não foi possível sincronizar os avisos por email. Os dados no servidor podem estar desatualizados.');
    } finally {
      client.close();
    }
  }).catchError((Object _) {
    // Never break the local wallet if its storage is closing or unavailable.
  });
  return _emailQueue;
}

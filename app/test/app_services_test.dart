import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:luckyscan50/data/app_services.dart';
import 'package:luckyscan50/data/wallet_store.dart';

class MemorySettings extends Fake implements WalletStore {
  final values = <String, String>{};
  @override
  Future<String?> setting(String key) async => values[key];
  @override
  Future<void> setSetting(String key, String value) async {
    values[key] = value;
  }
}

class MemoryCredentials implements PrivateAppStorage {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

void main() {
  test(
    'No requests or identifier before consent; unknown events ignored',
    () async {
      var requests = 0;
      final credentials = MemoryCredentials();
      final service = AppServices(
        store: MemorySettings(),
        version: '0.2.14+16',
        storage: credentials,
        client: MockClient((_) async {
          requests++;
          return http.Response('{}', 200);
        }),
      );
      addTearDown(service.dispose);
      await service.ready;
      await service.record('app_open');
      await service.record('purchase');
      expect(requests, 0);
      expect(credentials.values, isEmpty);
      expect(service.premium, isFalse);
    },
  );

  test(
    'Only allowlisted technical data is sent and duplicate openings are throttled',
    () async {
      final settings = MemorySettings()..values['metrics.consent.v1'] = 'true';
      final calls = <http.Request>[];
      final service = AppServices(
        store: settings,
        version: '0.2.14+16',
        storage: MemoryCredentials(),
        client: MockClient((request) async {
          calls.add(request);
          return http.Response(
            request.url.path.endsWith('register')
                ? '{"token":"metrics-credential"}'
                : '{"accepted":true}',
            request.url.path.endsWith('register') ? 201 : 200,
          );
        }),
      );
      addTearDown(service.dispose);
      await service.record('app_open');
      await service.record('app_open');
      await service.record('scan_camera');
      expect(calls.length, 3);
      final data = jsonDecode(calls.last.body) as Map;
      expect(data.keys.toSet(), {'eventId', 'event', 'version', 'platform'});
      expect(data['event'], 'scan_camera');
      expect(data['eventId'], matches(RegExp(r'^[a-f0-9]{32}$')));
      expect(calls.last.headers['Authorization'], 'Bearer metrics-credential');
      expect(settings.values.keys.any((key) => key.contains('Token')), isFalse);
    },
  );

  test(
    'Withdrawal waits for in-flight registration and deletes its token',
    () async {
      final settings = MemorySettings()..values['metrics.consent.v1'] = 'true';
      final credentials = MemoryCredentials();
      final registered = Completer<void>();
      final finish = Completer<void>();
      final calls = <String>[];
      final service = AppServices(
        store: settings,
        version: '0.2.14+16',
        storage: credentials,
        client: MockClient((request) async {
          calls.add('${request.method} ${request.url.path}');
          if (request.url.path.endsWith('register')) {
            registered.complete();
            await finish.future;
            return http.Response('{"token":"new-credential"}', 201);
          }
          return http.Response('{"deleted":true}', 200);
        }),
      );
      addTearDown(service.dispose);
      final recording = service.record('app_open');
      await registered.future;
      final withdrawal = service.setConsent(false);
      finish.complete();
      await recording;
      await withdrawal;
      expect(calls, [
        'POST /v1/app/metrics/register',
        'DELETE /v1/app/metrics',
      ]);
      expect(credentials.values, isEmpty);
      expect(service.consent, isFalse);
      expect(service.deletionPending, isFalse);
    },
  );

  test(
    'Offline deletion persists, then retries without sending new events',
    () async {
      final settings = MemorySettings()..values['metrics.consent.v1'] = 'true';
      final credentials = MemoryCredentials()
        ..values['metricsToken'] = 'credential';
      var offline = true;
      final calls = <String>[];
      final service = AppServices(
        store: settings,
        version: '0.2.14+16',
        storage: credentials,
        client: MockClient((request) async {
          calls.add(request.method);
          if (offline) throw const FormatException('offline');
          return http.Response('{"deleted":true}', 200);
        }),
      );
      addTearDown(service.dispose);
      await service.ready;
      await service.setConsent(false);
      expect(service.deletionPending, isTrue);
      expect(settings.values['metrics.delete.pending'], 'true');
      offline = false;
      await service.record('app_open');
      expect(calls, ['DELETE', 'DELETE']);
      expect(credentials.values, isEmpty);
      expect(service.deletionPending, isFalse);
    },
  );

  test('Owner is server-validated, then removed after revocation', () async {
    final credentials = MemoryCredentials();
    var revoked = false;
    final expires =
        DateTime.now().add(const Duration(days: 30)).millisecondsSinceEpoch ~/
        1000;
    final service = AppServices(
      store: MemorySettings(),
      version: '0.2.14+16',
      storage: credentials,
      client: MockClient((request) async {
        if (revoked) {
          return http.Response('{"error":"owner_session_invalid"}', 401);
        }
        return http.Response(
          jsonEncode({
            'token': 'owner-session',
            'tier': 'owner',
            'ads': false,
            'expiresAt': expires,
          }),
          200,
        );
      }),
    );
    addTearDown(service.dispose);
    await service.ready;
    await service.activateOwner('individual-key');
    expect(service.premium, isTrue);
    expect(service.adsAllowed, isFalse);
    expect(credentials.values['ownerToken'], 'owner-session');
    expect(credentials.values.values, isNot(contains('individual-key')));
    revoked = true;
    await service.refreshOwner();
    expect(service.premium, isFalse);
    expect(credentials.values['ownerToken'], isNull);
  });
  test(
    'Pending deletion is retried after restarting with consent disabled',
    () async {
      final settings = MemorySettings()
        ..values['metrics.consent.v1'] = 'false'
        ..values['metrics.delete.pending'] = 'true';
      final credentials = MemoryCredentials()
        ..values['metricsToken'] = 'pending-credential';
      final requests = <String>[];
      final service = AppServices(
        store: settings,
        version: '0.2.15+17',
        storage: credentials,
        client: MockClient((request) async {
          requests.add('${request.method} ${request.url.path}');
          return http.Response('{"deleted":true}', 200);
        }),
      );
      addTearDown(service.dispose);
      await service.ready;
      await service.record('scan_camera');
      expect(requests, ['DELETE /v1/app/metrics']);
      expect(credentials.values, isEmpty);
      expect(service.consent, isFalse);
      expect(service.deletionPending, isFalse);
    },
  );
}

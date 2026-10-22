import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'wallet_store.dart';

abstract class PrivateAppStorage {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class AndroidPrivateAppStorage implements PrivateAppStorage {
  static const channel = MethodChannel('luckyscan50/private_storage');
  @override
  Future<String?> read(String key) =>
      channel.invokeMethod<String>('read', {'key': key});
  @override
  Future<void> write(String key, String value) =>
      channel.invokeMethod<void>('write', {'key': key, 'value': value});
  @override
  Future<void> delete(String key) =>
      channel.invokeMethod<void>('delete', {'key': key});
}

/// Allowlisted counters only. No receipt data, emails, advertising IDs or images.
class AppServices extends ChangeNotifier {
  AppServices({
    required this.store,
    required this.version,
    http.Client? client,
    PrivateAppStorage? storage,
    this.base = 'https://luckyscan50-api.policlinicosdesantoandre.com',
  }) : client = client ?? http.Client(),
       storage = storage ?? AndroidPrivateAppStorage() {
    ready = _load();
  }
  final WalletStore store;
  final String version, base;
  final http.Client client;
  final PrivateAppStorage storage;
  late final Future<void> ready;
  Future<void> _tail = Future.value();
  bool consent = false, owner = false, deletionPending = false;
  bool _disposed = false;
  DateTime? _ownerExpires;
  static const events = {
    'app_open',
    'scan_camera',
    'scan_import',
    'scan_error',
    'receipt_saved_manual',
    'receipt_saved_import',
  };
  bool get premium =>
      owner && (_ownerExpires?.isAfter(DateTime.now()) ?? false);
  bool get adsAllowed => !premium;
  static String randomId() => List.generate(
    16,
    (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  void _changed() {
    if (!_disposed) notifyListeners();
  }

  Future<void> _load() async {
    try {
      consent = await store.setting('metrics.consent.v1') == 'true';
      deletionPending = await store.setting('metrics.delete.pending') == 'true';
      if (deletionPending) await _deleteMetrics();
      await refreshOwner();
    } catch (_) {
      // Optional services cannot block the local wallet.
    }
    _changed();
  }

  Future<http.Response> _request(
    String method,
    String path, {
    String? token,
    Map<String, dynamic>? body,
  }) async {
    final uri = Uri.parse('$base$path');
    if (uri.scheme != 'https') {
      throw const FormatException('A API exige HTTPS.');
    }
    final headers = {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
    if (method == 'GET') {
      return client
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 8));
    }
    if (method == 'DELETE') {
      return client
          .delete(uri, headers: headers)
          .timeout(const Duration(seconds: 8));
    }
    return client
        .post(uri, headers: headers, body: jsonEncode(body))
        .timeout(const Duration(seconds: 8));
  }

  Future<void> _serial(Future<void> Function() action) {
    final task = _tail.then((_) async {
      await ready;
      await action();
    });
    _tail = task.catchError((Object _) {});
    return task;
  }

  Future<void> setConsent(bool enabled) async {
    // Stop newly queued events immediately; deletion runs after any in-flight event.
    consent = enabled;
    _changed();
    await _serial(() async {
      await store.setSetting('metrics.consent.v1', enabled.toString());
      if (!enabled) {
        deletionPending = true;
        await store.setSetting('metrics.delete.pending', 'true');
        await _deleteMetrics();
      } else if (deletionPending) {
        await _deleteMetrics();
      }
      _changed();
    });
    if (enabled) unawaited(record('app_open'));
  }

  Future<void> _deleteMetrics() async {
    try {
      final token = await storage.read('metricsToken');
      if (token != null) {
        final response = await _request(
          'DELETE',
          '/v1/app/metrics',
          token: token,
        );
        if (response.statusCode != 200 && response.statusCode != 401) return;
        await storage.delete('metricsToken');
      }
      await store.setSetting('metrics.delete.pending', 'false');
      await store.setSetting('metrics.lastOpen', '');
      deletionPending = false;
    } catch (_) {
      // Persist the deletion request and retry at the next opening/event.
    }
  }

  Future<void> record(String event) async {
    if (!events.contains(event)) return;
    try {
      await _serial(() async {
        if (deletionPending) {
          await _deleteMetrics();
          _changed();
        }
        if (!consent || deletionPending || _disposed) return;
        if (event == 'app_open') {
          final last = DateTime.tryParse(
            await store.setting('metrics.lastOpen') ?? '',
          );
          if (last != null &&
              DateTime.now().difference(last) < const Duration(minutes: 30)) {
            return;
          }
        }
        var token = await storage.read('metricsToken');
        if (token == null) {
          final response = await _request(
            'POST',
            '/v1/app/metrics/register',
            body: {'consentVersion': 1},
          );
          if (response.statusCode != 201) return;
          token = (jsonDecode(response.body) as Map)['token'] as String;
          await storage.write('metricsToken', token);
        }
        if (!consent) return;
        final response = await _request(
          'POST',
          '/v1/app/metrics',
          token: token,
          body: {
            'eventId': randomId(),
            'event': event,
            'version': version,
            'platform': Platform.isAndroid
                ? 'android'
                : Platform.isIOS
                ? 'ios'
                : 'other',
          },
        );
        if (response.statusCode == 401) await storage.delete('metricsToken');
        if (event == 'app_open' && response.statusCode == 200) {
          await store.setSetting(
            'metrics.lastOpen',
            DateTime.now().toUtc().toIso8601String(),
          );
        }
      });
    } catch (_) {
      // Fail silently, without retaining payloads or slowing user actions.
    }
  }

  Future<void> activateOwner(String key) async {
    await ready;
    var installation = await storage.read('ownerInstall');
    installation ??= randomId();
    await storage.write('ownerInstall', installation);
    final response = await _request(
      'POST',
      '/v1/app/owner/activate',
      body: {'key': key.trim(), 'installation': installation},
    );
    if (response.statusCode != 200) {
      throw const FormatException(
        'Não foi possível validar a chave de proprietário.',
      );
    }
    final data = jsonDecode(response.body) as Map;
    if (data['tier'] != 'owner' || data['expiresAt'] is! int) {
      throw const FormatException('Resposta de ativação inválida.');
    }
    await storage.write('ownerToken', data['token'] as String);
    _ownerExpires = DateTime.fromMillisecondsSinceEpoch(
      (data['expiresAt'] as int) * 1000,
    );
    owner = true;
    _changed();
  }

  Future<void> refreshOwner() async {
    try {
      final token = await storage.read('ownerToken');
      if (token == null) {
        owner = false;
        _changed();
        return;
      }
      final response = await _request(
        'GET',
        '/v1/app/entitlement',
        token: token,
      );
      if (await storage.read('ownerToken') != token) return;
      if (response.statusCode == 401 || response.statusCode == 403) {
        await storage.delete('ownerToken');
        owner = false;
      } else if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map;
        owner =
            data['tier'] == 'owner' &&
            data['ads'] == false &&
            data['expiresAt'] is int;
        if (owner) {
          _ownerExpires = DateTime.fromMillisecondsSinceEpoch(
            (data['expiresAt'] as int) * 1000,
          );
        }
      }
    } catch (_) {
      // Existing in-memory grant expires; no local flag can create an entitlement.
    }
    _changed();
  }

  Future<void> deactivateOwner() async {
    await storage.delete('ownerToken');
    owner = false;
    _ownerExpires = null;
    _changed();
  }

  @override
  void dispose() {
    _disposed = true;
    client.close();
    super.dispose();
  }
}

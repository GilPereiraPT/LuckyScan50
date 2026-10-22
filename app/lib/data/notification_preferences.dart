import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'wallet_store.dart';
import '../domain/wallet.dart';

const notificationSettingsKey = 'notifications.v1';

class NotificationPreferences {
  const NotificationPreferences({
    this.android = false,
    this.emailConsent = false,
    this.email = '',
    this.results = true,
    this.prizes = true,
    this.expiry = true,
    this.leadDays = 7,
    this.emailConsentAt,
  });

  final bool android, emailConsent, results, prizes, expiry;
  final String email;
  final int leadDays;
  final String? emailConsentAt;

  static bool validEmail(String value) =>
      value.length <= 254 &&
      RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value);

  Map<String, dynamic> toJson() => {
    'android': android,
    'emailConsent': emailConsent,
    'email': email,
    'results': results,
    'prizes': prizes,
    'expiry': expiry,
    'leadDays': leadDays,
    'emailConsentAt': emailConsentAt,
  };

  factory NotificationPreferences.fromJson(Map<String, dynamic> json) =>
      NotificationPreferences(
        android: json['android'] == true,
        emailConsent: json['emailConsent'] == true,
        email: json['email'] as String? ?? '',
        results: json['results'] != false,
        prizes: json['prizes'] != false,
        expiry: json['expiry'] != false,
        leadDays: [1, 3, 7, 14].contains(json['leadDays'])
            ? json['leadDays'] as int
            : 7,
        emailConsentAt: json['emailConsentAt'] as String?,
      );

  static Future<NotificationPreferences> load(WalletStore store) async {
    final raw = await store.setting(notificationSettingsKey);
    if (raw == null) return const NotificationPreferences();
    try {
      return NotificationPreferences.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } on FormatException {
      return const NotificationPreferences();
    }
  }
}

class AndroidNotifications {
  static const channel = MethodChannel('luckyscan50/notifications');
  static Future<bool> enabled() async =>
      Platform.isAndroid &&
      (await channel.invokeMethod<bool>('enabled') ?? false);
  static Future<bool> request() async =>
      Platform.isAndroid &&
      (await channel.invokeMethod<bool>('request') ?? false);
  static Future<void> settings() async {
    if (Platform.isAndroid) await channel.invokeMethod<void>('settings');
  }

  static Future<void> cancelAll() async {
    if (Platform.isAndroid) await channel.invokeMethod<void>('cancelAll');
  }

  static Future<bool> show(String category, String title, String body) async {
    if (!Platform.isAndroid) return false;
    return await channel.invokeMethod<bool>('show', {
          'id': category == 'results'
              ? 1
              : category == 'prizes'
              ? 2
              : 3,
          'category': category,
          'title': title,
          'body': body,
        }) ??
        false;
  }
}

/// Called after synchronization. Never sends email or uploads wallet data.
Future<void> notifyAfterSync(
  WalletStore store,
  List<Map<String, dynamic>> previous,
  List<Map<String, dynamic>> current,
) async {
  final preferences = await NotificationPreferences.load(store);
  if (!preferences.android || !await AndroidNotifications.enabled()) return;
  final known = previous.map((r) => '${r['game']}:${r['drawId']}').toSet();
  final fresh = current
      .where(
        (r) =>
            r['status'] == 'complete' &&
            !known.contains('${r['game']}:${r['drawId']}'),
      )
      .toList();
  if (preferences.results && fresh.isNotEmpty) {
    final key = fresh.map((r) => '${r['game']}:${r['drawId']}').toList()
      ..sort();
    final fingerprint = key.join(',');
    if (await store.setting('notifications.results.last') != fingerprint &&
        await AndroidNotifications.show(
          'results',
          'Resultados disponíveis',
          '${fresh.length} concurso(s) atualizado(s). Consulte os resultados na app.',
        )) {
      await store.setSetting('notifications.results.last', fingerprint);
    }
  }
  if (preferences.prizes) {
    final receipts = await store.receipts();
    final outstanding = receipts.where((r) {
      final result = verify(r, current);
      return result.knownCents > r.receivedCents;
    }).toList();
    final today = DateTime.now().toIso8601String().substring(0, 10);
    if (outstanding.isNotEmpty &&
        await store.setting('notifications.prizes.last') != today &&
        await AndroidNotifications.show(
          'prizes',
          'Prémios por levantar',
          '${outstanding.length} recibo(s) com prémios identificados ainda por registar como recebidos.',
        )) {
      await store.setSetting('notifications.prizes.last', today);
    }
  }
}

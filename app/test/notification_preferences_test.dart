import 'package:flutter_test/flutter_test.dart';
import 'package:luckyscan50/data/notification_preferences.dart';

void main() {
  test('delivery channels require explicit opt-in', () {
    const value = NotificationPreferences();
    expect(value.android, isFalse);
    expect(value.emailConsent, isFalse);
    expect(value.email, isEmpty);
  });

  test('notification preferences survive serialization', () {
    const value = NotificationPreferences(
      android: true,
      emailConsent: true,
      email: 'user@example.pt',
      results: false,
      leadDays: 3,
      emailConsentAt: '2026-10-20T11:00:00Z',
    );
    final restored = NotificationPreferences.fromJson(value.toJson());
    expect(restored.toJson(), value.toJson());
  });

  test('validates email without allowing whitespace or extra at signs', () {
    expect(NotificationPreferences.validEmail('user@example.pt'), isTrue);
    for (final invalid in [
      '',
      'user',
      'user@host',
      'a b@host.pt',
      'a@@host.pt',
    ]) {
      expect(NotificationPreferences.validEmail(invalid), isFalse);
    }
  });

  test('invalid reminder lead time falls back to seven days', () {
    expect(NotificationPreferences.fromJson({'leadDays': -1}).leadDays, 7);
  });
}

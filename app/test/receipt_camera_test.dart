import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luckyscan50/data/receipt_camera.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('luckyscan50/receipt_camera');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));
  test(
    'guided capture returns the native photo without opening image picker',
    () async {
      final calls = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        return '/cache/receipt-camera-test.jpg';
      });
      final result = await captureReceiptPhoto();
      expect(result?.path, '/cache/receipt-camera-test.jpg');
      expect(calls, ['capture']);
    },
  );
  test('cancelling guided camera leaves the import unchanged', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    expect(await captureReceiptPhoto(), isNull);
  });
  test(
    'permission failure is propagated to the existing scan error flow',
    () async {
      messenger.setMockMethodCallHandler(channel, (_) async {
        throw PlatformException(code: 'camera_permission');
      });
      await expectLater(
        captureReceiptPhoto(),
        throwsA(isA<PlatformException>()),
      );
    },
  );
}

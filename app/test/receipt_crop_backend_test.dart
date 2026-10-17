import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luckyscan50/data/receipt_crop_backend.dart';
import 'package:luckyscan50/domain/receipt_geometry.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'cell crop contract forwards original-pixel bounds, deskew and justified contrast',
    () async {
      MethodCall? recorded;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(ReceiptCropBackend.channel, (call) async {
            recorded = call;
            return '/private/cache/cell.png';
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(ReceiptCropBackend.channel, null),
      );
      final path = await const ReceiptCropBackend().crop(
        const PreparedReceiptImage(
          '/private/upright.png',
          2160,
          3840,
          'session',
        ),
        const BetCrop(
          2,
          CropBox(490, 1200, 660, 1300),
          kind: 'N',
          position: 0,
          deskewDegrees: 4,
          contrast: true,
        ),
        2,
      );
      expect(path, '/private/cache/cell.png');
      expect(recorded!.method, 'crop');
      expect(recorded!.arguments, {
        'session': 'session',
        'left': 490.0,
        'top': 1200.0,
        'right': 660.0,
        'bottom': 1300.0,
        'scale': 2.0,
        'deskewDegrees': 4.0,
        'contrast': true,
      });
    },
  );
  test(
    'failed native crops propagate instead of fabricating an OCR observation',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            ReceiptCropBackend.channel,
            (call) async =>
                throw PlatformException(code: 'receipt_crop_memory'),
          );
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(ReceiptCropBackend.channel, null),
      );
      await expectLater(
        const ReceiptCropBackend().crop(
          const PreparedReceiptImage(
            '/private/upright.png',
            2160,
            3840,
            'session',
          ),
          const BetCrop(1, CropBox(0, 0, 40, 40)),
          1,
        ),
        throwsA(isA<PlatformException>()),
      );
    },
  );
}

import 'package:flutter/services.dart';
import '../domain/receipt_multipass.dart';

class PreparedReceiptImage {
  const PreparedReceiptImage(this.path, this.width, this.height, this.session);
  final String path, session;
  final double width, height;
}

class ReceiptCropBackend {
  const ReceiptCropBackend();
  static const channel = MethodChannel('luckyscan50/receipt_crops');
  Future<PreparedReceiptImage> prepare(String path) async {
    final response = await channel.invokeMapMethod<String, dynamic>('prepare', {
      'path': path,
    });
    if (response == null) throw StateError('No prepared image');
    return PreparedReceiptImage(
      response['path'] as String,
      (response['width'] as num).toDouble(),
      (response['height'] as num).toDouble(),
      response['session'] as String,
    );
  }

  Future<PreparedReceiptImage> rotate(
    PreparedReceiptImage image,
    int turns,
  ) async {
    final response = await channel.invokeMapMethod<String, dynamic>('rotate', {
      'session': image.session,
      'turns': turns,
    });
    if (response == null) throw StateError('No oriented image');
    return PreparedReceiptImage(
      response['path'] as String,
      (response['width'] as num).toDouble(),
      (response['height'] as num).toDouble(),
      response['session'] as String,
    );
  }

  Future<String> crop(
    PreparedReceiptImage image,
    BetCrop row,
    double scale,
  ) async {
    final response = await channel.invokeMethod<String>('crop', {
      'session': image.session,
      ...row.box.toJson(),
      'scale': scale,
      'deskewDegrees': row.deskewDegrees,
      'contrast': row.contrast,
    });
    if (response == null) throw StateError('No crop');
    return response;
  }

  Future<void> dispose(PreparedReceiptImage image) =>
      channel.invokeMethod<void>('dispose', {'session': image.session});
}

import 'package:flutter/services.dart';
import '../domain/receipt_rules.dart';
import '../domain/receipt_multipass.dart';

class PreparedReceiptImage {
  const PreparedReceiptImage(this.path, this.width, this.height, this.session);
  final String path, session;
  final double width, height;
}

class ReceiptCropBackend {
  const ReceiptCropBackend();
  static const channel = MethodChannel('luckyscan50/receipt_crops');
  Future<PreparedReceiptImage> prepare(
    String path, {
    bool preview = false,
  }) async {
    final response = await channel.invokeMapMethod<String, dynamic>(
      preview ? 'preparePreview' : 'prepare',
      {'path': path},
    );
    if (response == null) throw StateError('No prepared image');
    return PreparedReceiptImage(
      response['path'] as String,
      (response['width'] as num).toDouble(),
      (response['height'] as num).toDouble(),
      response['session'] as String,
    );
  }

  /// Produces a bounded JPEG from an upright preview using four normalized corners.
  /// Caller owns the temporary returned file; it is not deleted with the session.
  Future<String> rectify(
    PreparedReceiptImage image,
    List<double> corners,
  ) async {
    if (corners.length != 8) throw ArgumentError('Four corners required');
    final path = await channel.invokeMethod<String>('rectify', {
      'session': image.session,
      'corners': corners,
    });
    if (path == null) throw StateError('No rectified image');
    return path;
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

  Future<ReceiptRaster> luminance(PreparedReceiptImage image) async {
    final response = await channel.invokeMapMethod<String, dynamic>(
      'luminance',
      {'session': image.session},
    );
    if (response == null) throw StateError('No receipt luminance');
    return ReceiptRaster(
      response['width'] as int,
      response['height'] as int,
      response['pixels'] as Uint8List,
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

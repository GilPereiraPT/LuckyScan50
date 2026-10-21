import 'dart:io';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

/// Android opens the local, quality-gated camera. Gallery imports are unchanged.
Future<XFile?> pickReceiptImage(ImageSource source) async {
  if (source == ImageSource.camera && Platform.isAndroid) {
    return captureReceiptPhoto();
  }
  return ImagePicker().pickImage(source: source);
}

Future<XFile?> captureReceiptPhoto() async {
  const channel = MethodChannel('luckyscan50/receipt_camera');
  final path = await channel.invokeMethod<String>('capture');
  return path == null ? null : XFile(path);
}

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import '../domain/receipt_ocr.dart';

class ReceiptScan {
  const ReceiptScan(
    this.receipt,
    this.rawText, {
    this.imagePath,
    this.ocrMs = 0,
    this.parseMs = 0,
  });
  final ScannedReceipt receipt;
  final String rawText;
  final String? imagePath;
  final int ocrMs, parseMs;
}

class ReceiptScanFailure implements Exception {
  const ReceiptScanFailure(this.stage, this.errorType);
  final String stage, errorType;
}

typedef ReceiptScanner = Future<ReceiptScan?> Function(ImageSource source);

Future<ReceiptScan?> scanReceiptImage(ImageSource source) async {
  String stage = 'seleção da imagem';
  TextRecognizer? recognizer;
  try {
    final picked = await ImagePicker().pickImage(
      source: source,
      maxWidth: 3000,
    );
    if (picked == null) return null;
    stage = 'reconhecimento ML Kit';
    recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    final clock = Stopwatch()..start();
    final recognized = await recognizer.processImage(
      InputImage.fromFilePath(picked.path),
    );
    final ocrMs = clock.elapsedMilliseconds;
    stage = 'interpretação dos campos';
    clock.reset();
    final receipt = parseScannedReceipt(recognized);
    return ReceiptScan(
      receipt,
      recognized.text,
      imagePath: picked.path,
      ocrMs: ocrMs,
      parseMs: clock.elapsedMilliseconds,
    );
  } catch (error) {
    throw ReceiptScanFailure(stage, error.runtimeType.toString());
  } finally {
    await recognizer?.close();
  }
}

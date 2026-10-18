import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import '../domain/receipt_ocr.dart';
import '../domain/receipt_rules.dart';
import '../domain/receipt_multipass.dart';
import 'receipt_crop_backend.dart';

class OrientationPass {
  const OrientationPass(this.turns, this.frame, this.elapsedMs, this.rows);
  final int turns, elapsedMs, rows;
  final OcrFrame frame;
}

class ReceiptScan {
  const ReceiptScan(
    this.receipt,
    this.rawText, {
    this.imagePath,
    this.ocrMs = 0,
    this.parseMs = 0,
    this.initialParseMs = 0,
    this.totalMs,
    this.phaseTimings = const {},
    this.imageGeometry = const {},
    this.multiPass,
    this.recoveryError,
    this.initialReceipt,
    this.orientationPasses = const [],
  });
  final ScannedReceipt receipt;
  final String rawText;
  final String? imagePath, recoveryError;
  final int ocrMs, parseMs, initialParseMs;
  final int? totalMs;
  final Map<String, int> phaseTimings;
  final Map<String, num> imageGeometry;
  int get totalProcessingMs =>
      phaseTimings['total'] ?? totalMs ?? ocrMs + parseMs;
  final MultiPassResult? multiPass;
  final ScannedReceipt? initialReceipt;
  final List<OrientationPass> orientationPasses;
}

class ReceiptScanFailure implements Exception {
  const ReceiptScanFailure(this.stage, this.errorType);
  final String stage, errorType;
}

typedef ReceiptScanner = Future<ReceiptScan?> Function(ImageSource source);

Future<ReceiptScan?> scanReceiptImage(ImageSource source) async {
  try {
    final picked = await ImagePicker().pickImage(source: source);
    if (picked == null) return null;
    return scanReceiptFile(picked.path);
  } on ReceiptScanFailure {
    rethrow;
  } catch (error) {
    throw ReceiptScanFailure('seleção da imagem', error.runtimeType.toString());
  }
}

Future<ReceiptScan> scanReceiptFile(String path) async {
  final total = Stopwatch()..start();
  final phaseTimings = <String, int>{};
  final imageGeometry = <String, num>{};
  String stage = 'seleção da imagem';
  TextRecognizer? recognizer;
  final preparedImages = <PreparedReceiptImage>[];
  const backend = ReceiptCropBackend();
  try {
    stage = 'reconhecimento ML Kit inicial';
    recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    final engine = recognizer;
    final timer = Stopwatch()..start();
    // Keep the initial full-frame observation, even if native crop prep fails.
    final initial = receiptFrame(
      await engine.processImage(InputImage.fromFilePath(path)),
    );
    final ocrMs = timer.elapsedMilliseconds;
    final first = initial.parse();
    final initialParseMs = timer.elapsedMilliseconds - ocrMs;
    timer.reset();
    final orientationPasses = <OrientationPass>[];
    try {
      stage = 'normalização EXIF e preparação dos recortes';
      final preparationClock = Stopwatch()..start();
      final prepared = await backend.prepare(path);
      imageGeometry.addAll({
        'preparedWidth': prepared.width,
        'preparedHeight': prepared.height,
        'workingQuarterTurns': 0,
      });
      phaseTimings['imagePreparation'] = preparationClock.elapsedMilliseconds;
      preparedImages.add(prepared);
      // ML Kit fromFilePath and the native crop backend both apply EXIF.
      // Native prepare writes lossless upright pixels without changing input.
      var normalized = prepared;
      var workingFrame = initial;
      final orientationClock = Stopwatch()..start();
      if (uprightBetRowCount(
                initial.tokens,
                normalized.width,
                normalized.height,
              ) ==
              0 &&
          initial.tokens.any(verticalReceiptToken)) {
        for (final turns in preferredReceiptTurns(initial.tokens)) {
          final rotated = await backend.rotate(prepared, turns);
          preparedImages.add(rotated);
          final watch = Stopwatch()..start();
          final frame = receiptFrame(
            await engine.processImage(InputImage.fromFilePath(rotated.path)),
          );
          final rowCount = uprightBetRowCount(
            frame.tokens,
            rotated.width,
            rotated.height,
          );
          orientationPasses.add(
            OrientationPass(turns, frame, watch.elapsedMilliseconds, rowCount),
          );
          if (rowCount >= 1) {
            imageGeometry['workingQuarterTurns'] = turns;
            normalized = rotated;
            workingFrame = frame;
            break;
          }
        }
      }
      phaseTimings['orientation'] = orientationClock.elapsedMilliseconds;
      imageGeometry.addAll({
        'workingWidth': normalized.width,
        'workingHeight': normalized.height,
      });
      final ruleClock = Stopwatch()..start();
      var rules = <CropBox>[];
      try {
        final raster = await backend.luminance(normalized);
        rules = detectReceiptRules(
          raster,
          workingFrame.tokens,
          normalized.width,
          normalized.height,
        );
      } catch (_) {
        // Keep the OCR anchors when raster preparation is unavailable.
        phaseTimings['ruleDetectionUnavailable'] = 1;
      }
      phaseTimings['ruleDetection'] = ruleClock.elapsedMilliseconds;
      imageGeometry['horizontalRuleCount'] = rules.length;
      stage = 'reconhecimento das regiões numéricas';
      final recovered = await recoverReceiptRows(
        initial: workingFrame,
        metadata: first,
        rules: rules,
        width: normalized.width,
        height: normalized.height,
        recognizeCrop: (row, scale) async {
          final preparationClock = Stopwatch()..start();
          final croppedPath = await backend.crop(normalized, row, scale);
          phaseTimings['cropPreparation'] =
              (phaseTimings['cropPreparation'] ?? 0) +
              preparationClock.elapsedMilliseconds;
          final clock = Stopwatch()..start();
          try {
            final frame = receiptFrame(
              await engine.processImage(InputImage.fromFilePath(croppedPath)),
            );
            return OcrFrame(
              frame.text,
              frame.tokens,
              rows: frame.rows,
              elapsedMs: clock.elapsedMilliseconds,
            );
          } finally {
            phaseTimings['cropRecognition'] =
                (phaseTimings['cropRecognition'] ?? 0) +
                clock.elapsedMilliseconds;
            try {
              await File(croppedPath).delete();
            } catch (_) {
              debugPrint(
                'Receipt crop file cleanup deferred to session disposal',
              );
            }
          }
        },
      );
      return ReceiptScan(
        recovered.receipt,
        initial.text,
        imagePath: path,
        ocrMs: ocrMs,
        parseMs: timer.elapsedMilliseconds,
        initialParseMs: initialParseMs,
        totalMs: total.elapsedMilliseconds,
        phaseTimings: phaseTimings,
        imageGeometry: imageGeometry,
        multiPass: recovered,
        initialReceipt: first,
        orientationPasses: orientationPasses,
      );
    } catch (error) {
      return ReceiptScan(
        first,
        initial.text,
        imagePath: path,
        ocrMs: ocrMs,
        parseMs: timer.elapsedMilliseconds,
        initialParseMs: initialParseMs,
        totalMs: total.elapsedMilliseconds,
        phaseTimings: phaseTimings,
        imageGeometry: imageGeometry,
        initialReceipt: first,
        orientationPasses: orientationPasses,
        recoveryError: '$stage: ${error.runtimeType}',
      );
    }
  } catch (error) {
    throw ReceiptScanFailure(stage, error.runtimeType.toString());
  } finally {
    final cleanupClock = Stopwatch()..start();
    try {
      await recognizer?.close();
    } catch (_) {
      debugPrint('Receipt recognizer cleanup failed');
    }
    for (final image in preparedImages.reversed) {
      try {
        await backend.dispose(image);
      } catch (_) {
        debugPrint('Receipt crop cleanup failed');
      }
    }
    phaseTimings['cleanup'] = cleanupClock.elapsedMilliseconds;
    phaseTimings['total'] = total.elapsedMilliseconds;
  }
}

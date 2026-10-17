import 'dart:convert';
import 'dart:io';
import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver(
  responseDataCallback: (data) async {
    final file = File('build/receipt-real-evidence.json');
    await file.parent.create(recursive: true);
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(data));
    if (data?['accepted'] != true) {
      throw StateError(
        'Both real image orientations and Android form acceptance must pass.',
      );
    }
  },
);

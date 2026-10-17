import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:cryptography/cryptography.dart';
import 'package:path/path.dart' as p;
import '../domain/wallet.dart';

class WalletBackup {
  static final _cipher = AesGcm.with256bits();
  static Future<SecretKey> _key(String password, List<int> salt) => Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: 210000,
    bits: 256,
  ).deriveKey(secretKey: SecretKey(utf8.encode(password)), nonce: salt);
  static Future<String> encrypt(List<Receipt> receipts, String password) async {
    if (password.length < 12) {
      throw const FormatException('Use pelo menos 12 caracteres');
    }
    final images = <String, String>{};
    for (final r in receipts) {
      if (r.imagePath != null) {
        final file = File(r.imagePath!);
        // A missing attachment must not silently create an incomplete backup.
        images[r.id] = base64Encode(await file.readAsBytes());
      }
    }
    final payload = {
      'receipts': receipts
          .map((r) => {...r.toJson(), 'imagePath': null})
          .toList(),
      'images': images,
    };
    final salt = List.generate(16, (_) => Random.secure().nextInt(256));
    final box = await _cipher.encrypt(
      utf8.encode(jsonEncode(payload)),
      secretKey: await _key(password, salt),
    );
    return jsonEncode({
      'version': 2,
      'salt': base64Encode(salt),
      'nonce': base64Encode(box.nonce),
      'ciphertext': base64Encode(box.cipherText),
      'mac': base64Encode(box.mac.bytes),
    });
  }

  static Future<List<Receipt>> decrypt(
    String text,
    String password, {
    String? imageDirectory,
  }) async {
    try {
      final j = jsonDecode(text) as Map<String, dynamic>;
      if (j['version'] != 1 && j['version'] != 2) {
        throw const FormatException('Versão não suportada');
      }
      final salt = base64Decode(j['salt'] as String),
          nonce = base64Decode(j['nonce'] as String);
      if (salt.length != 16 || nonce.length != 12) {
        throw const FormatException('Formato inválido');
      }
      final box = SecretBox(
        base64Decode(j['ciphertext'] as String),
        nonce: nonce,
        mac: Mac(base64Decode(j['mac'] as String)),
      );
      final bytes = await _cipher.decrypt(
        box,
        secretKey: await _key(password, salt),
      );
      final decoded = jsonDecode(utf8.decode(bytes));
      final List rows = j['version'] == 1
          ? decoded as List
          : (decoded as Map)['receipts'] as List;
      final receipts = rows
          .map(
            (r) => Receipt.fromJson({
              ...Map<String, dynamic>.from(r as Map),
              'imagePath': null,
            }),
          )
          .toList();
      if (receipts.map((r) => r.id).toSet().length != receipts.length) {
        throw const FormatException('Duplicados na cópia');
      }
      final images = j['version'] == 2
          ? Map<String, dynamic>.from((decoded as Map)['images'] as Map)
          : <String, dynamic>{};
      final attachments = <String, List<int>>{};
      for (final r in receipts) {
        if (images.containsKey(r.id)) {
          attachments[r.id] = base64Decode(images[r.id] as String);
        }
      }
      if (attachments.isNotEmpty && imageDirectory == null) {
        throw const FormatException('Diretório de restauro necessário');
      }
      if (imageDirectory == null) {
        return receipts;
      }
      await Directory(imageDirectory).create(recursive: true);
      final restored = <Receipt>[];
      for (final r in receipts) {
        if (!attachments.containsKey(r.id)) {
          restored.add(r);
          continue;
        }
        final path = p.join(
          imageDirectory,
          '${r.id}-restored-${DateTime.now().microsecondsSinceEpoch}.jpg',
        );
        await File(path).writeAsBytes(attachments[r.id]!, flush: true);
        restored.add(Receipt.fromJson({...r.toJson(), 'imagePath': path}));
      }
      return restored;
    } catch (_) {
      throw const FormatException(
        'Palavra-passe incorreta ou cópia corrompida',
      );
    }
  }
}

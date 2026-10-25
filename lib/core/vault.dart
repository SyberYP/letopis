import 'dart:convert';
import 'dart:typed_data';

import 'crypto.dart';

class WrongPasswordException implements Exception {}

/// The key file: Argon2id salt and parameters plus the data key (DEK) wrapped by the
/// password-derived key (KEK). Safe to store next to the data and in git: without the
/// password it reveals nothing.
class VaultFile {
  VaultFile(
      {required this.kdf,
      required this.salt,
      required this.wrappedDek,
      required this.check,
      required this.id});

  static const _context = 'vault/dek';
  static const _checkContext = 'vault/check';
  static const _checkText = 'letopis';

  final KdfParams kdf;
  final Uint8List salt;
  final Uint8List wrappedDek;

  /// A known text encrypted by the DEK, to verify a DEK without the password.
  final Uint8List check;

  /// Random id of this vault; lets a device tell its own repo from someone else's.
  final String id;

  static Future<(VaultFile, CryptoBox)> create(String password,
      {KdfParams kdf = const KdfParams(), List<int>? dek}) async {
    final salt = randomBytes(16);
    final kek = CryptoBox(await deriveKey(password, salt, kdf));
    final dekBytes = dek ?? randomBytes(32);
    final wrapped = await kek.encrypt(dekBytes, context: _context);
    kek.wipe();
    final box = CryptoBox(dekBytes);
    final check = await box.encrypt(utf8.encode(_checkText), context: _checkContext);
    final id = base64Url.encode(randomBytes(12));
    return (
      VaultFile(kdf: kdf, salt: salt, wrappedDek: wrapped, check: check, id: id),
      box,
    );
  }

  Future<CryptoBox> unlock(String password) async {
    final kek = CryptoBox(await deriveKey(password, salt, kdf));
    try {
      return CryptoBox(await kek.decrypt(wrappedDek, context: _context));
    } on DecryptionException {
      throw WrongPasswordException();
    } finally {
      kek.wipe();
    }
  }

  /// Opens with a DEK cached by biometric unlock, after checking it belongs to this vault.
  Future<CryptoBox?> unlockWithKey(List<int> dek) async {
    if (dek.length != 32) return null;
    final box = CryptoBox(dek);
    try {
      final probe = await box.decrypt(check, context: _checkContext);
      if (utf8.decode(probe) == _checkText) return box;
    } on DecryptionException {
      // falls through
    }
    box.wipe();
    return null;
  }

  Future<VaultFile> rewrap(CryptoBox dek, String newPassword) async {
    final (file, box) = await create(newPassword, kdf: kdf, dek: dek.keyBytes);
    box.wipe();
    return VaultFile(
        kdf: file.kdf, salt: file.salt, wrappedDek: file.wrappedDek, check: file.check, id: id);
  }

  Map<String, dynamic> toJson() => {
        'format': 'letopis-vault',
        'v': 1,
        'id': id,
        'kdf': {...kdf.toJson(), 'salt': base64.encode(salt)},
        'dek': base64.encode(wrappedDek),
        'check': base64.encode(check),
      };

  factory VaultFile.fromJson(Map<String, dynamic> j) {
    if (j['format'] != 'letopis-vault') throw const FormatException('not a Letopis vault');
    final kdf = j['kdf'] as Map<String, dynamic>;
    return VaultFile(
      kdf: KdfParams.fromJson(kdf),
      salt: base64.decode(kdf['salt'] as String),
      wrappedDek: base64.decode(j['dek'] as String),
      check: base64.decode(j['check'] as String),
      id: j['id'] as String,
    );
  }

  String encode() => const JsonEncoder.withIndent('  ').convert(toJson());
  static VaultFile decode(String s) => VaultFile.fromJson(jsonDecode(s) as Map<String, dynamic>);
}

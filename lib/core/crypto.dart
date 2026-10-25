import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Encrypted blob format "LTP1", chunked so large videos never sit in memory whole:
///
///   magic "LTP1" (4) | chunk size u32 BE (4) | nonce prefix (8) | chunks...
///   chunk i = AES-256-GCM(cleartext[i]) (n bytes) + tag (16)
///   nonce(i) = prefix || u32 BE(i); aad(i) = context || final-flag byte (1 = last chunk)
///
/// The final flag stops truncation; the context (a logical path like "entries/<id>") stops a
/// valid ciphertext being swapped into another file.
class Ltp1 {
  static const magic = [0x4C, 0x54, 0x50, 0x31]; // LTP1
  static const headerLength = 16;
  static const tagLength = 16;
  static const defaultChunk = 1 << 20; // 1 MiB
}

class DecryptionException implements Exception {
  final String message;
  DecryptionException(this.message);
  @override
  String toString() => 'DecryptionException: $message';
}

final _rng = Random.secure();

Uint8List randomBytes(int n) {
  final out = Uint8List(n);
  for (var i = 0; i < n; i++) {
    out[i] = _rng.nextInt(256);
  }
  return out;
}

/// AES-256-GCM over a data key (DEK). Holds the key bytes so it can be wiped on lock.
class CryptoBox {
  CryptoBox(List<int> keyBytes, {this.chunkSize = Ltp1.defaultChunk})
      : _keyBytes = Uint8List.fromList(keyBytes) {
    if (keyBytes.length != 32) throw ArgumentError('key must be 32 bytes');
  }

  static final AesGcm _aes = AesGcm.with256bits();
  final Uint8List _keyBytes;
  final int chunkSize;
  bool _wiped = false;

  SecretKey get _key {
    if (_wiped) throw StateError('vault is locked');
    return SecretKey(_keyBytes);
  }

  Uint8List get keyBytes {
    if (_wiped) throw StateError('vault is locked');
    return Uint8List.fromList(_keyBytes);
  }

  void wipe() {
    _keyBytes.fillRange(0, _keyBytes.length, 0);
    _wiped = true;
  }

  static List<int> _nonce(List<int> prefix, int index) {
    final n = Uint8List(12)..setRange(0, 8, prefix);
    ByteData.sublistView(n).setUint32(8, index);
    return n;
  }

  static List<int> _aad(List<int> context, bool last) => [...context, last ? 1 : 0];

  Uint8List _header(List<int> prefix) {
    final h = Uint8List(Ltp1.headerLength)..setRange(0, 4, Ltp1.magic);
    ByteData.sublistView(h).setUint32(4, chunkSize);
    h.setRange(8, 16, prefix);
    return h;
  }

  Future<Uint8List> encrypt(List<int> clear, {required String context}) async {
    final ctx = utf8.encode(context);
    final prefix = randomBytes(8);
    final out = BytesBuilder(copy: false)..add(_header(prefix));
    final key = _key;
    var index = 0;
    var offset = 0;
    do {
      final end = min(offset + chunkSize, clear.length);
      final last = end == clear.length;
      final box = await _aes.encrypt(clear.sublist(offset, end),
          secretKey: key, nonce: _nonce(prefix, index), aad: _aad(ctx, last));
      out
        ..add(box.cipherText)
        ..add(box.mac.bytes);
      offset = end;
      index++;
    } while (offset < clear.length);
    return out.takeBytes();
  }

  Future<Uint8List> decrypt(List<int> blob, {required String context}) async {
    final ctx = utf8.encode(context);
    final (chunk, prefix) = _readHeader(blob);
    final out = BytesBuilder(copy: false);
    final key = _key;
    final step = chunk + Ltp1.tagLength;
    var offset = Ltp1.headerLength;
    var index = 0;
    if (blob.length - offset < Ltp1.tagLength) throw DecryptionException('truncated');
    while (offset < blob.length) {
      final end = min(offset + step, blob.length);
      final last = end == blob.length;
      if (end - offset < Ltp1.tagLength) throw DecryptionException('truncated');
      out.add(await _open(blob.sublist(offset, end), key, prefix, index, ctx, last));
      offset = end;
      index++;
    }
    return out.takeBytes();
  }

  Future<List<int>> _open(
      List<int> part, SecretKey key, List<int> prefix, int index, List<int> ctx, bool last) async {
    final split = part.length - Ltp1.tagLength;
    try {
      return await _aes.decrypt(
        SecretBox(part.sublist(0, split),
            nonce: _nonce(prefix, index), mac: Mac(part.sublist(split))),
        secretKey: key,
        aad: _aad(ctx, last),
      );
    } on SecretBoxAuthenticationError {
      throw DecryptionException('wrong key or damaged data');
    }
  }

  (int, List<int>) _readHeader(List<int> blob) {
    if (blob.length < Ltp1.headerLength) throw DecryptionException('too short');
    for (var i = 0; i < 4; i++) {
      if (blob[i] != Ltp1.magic[i]) throw DecryptionException('not an LTP1 blob');
    }
    final chunk = ByteData.sublistView(Uint8List.fromList(blob.sublist(4, 8))).getUint32(0);
    if (chunk == 0 || chunk > 64 << 20) throw DecryptionException('bad chunk size');
    return (chunk, blob.sublist(8, 16));
  }

  /// Streams [source] into an encrypted [target] chunk by chunk.
  Future<void> encryptFile(File source, File target, {required String context}) async {
    final ctx = utf8.encode(context);
    final prefix = randomBytes(8);
    final key = _key;
    final total = await source.length();
    final input = await source.open();
    final tmp = File('${target.path}.part');
    final output = await tmp.open(mode: FileMode.write);
    try {
      await output.writeFrom(_header(prefix));
      var done = 0;
      var index = 0;
      do {
        final clear = await input.read(min(chunkSize, total - done));
        done += clear.length;
        final last = done >= total;
        final box = await _aes.encrypt(clear,
            secretKey: key, nonce: _nonce(prefix, index), aad: _aad(ctx, last));
        await output.writeFrom(box.cipherText);
        await output.writeFrom(box.mac.bytes);
        index++;
      } while (done < total);
    } finally {
      await input.close();
      await output.close();
    }
    await tmp.rename(target.path);
  }

  /// Streams an encrypted [source] into a plain [target].
  Future<void> decryptFile(File source, File target, {required String context}) async {
    final ctx = utf8.encode(context);
    final total = await source.length();
    final input = await source.open();
    final tmp = File('${target.path}.part');
    final output = await tmp.open(mode: FileMode.write);
    try {
      final (chunk, prefix) = _readHeader(await input.read(Ltp1.headerLength));
      final key = _key;
      var done = Ltp1.headerLength;
      var index = 0;
      if (total - done < Ltp1.tagLength) throw DecryptionException('truncated');
      while (done < total) {
        final part = await input.read(min(chunk + Ltp1.tagLength, total - done));
        done += part.length;
        if (part.length < Ltp1.tagLength) throw DecryptionException('truncated');
        await output.writeFrom(await _open(part, key, prefix, index, ctx, done >= total));
        index++;
      }
    } catch (_) {
      await output.close();
      if (await tmp.exists()) await tmp.delete();
      await input.close();
      rethrow;
    }
    await input.close();
    await output.close();
    await tmp.rename(target.path);
  }
}

/// Argon2id parameters. Defaults follow the OWASP recommendation (19 MiB, 2 passes, 1 lane).
class KdfParams {
  const KdfParams({this.memoryKiB = 19456, this.iterations = 2, this.parallelism = 1});
  final int memoryKiB;
  final int iterations;
  final int parallelism;

  Map<String, dynamic> toJson() =>
      {'alg': 'argon2id', 'm': memoryKiB, 't': iterations, 'p': parallelism};

  factory KdfParams.fromJson(Map<String, dynamic> j) {
    if (j['alg'] != 'argon2id') throw FormatException('unknown kdf ${j['alg']}');
    return KdfParams(
        memoryKiB: j['m'] as int, iterations: j['t'] as int, parallelism: j['p'] as int);
  }
}

/// Derives a 32-byte key from [password]. Runs in a background isolate: it takes a second or two.
Future<Uint8List> deriveKey(String password, List<int> salt, KdfParams p) {
  final pw = utf8.encode(password);
  final s = List<int>.from(salt);
  final m = p.memoryKiB, t = p.iterations, par = p.parallelism;
  return Isolate.run(() async {
    final algo = Argon2id(parallelism: par, memory: m, iterations: t, hashLength: 32);
    final key = await algo.deriveKey(secretKey: SecretKey(pw), nonce: s);
    return Uint8List.fromList(await key.extractBytes());
  });
}

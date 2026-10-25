import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:letopis/core/crypto.dart';
import 'package:letopis/core/vault.dart';

const fastKdf = KdfParams(memoryKiB: 256, iterations: 1, parallelism: 1);

void main() {
  group('CryptoBox', () {
    final box = CryptoBox(randomBytes(32), chunkSize: 64);

    test('round trip across chunk sizes', () async {
      for (final n in [0, 1, 63, 64, 65, 128, 1000]) {
        final clear = List<int>.generate(n, (i) => i % 251);
        final blob = await box.encrypt(clear, context: 'entries/a');
        expect(blob.length, Ltp1.headerLength + n + ((n == 0 ? 1 : (n + 63) ~/ 64) * 16));
        expect(await box.decrypt(blob, context: 'entries/a'), clear);
      }
    });

    test('wrong context, key, tampering and truncation fail', () async {
      final blob = await box.encrypt(utf8.encode('x' * 200), context: 'entries/a');
      expect(() => box.decrypt(blob, context: 'entries/b'), throwsA(isA<DecryptionException>()));
      final other = CryptoBox(randomBytes(32), chunkSize: 64);
      expect(() => other.decrypt(blob, context: 'entries/a'), throwsA(isA<DecryptionException>()));
      final flipped = List<int>.from(blob)..[30] ^= 1;
      expect(() => box.decrypt(flipped, context: 'entries/a'), throwsA(isA<DecryptionException>()));
      // Dropping the final chunk must not decrypt as a shorter valid text.
      final cut = blob.sublist(0, Ltp1.headerLength + 2 * (64 + 16));
      expect(() => box.decrypt(cut, context: 'entries/a'), throwsA(isA<DecryptionException>()));
    });

    test('two encryptions of one text differ', () async {
      final a = await box.encrypt([1, 2, 3], context: 'c');
      final b = await box.encrypt([1, 2, 3], context: 'c');
      expect(a, isNot(b));
    });

    test('file streaming matches in-memory format', () async {
      final dir = await Directory.systemTemp.createTemp('ltp');
      final src = File('${dir.path}/src')..writeAsBytesSync(List.generate(1000, (i) => i % 7));
      final enc = File('${dir.path}/enc');
      final out = File('${dir.path}/out');
      await box.encryptFile(src, enc, context: 'media/x');
      expect(await box.decrypt(enc.readAsBytesSync(), context: 'media/x'), src.readAsBytesSync());
      await box.decryptFile(enc, out, context: 'media/x');
      expect(out.readAsBytesSync(), src.readAsBytesSync());
      await expectLater(box.decryptFile(enc, out, context: 'media/y'), throwsA(isA<DecryptionException>()));
      await dir.delete(recursive: true);
    });

    test('wiped box refuses to work', () async {
      final b = CryptoBox(randomBytes(32));
      b.wipe();
      expect(() => b.encrypt([1], context: 'c'), throwsStateError);
    });
  });

  group('VaultFile', () {
    test('create, serialize, unlock, wrong password, rewrap', () async {
      final (vault, box) = await VaultFile.create('correct horse', kdf: fastKdf);
      final secret = await box.encrypt(utf8.encode('дневник'), context: 'entries/1');
      final restored = VaultFile.decode(vault.encode());
      final again = await restored.unlock('correct horse');
      expect(utf8.decode(await again.decrypt(secret, context: 'entries/1')), 'дневник');
      expect(() => restored.unlock('wrong'), throwsA(isA<WrongPasswordException>()));

      final changed = await restored.rewrap(again, 'new pass');
      expect(changed.id, vault.id);
      final third = await changed.unlock('new pass');
      expect(utf8.decode(await third.decrypt(secret, context: 'entries/1')), 'дневник');
      expect(() => changed.unlock('correct horse'), throwsA(isA<WrongPasswordException>()));
    });

    test('unlockWithKey checks the key', () async {
      final (vault, box) = await VaultFile.create('pw', kdf: fastKdf);
      expect(await vault.unlockWithKey(box.keyBytes), isNotNull);
      expect(await vault.unlockWithKey(randomBytes(32)), isNull);
    });

    test('default Argon2id cost', () async {
      final sw = Stopwatch()..start();
      await deriveKey('password', randomBytes(16), const KdfParams());
      // ignore: avoid_print
      print('argon2id default params: ${sw.elapsedMilliseconds} ms');
    });
  });
}

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:letopis/core/crypto.dart';
import 'package:letopis/core/entry.dart';
import 'package:letopis/core/store.dart';
import 'package:letopis/core/vault.dart';
import 'package:letopis/services/git_remote.dart';
import 'package:letopis/services/sync.dart';

const fastKdf = KdfParams(memoryKiB: 256, iterations: 1, parallelism: 1);
const cfg = GitHubConfig(owner: 'o', repo: 'r', token: 't', dir: 'diary');

Future<(Directory, EntryStore, VaultFile)> device() async {
  final (vault, box) = await VaultFile.create('pw', kdf: fastKdf);
  final dir = await Directory.systemTemp.createTemp('dev');
  await EntryStore.writeVault(dir, vault);
  final s = EntryStore(dir, box);
  await s.load();
  return (dir, s, vault);
}

SyncEngine engine(EntryStore s, RemoteRepo r, {GitHubConfig config = cfg}) =>
    SyncEngine(store: s, remote: r, config: config, device: 'test');

void main() {
  test('only diary files are taken from the repository', () async {
    final (dir, s, _) = await device();
    addTearDown(() => dir.delete(recursive: true));
    final remote = MemoryRemote();
    await s.save(Entry.create()..body = 'a');
    await engine(s, remote).run();

    // Someone with write access adds files the app would never write.
    remote.pushExternal('diary/settings.enc', [1, 2, 3]);
    remote.pushExternal('diary/index.enc', [1, 2, 3]);
    remote.pushExternal('diary/entries/sub/x.md.enc', [1, 2, 3]);
    remote.pushExternal('diary/media/../../escape.enc', [1, 2, 3]);
    final r = await engine(s, remote).run();
    expect(r.downloaded, 0);
    expect(File('${dir.path}/settings.enc').existsSync(), isFalse);
    final index = File('${dir.path}/index.enc');
    if (index.existsSync()) expect(index.readAsBytesSync(), isNot([1, 2, 3]));
    expect(Directory('${dir.path}/entries/sub').existsSync(), isFalse);
    expect(File('${dir.parent.path}/escape.enc').existsSync(), isFalse);
    expect(SyncEngine.isSyncPath('entries/6f1c-aa.md.enc'), isTrue);
    expect(SyncEngine.isSyncPath('../vault.json'), isFalse);
  });

  test('a key file that does not open this diary is refused, not taken', () async {
    final (dir, s, vault) = await device();
    addTearDown(() => dir.delete(recursive: true));
    final remote = MemoryRemote();
    await s.save(Entry.create()..body = 'мои записи');
    await engine(s, remote).run();

    // Same vault id, but a different data key (e.g. a hostile or broken vault.json).
    final (rogue, rogueBox) = await VaultFile.create('other', kdf: fastKdf);
    rogueBox.wipe();
    final forged = VaultFile(kdf: rogue.kdf, salt: rogue.salt, wrappedDek: rogue.wrappedDek, check: rogue.check, id: vault.id);
    remote.pushExternal('diary/vault.json', utf8.encode(forged.encode()));
    await expectLater(
      engine(s, remote).run(),
      throwsA(isA<SyncException>().having((e) => e.code, 'code', 'other_vault')),
    );
    // The local key file is untouched: the diary still opens with its password.
    final local = (await EntryStore.readVault(dir))!;
    final box = await local.unlock('pw');
    box.wipe();
  });

  test('a new password from another device is accepted', () async {
    final (dir, s, vault) = await device();
    addTearDown(() => dir.delete(recursive: true));
    final remote = MemoryRemote();
    await engine(s, remote).run();
    final changed = await vault.rewrap(s.box, 'новый пароль');
    remote.pushExternal('diary/vault.json', utf8.encode(changed.encode()));
    final r = await engine(s, remote).run();
    expect(r.vaultChanged, isTrue);
    final box = await (await EntryStore.readVault(dir))!.unlock('новый пароль');
    box.wipe();
  });

  test('plain mirror never pushes to a public repository', () async {
    final (dir, s, _) = await device();
    addTearDown(() => dir.delete(recursive: true));
    final remote = MemoryRemote()..private = false;
    await s.save(Entry.create()..body = 'личное');
    await expectLater(
      engine(s, remote, config: cfg.copyWith(plain: true)).run(),
      throwsA(isA<SyncException>().having((e) => e.code, 'code', 'public_repo')),
    );
    expect(remote.files, isEmpty);
    remote.private = true;
    await engine(s, remote, config: cfg.copyWith(plain: true)).run();
    expect(remote.files.keys.any((k) => k.endsWith('.md')), isTrue);
  });

  test('an entry restored from the trash is uploaded again', () async {
    final (dir, s, _) = await device();
    addTearDown(() => dir.delete(recursive: true));
    final remote = MemoryRemote();
    final e = Entry.create()..body = 'вернусь';
    await s.save(e);
    await engine(s, remote).run();
    await s.delete(e.id);
    await engine(s, remote).run();
    expect(remote.files.keys.any((k) => k.contains(e.id)), isFalse);
    await s.restore(e.id);
    final r = await engine(s, remote).run();
    expect(r.uploaded, 1);
    expect(remote.files.keys.any((k) => k.contains(e.id)), isTrue);
  });
}

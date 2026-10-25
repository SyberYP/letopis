// ignore_for_file: curly_braces_in_flow_control_structures
import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:letopis/core/crypto.dart';
import 'package:letopis/core/entry.dart';
import 'package:letopis/core/store.dart';
import 'package:letopis/core/vault.dart';
import 'package:letopis/services/ai_tagger.dart';
import 'package:letopis/services/git_remote.dart';
import 'package:letopis/services/sync.dart';

const fastKdf = KdfParams(memoryKiB: 256, iterations: 1, parallelism: 1);
const cfg = GitHubConfig(owner: 'o', repo: 'r', token: 't', dir: 'diary');

class Device {
  Device(this.dir, this.store, this.name);
  final Directory dir;
  EntryStore store;
  final String name;

  SyncEngine engine(RemoteRepo r, {GitHubConfig config = cfg}) =>
      SyncEngine(store: store, remote: r, config: config, device: name);

  Future<SyncReport> sync(RemoteRepo r) => engine(r).run();

  /// Reopens the store from disk (like an app restart).
  Future<void> reopen() async {
    store = EntryStore(dir, store.box);
    await store.load();
  }
}

Future<(Device, Device)> twoDevices() async {
  final (vault, box) = await VaultFile.create('pw', kdf: fastKdf);
  final a = await Directory.systemTemp.createTemp('devA');
  final b = await Directory.systemTemp.createTemp('devB');
  await EntryStore.writeVault(a, vault);
  await EntryStore.writeVault(b, vault);
  final sa = EntryStore(a, CryptoBox(box.keyBytes));
  final sb = EntryStore(b, CryptoBox(box.keyBytes));
  return (Device(a, sa, 'A'), Device(b, sb, 'B'));
}

void main() {
  test('gitBlobSha matches git', () {
    // `printf 'hello\n' | git hash-object --stdin`
    expect(gitBlobSha(utf8.encode('hello\n')), 'ce013625030ba8dba906f756967f9e9ca394464a');
  });

  test('parseRepo', () {
    expect(GitHubConfig.parseRepo('SyberYP/life'), ('SyberYP', 'life'));
    expect(GitHubConfig.parseRepo('https://github.com/SyberYP/life.git'), ('SyberYP', 'life'));
    expect(GitHubConfig.parseRepo('git@github.com:SyberYP/my.diary'), ('SyberYP', 'my.diary'));
    expect(GitHubConfig.parseRepo('nonsense'), isNull);
  });

  group('encrypted sync', () {
    test('entries and media travel both ways, deletes propagate', () async {
      final (a, b) = await twoDevices();
      final remote = MemoryRemote();

      final e1 = Entry.create()..body = 'с устройства A';
      final src = File('${a.dir.path}/note.txt')..writeAsStringSync('файл');
      final att = await a.store.importMedia(src);
      e1.attachments.add(att);
      await a.store.save(e1);
      final r1 = await a.sync(remote);
      expect(r1.uploaded, 3); // vault + entry + media
      expect(remote.files.keys, containsAll(['diary/README.md', 'diary/vault.json']));
      expect(remote.files.keys.every((k) => k.startsWith('diary/')), isTrue);

      final r2 = await b.sync(remote);
      expect(r2.downloaded, 2); // vault is identical already
      await b.reopen();
      expect(b.store.entries.single.body, 'с устройства A');
      expect(await b.store.mediaBytes(att.id), utf8.encode('файл'));

      // Nothing to do on a second run.
      expect((await a.sync(remote)).nothing, isTrue);
      expect((await b.sync(remote)).nothing, isTrue);

      // B edits, A receives.
      final eb = b.store.byId(e1.id)!..body = 'исправлено на B';
      await b.store.save(eb);
      await b.sync(remote);
      final r3 = await a.sync(remote);
      expect(r3.changedEntries, {e1.id});
      expect(a.store.byId(e1.id)!.body, 'исправлено на B');

      // A deletes, B loses it too.
      await a.store.delete(e1.id);
      final r4 = await a.sync(remote);
      expect(r4.deletedRemote, 2);
      await b.sync(remote);
      await b.reopen();
      expect(b.store.entries, isEmpty);
    });

    test('concurrent edits keep both versions', () async {
      final (a, b) = await twoDevices();
      final remote = MemoryRemote();
      final e = Entry.create()..body = 'исходный';
      await a.store.save(e);
      await a.sync(remote);
      await b.sync(remote);
      await b.reopen();

      final ea = a.store.byId(e.id)!..body = 'версия A';
      await a.store.save(ea);
      await Future.delayed(const Duration(milliseconds: 5));
      final eb = b.store.byId(e.id)!..body = 'версия B (позже)';
      await b.store.save(eb);

      await a.sync(remote);
      final rb = await b.sync(remote);
      expect(rb.conflicts, 1);
      expect(b.store.byId(e.id)!.body, 'версия B (позже)');
      final copy = b.store.entries.firstWhere((x) => x.id != e.id);
      expect(copy.body, 'версия A');
      expect(copy.tags, contains('конфликт'));

      await a.sync(remote);
      await a.reopen();
      expect(a.store.entries.map((x) => x.body).toSet(), {'версия A', 'версия B (позже)'});
    });

    test('edit wins over a delete on the other device', () async {
      final (a, b) = await twoDevices();
      final remote = MemoryRemote();
      final e = Entry.create()..body = 'x';
      await a.store.save(e);
      await a.sync(remote);
      await b.sync(remote);
      await b.reopen();
      await a.store.delete(e.id);
      await a.sync(remote);
      final eb = b.store.byId(e.id)!..body = 'оставить';
      await b.store.save(eb);
      await b.sync(remote);
      await a.sync(remote);
      expect(a.store.byId(e.id)?.body, 'оставить');
    });

    test('refuses a repository with another diary', () async {
      final (a, _) = await twoDevices();
      final (c, _) = await twoDevices();
      final remote = MemoryRemote();
      await a.store.save(Entry.create()..body = 'a');
      await a.sync(remote);
      await expectLater(c.sync(remote), throwsA(isA<SyncException>().having((e) => e.code, 'code', 'other_vault')));
    });

    test('retries when the branch moves during sync', () async {
      final (a, b) = await twoDevices();
      final remote = MemoryRemote();
      await a.store.save(Entry.create()..body = 'a');
      await a.sync(remote);
      await b.store.save(Entry.create()..body = 'b');
      remote.beforeCommit = () => remote.pushExternal('other/file.txt', [1]);
      await b.sync(remote);
      expect(remote.files.keys, contains('other/file.txt'));
      expect(remote.files.keys.where((k) => k.startsWith('diary/entries/')).length, 2);
    });
  });

  test('plain mirror writes readable Markdown and media, removes stale files', () async {
    final (a, _) = await twoDevices();
    final remote = MemoryRemote()..pushExternal('keep/me.txt', [1]);
    final src = File('${a.dir.path}/p.txt')..writeAsStringSync('медиа');
    final att = await a.store.importMedia(src, name: 'p.txt');
    final e = Entry.create(at: DateTime(2026, 10, 25, 9, 41))
      ..title = 'Утро'
      ..body = 'см. [📎 p.txt](att:${att.id})'
      ..attachments.add(att);
    await a.store.save(e);
    final config = cfg.copyWith(plain: true);
    await a.engine(remote, config: config).run();
    final mdPath = 'diary/entries/2026/10/2026-10-25-0941-утро.md';
    final md = utf8.decode(remote.blobs[remote.files[mdPath]]!);
    expect(md, contains('(../../../media/${att.id}.txt)'));
    expect(utf8.decode(remote.blobs[remote.files['diary/media/${att.id}.txt']]!), 'медиа');

    // Title change moves the file; nothing outside the folder is touched.
    a.store.byId(e.id)!;
    final renamed = a.store.byId(e.id)!..title = 'Вечер';
    await a.store.save(renamed);
    await a.engine(remote, config: config).run();
    expect(remote.files.containsKey(mdPath), isFalse);
    expect(remote.files.keys, contains('diary/entries/2026/10/2026-10-25-0941-вечер.md'));
    expect(remote.files.keys, contains('keep/me.txt'));
    expect(remote.files.keys, contains('diary/media/${att.id}.txt'));
  });

  group('GitHubRepo over HTTP', () {
    test('snapshot and commit call the Git Data API in order', () async {
      final calls = <String>[];
      final client = MockClient((req) async {
        calls.add('${req.method} ${req.url.path}');
        expect(req.headers['Authorization'], 'Bearer tok');
        final p = req.url.path;
        if (p.endsWith('/git/ref/heads/main'))
          return http.Response(
            jsonEncode({
              'object': {'sha': 'h1'},
            }),
            200,
          );
        if (p.endsWith('/git/commits/h1'))
          return http.Response(
            jsonEncode({
              'tree': {'sha': 't1'},
            }),
            200,
          );
        if (p.endsWith('/git/trees/t1')) {
          return http.Response(
            jsonEncode({
              'truncated': false,
              'tree': [
                {'path': 'd/a.enc', 'type': 'blob', 'sha': 's1'},
              ],
            }),
            200,
          );
        }
        if (p.endsWith('/git/blobs')) return http.Response(jsonEncode({'sha': 'b2'}), 201);
        if (p.endsWith('/git/trees')) {
          final body = jsonDecode(req.body);
          expect(body['base_tree'], 't1');
          expect((body['tree'] as List).length, 2);
          return http.Response(jsonEncode({'sha': 't2'}), 201);
        }
        if (p.endsWith('/git/commits')) return http.Response(jsonEncode({'sha': 'h2'}), 201);
        if (p.endsWith('/git/refs/heads/main')) return http.Response('{}', 200);
        return http.Response('not found', 404);
      });
      final repo = GitHubRepo(
        const GitHubConfig(owner: 'o', repo: 'r', token: 'tok'),
        client: client,
      );
      final snap = await repo.snapshot();
      expect(snap.files, {'d/a.enc': 's1'});
      final head = await repo.commit(
        snap,
        put: {
          'd/b.enc': Uint8List.fromList([1]),
        },
        remove: {'d/a.enc'},
        message: 'm',
      );
      expect(head, 'h2');
      expect(calls.last, 'PATCH /repos/o/r/git/refs/heads/main');
    });

    test('missing branch is an empty snapshot', () async {
      final client = MockClient((req) async => http.Response('{"message":"Git Repository is empty."}', 409));
      final repo = GitHubRepo(
        const GitHubConfig(owner: 'o', repo: 'r', token: 'tok'),
        client: client,
      );
      expect((await repo.snapshot()).isEmpty, isTrue);
    });
  });

  group('AI tagger', () {
    test('parses the different answer shapes', () {
      expect(AiTagger.parseTags('{"tags": ["Семья", "#дочь", "работа и дом"]}'), ['семья', 'дочь', 'работа_и_дом']);
      expect(AiTagger.parseTags('```json\n["a","b"]\n```'), ['a', 'b']);
      expect(AiTagger.parseTags('Here you go: {"tags":["x"]} hope it helps'), ['x']);
      expect(AiTagger.parseTags('Теги: семья, роды'), ['теги_семья', 'роды']);
    });

    test('sends the entry and known tags, filters tags already present', () async {
      late Map body;
      final client = MockClient((req) async {
        expect(req.url.toString(), 'https://openrouter.ai/api/v1/chat/completions');
        expect(req.headers['Authorization'], 'Bearer key');
        body = jsonDecode(req.body) as Map;
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'choices': [
                {
                  'message': {'content': '{"tags":["семья","роды","радость"]}'},
                },
              ],
            }),
          ),
          200,
        );
      });
      final tagger = AiTagger(const AiConfig(apiKey: 'key'), client: client);
      final e = Entry.create()..body = 'Сегодня #семья';
      final tags = await tagger.suggest(e, ['семья', 'работа']);
      expect(tags, ['роды', 'радость']);
      expect(body['model'], AiConfig.defaultModel);
      expect((body['messages'] as List).last['content'], contains('семья, работа'));
    });

    test('reports HTTP errors with the provider message', () async {
      final client = MockClient((_) async => http.Response('{"error":{"message":"No credits"}}', 402));
      final tagger = AiTagger(const AiConfig(apiKey: 'key'), client: client);
      await expectLater(
        tagger.suggest(Entry.create()..body = 'x', []),
        throwsA(isA<AiException>().having((e) => e.message, 'message', contains('No credits'))),
      );
    });
  });
}

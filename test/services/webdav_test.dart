import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:letopis/core/entry.dart';
import 'package:letopis/services/git_remote.dart';
import 'package:letopis/services/sync.dart';
import 'package:letopis/services/webdav_remote.dart';

import 'sync_test.dart' show twoDevices;

/// A WebDAV server in memory: just enough of RFC 4918 for the app.
class FakeDav {
  final files = <String, List<int>>{};
  final dirs = <String>{''};
  final log = <String>[];
  String password = 'app-pass';

  late final client = MockClient((req) async {
    final auth = req.headers['authorization'];
    if (auth != 'Basic ${base64.encode(utf8.encode('me@example.com:$password'))}') {
      return http.Response('', 401);
    }
    var path = Uri.decodeFull(req.url.path);
    if (!path.startsWith('/dav')) return http.Response('', 404);
    path = path.substring(4).replaceAll(RegExp(r'^/+|/+$'), '');
    final parent = path.contains('/') ? path.substring(0, path.lastIndexOf('/')) : '';
    log.add('${req.method} $path');
    switch (req.method) {
      case 'PROPFIND':
        return http.Response('<multistatus/>', dirs.contains(path) || files.containsKey(path) ? 207 : 404);
      case 'MKCOL':
        if (dirs.contains(path)) return http.Response('', 405);
        if (!dirs.contains(parent)) return http.Response('', 409);
        dirs.add(path);
        return http.Response('', 201);
      case 'PUT':
        if (!dirs.contains(parent)) return http.Response('', 409);
        final existed = files.containsKey(path);
        files[path] = req.bodyBytes;
        return http.Response('', existed ? 204 : 201);
      case 'GET':
        final f = files[path];
        return f == null ? http.Response('', 404) : http.Response.bytes(f, 200);
      case 'DELETE':
        return http.Response('', files.remove(path) == null ? 404 : 204);
    }
    return http.Response('', 405);
  });

  WebDavRepo repo({String dir = 'Letopis/diary'}) => WebDavRepo(
    WebDavConfig(url: 'https://cloud.example.com/dav/', user: 'me@example.com', password: password, dir: dir),
    client: client,
  );

  Map<String, dynamic> get index => jsonDecode(utf8.decode(files['Letopis/diary/${WebDavRepo.indexName}']!));
  Iterable<String> get objects => files.keys.where((k) => k.startsWith('Letopis/diary/objects/'));
}

const davCfg = WebDavConfig(url: 'https://cloud.example.com/dav', user: 'me@example.com', password: 'p', dir: 'Letopis/diary');

void main() {
  group('cloud (WebDAV) sync', () {
    test('entries and media travel both ways, deletes clean the folder up', () async {
      final dav = FakeDav();
      final (a, b) = await twoDevices();
      SyncEngine engine(d) => SyncEngine(store: d.store, remote: dav.repo(), config: davCfg, device: d.name);

      final e1 = Entry.create()..body = 'с телефона A #облако';
      final src = File('${a.dir.path}/photo.jpg')..writeAsBytesSync(List.generate(5000, (i) => i % 251));
      e1.attachments.add(await a.store.importMedia(src));
      await a.store.save(e1);
      final r1 = await engine(a).run();
      expect(r1.uploaded, 3); // vault + entry + media
      expect(dav.dirs, containsAll(['Letopis', 'Letopis/diary', 'Letopis/diary/objects']));
      expect(dav.files.keys, contains('Letopis/diary/README.md'));
      expect((dav.index['files'] as Map).keys, containsAll(['vault.json', 'entries/${e1.id}.md.enc']));
      // Only encrypted bytes reach the cloud.
      for (final o in dav.objects) {
        expect(utf8.decode(dav.files[o]!, allowMalformed: true), isNot(contains('телефона')));
      }

      final r2 = await engine(b).run();
      expect(r2.downloaded, 2);
      await b.reopen();
      expect(b.store.byId(e1.id)!.body, 'с телефона A #облако');
      expect(await b.store.mediaBytes(e1.attachments.first.id), hasLength(5000));

      // Edit on B, delete the media-less copy on A later: old blobs are removed.
      final objectsBefore = dav.objects.length;
      final eb = b.store.byId(e1.id)!..body = 'исправлено на B';
      await b.store.save(eb);
      await engine(b).run();
      expect(dav.objects.length, objectsBefore, reason: 'the replaced entry blob is deleted');

      await engine(a).run();
      await a.reopen();
      expect(a.store.byId(e1.id)!.body, 'исправлено на B');

      await a.store.delete(e1.id);
      final r3 = await engine(a).run();
      expect(r3.deletedRemote, greaterThan(0));
      await engine(b).run();
      await b.reopen();
      expect(b.store.byId(e1.id), isNull);
    });

    test('concurrent edits keep both versions', () async {
      final dav = FakeDav();
      final (a, b) = await twoDevices();
      SyncEngine engine(d) => SyncEngine(store: d.store, remote: dav.repo(), config: davCfg, device: d.name);
      final e = Entry.create()..body = 'исходный';
      await a.store.save(e);
      await engine(a).run();
      await engine(b).run();
      await b.reopen();

      await a.store.save(a.store.byId(e.id)!..body = 'версия A');
      await Future.delayed(const Duration(milliseconds: 5));
      await b.store.save(b.store.byId(e.id)!..body = 'версия B');
      await engine(a).run();
      final r = await engine(b).run();
      expect(r.conflicts, 1);
      await b.reopen();
      final bodies = b.store.entries.map((x) => x.body).toSet();
      expect(bodies, containsAll(['версия A', 'версия B']));
    });

    test('a commit from an outdated snapshot is refused, then sync starts over', () async {
      final dav = FakeDav();
      final repo = dav.repo();
      final base = await repo.snapshot();
      expect(base.isEmpty, isTrue);
      await repo.commit(base, put: {'Letopis/diary/x': bytesSource([1])}, remove: {}, message: 'one');
      await expectLater(
        repo.commit(base, put: {'Letopis/diary/y': bytesSource([2])}, remove: {}, message: 'two'),
        throwsA(isA<RemoteException>().having((e) => e.isConflict, 'conflict', isTrue)),
      );
      // The second upload never became visible.
      expect((dav.index['files'] as Map).keys, ['x']);
    });

    test('a blob that changed under the index is treated as a conflict', () async {
      final dav = FakeDav();
      final repo = dav.repo();
      await repo.commit(await repo.snapshot(), put: {'Letopis/diary/x': bytesSource([1, 2, 3])}, remove: {}, message: '');
      final snap = await repo.snapshot();
      final sha = snap.files['Letopis/diary/x']!;
      expect(await repo.readBlob(sha), [1, 2, 3]);
      dav.files['Letopis/diary/objects/$sha'] = [9];
      await expectLater(repo.readBlob(sha), throwsA(isA<RemoteException>().having((e) => e.isConflict, 'c', isTrue)));
      await expectLater(repo.readBlob('../etc'), throwsA(isA<RemoteException>()));
    });

    test('check reports a wrong app password', () async {
      final dav = FakeDav();
      await dav.repo().check();
      final wrong = WebDavRepo(
        const WebDavConfig(url: 'https://cloud.example.com/dav', user: 'me@example.com', password: 'nope'),
        client: dav.client,
      );
      await expectLater(wrong.check(), throwsA(isA<RemoteException>().having((e) => e.statusCode, 'status', 401)));
    });

    test('the password never goes over plain HTTP to the internet', () async {
      expect(WebDavConfig.urlProblem('https://webdav.yandex.ru'), isNull);
      expect(WebDavConfig.urlProblem('http://webdav.yandex.ru'), 'https_only');
      expect(WebDavConfig.urlProblem('http://192.168.1.20:8080/dav'), isNull);
      expect(WebDavConfig.urlProblem('http://nas.local/dav'), isNull);
      expect(WebDavConfig.urlProblem('ftp://x'), 'bad_url');
      expect(WebDavConfig.urlProblem('webdav.yandex.ru'), 'bad_url');
      const cfg = WebDavConfig(url: 'http://example.com', user: 'u', password: 'p');
      expect(cfg.isConfigured, isFalse);
      await expectLater(WebDavRepo(cfg).check(), throwsA(isA<RemoteException>()));
    });

    test('settings round-trip and presets', () {
      const c = WebDavConfig(url: 'https://webdav.yandex.ru/', user: 'u', password: 'p', dir: 'd', autoSync: true);
      final back = WebDavConfig.fromJson(c.toJson());
      expect(back.key, c.key);
      expect(back.autoSync, isTrue);
      expect(WebDavPreset.forUrl('https://webdav.yandex.ru/').id, 'yandex');
      expect(WebDavPreset.forUrl('https://cloud.me/remote.php/dav/files/me').id, 'nextcloud');
    });
  });
}

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:letopis/core/crypto.dart';
import 'package:letopis/core/entry.dart';
import 'package:letopis/core/markdown_io.dart';
import 'package:letopis/core/store.dart';
import 'package:letopis/services/ai_tagger.dart';
import 'package:letopis/services/importer.dart';

/// Input that comes from outside the app (imported files, shared repositories, settings typed
/// by the user) must not be able to reach paths outside the diary or leak data.
void main() {
  test('ids with path tricks are replaced', () {
    expect(isSafeId('6f1c2d3e-aaaa-4bbb-8ccc-123456789abc'), isTrue);
    for (final bad in ['../vault', 'a/b', '..', '', 'x.md', 'a\\b', 'a' * 65]) {
      expect(isSafeId(bad), isFalse, reason: bad);
    }
    final e = entryFromMarkdown('---\nid: ../../vault\ncreated: 2026-10-25T09:41:00+03:00\n---\ntext');
    expect(isSafeId(e.id), isTrue);
    expect(e.id.contains('/'), isFalse);
  });

  test('attachments with unsafe ids are dropped, extensions are sanitized', () {
    final e = entryFromMarkdown(
      '---\nid: x1\nattachments:\n'
      '  - {"id": "../../settings", "type": "photo", "name": "a.jpg", "mime": "image/jpeg"}\n'
      '  - {"id": "ok-1", "type": "file", "name": "evil.b/../../x", "mime": "application/pdf"}\n'
      '---\nbody',
    );
    expect(e.attachments.map((a) => a.id), ['ok-1']);
    expect(e.attachments.single.extension, 'bin');
    const good = Attachment(id: 'a', type: AttachmentType.photo, name: 'IMG.JPG', mime: 'image/jpeg');
    expect(good.extension, 'jpg');
  });

  test('stored entries keep the id of their file', () async {
    final dir = await Directory.systemTemp.createTemp('ids');
    addTearDown(() => dir.delete(recursive: true));
    final box = CryptoBox(randomBytes(32));
    final s = EntryStore(dir, box);
    final e = Entry.create()..body = 'x';
    await s.save(e);
    // A file whose front matter claims another id is still loaded under its file name.
    final other = utf8.encode('---\nid: someone-else\ncreated: 2026-10-25T09:41:00+03:00\n---\nx');
    await File('${dir.path}/${EntryStore.entryPath(e.id)}')
        .writeAsBytes(await box.encrypt(other, context: 'entries/${e.id}'));
    final s2 = EntryStore(dir, box);
    await s2.load();
    expect(s2.entries.single.id, e.id);
  });

  test('an imported Markdown file gets a new id and no foreign attachments', () {
    const id = '6f1c2d3e-aaaa-4bbb-8ccc-123456789abc';
    final p = parseImport(
      '---\nid: $id\ncreated: 2026-10-25T09:41:00+03:00\ntitle: "T"\n'
      'attachments:\n  - {"id": "a1", "type": "photo", "name": "p.jpg", "mime": "image/jpeg"}\n---\nbody',
    );
    final e = p.entries.single;
    expect(e.id, isNot(id));
    expect(e.attachments, isEmpty);
    expect(e.title, 'T');
    expect(e.body, 'body');
  });

  test('KDF parameters from a file are bounded', () {
    Map<String, dynamic> j(int m, int t, int p) => {'alg': 'argon2id', 'm': m, 't': t, 'p': p};
    expect(KdfParams.fromJson(j(19456, 2, 1)).memoryKiB, 19456);
    expect(() => KdfParams.fromJson(j(1 << 30, 2, 1)), throwsFormatException); // 1 TiB
    expect(() => KdfParams.fromJson(j(19456, 100000, 1)), throwsFormatException);
    expect(() => KdfParams.fromJson(j(19456, 2, 0)), throwsFormatException);
    expect(() => KdfParams.fromJson({'alg': 'argon2id', 'm': '1', 't': 2, 'p': 1}), throwsFormatException);
  });

  test('AI requests go over HTTPS only', () async {
    var called = false;
    final client = MockClient((_) async {
      called = true;
      return http.Response('{}', 200);
    });
    final ai = AiTagger(
      const AiConfig(baseUrl: 'http://example.com/v1', apiKey: 'k', model: 'm'),
      client: client,
    );
    await expectLater(
      ai.suggest(Entry.create()..body = 'text', const []),
      throwsA(isA<AiException>().having((e) => e.message, 'message', 'https_only')),
    );
    expect(called, isFalse);
    expect(const AiConfig(baseUrl: 'https://openrouter.ai/api/v1').host, 'openrouter.ai');
  });
}

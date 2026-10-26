import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as hash;
import 'package:http/http.dart' as http;

/// Git blob id of [bytes]: `sha1("blob <len>\0" + bytes)`. Lets sync compare files without
/// downloading them.
String gitBlobSha(List<int> bytes) {
  final header = utf8.encode('blob ${bytes.length}\u0000');
  return hash.sha1.convert([...header, ...bytes]).toString();
}

/// [gitBlobSha] of a file, streamed: big videos are never read into memory whole.
Future<String> gitBlobShaFile(File f) async {
  final out = _DigestSink();
  final sink = hash.sha1.startChunkedConversion(out);
  sink.add(utf8.encode('blob ${await f.length()}\u0000'));
  await for (final chunk in f.openRead()) {
    sink.add(chunk);
  }
  sink.close();
  return out.value.toString();
}

class _DigestSink implements Sink<hash.Digest> {
  late hash.Digest value;
  @override
  void add(hash.Digest data) => value = data;
  @override
  void close() {}
}

/// File contents read only when the upload needs them, one file at a time.
typedef BlobSource = Future<Uint8List> Function();

BlobSource bytesSource(List<int> bytes) =>
    () async => Uint8List.fromList(bytes);

class RemoteException implements Exception {
  RemoteException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
  bool get isConflict => statusCode == 409 || statusCode == 422;
  @override
  String toString() => statusCode == null ? message : 'HTTP $statusCode: $message';
}

/// State of the branch: head commit and blob ids of every file (full repo paths).
class RemoteSnapshot {
  RemoteSnapshot({this.headSha, this.treeSha, Map<String, String>? files}) : files = files ?? {};
  final String? headSha;
  final String? treeSha;
  final Map<String, String> files;
  bool get isEmpty => headSha == null;
}

/// What sync needs from a git host. GitHub is the first implementation; Gitea and GitLab
/// expose the same primitives.
abstract class RemoteRepo {
  String get label;

  /// Whether only invited people can read the repository.
  Future<bool> isPrivate();
  Future<RemoteSnapshot> snapshot();
  Future<Uint8List> readBlob(String sha);

  /// One commit on top of [base]: [put] adds or replaces files, [remove] deletes them.
  /// Returns the new head. Throws [RemoteException] with isConflict when the branch moved.
  Future<String> commit(
    RemoteSnapshot base, {
    required Map<String, BlobSource> put,
    required Set<String> remove,
    required String message,
  });
}

class GitHubConfig {
  const GitHubConfig({
    this.owner = '',
    this.repo = '',
    this.branch = 'main',
    this.dir = 'letopis',
    this.token = '',
    this.plain = false,
    this.autoSync = false,
    this.apiBase = 'https://api.github.com',
  });

  final String owner;
  final String repo;
  final String branch;

  /// Folder inside the repo; empty for the root.
  final String dir;
  final String token;

  /// Plain Markdown mirror (push only) instead of the encrypted two-way sync.
  final bool plain;
  final bool autoSync;
  final String apiBase;

  bool get isConfigured => owner.isNotEmpty && repo.isNotEmpty && token.isNotEmpty;
  String get key => '$owner/$repo@$branch/$dir/${plain ? 'plain' : 'enc'}';

  GitHubConfig copyWith({
    String? owner,
    String? repo,
    String? branch,
    String? dir,
    String? token,
    bool? plain,
    bool? autoSync,
  }) => GitHubConfig(
    owner: owner ?? this.owner,
    repo: repo ?? this.repo,
    branch: branch ?? this.branch,
    dir: dir ?? this.dir,
    token: token ?? this.token,
    plain: plain ?? this.plain,
    autoSync: autoSync ?? this.autoSync,
    apiBase: apiBase,
  );

  Map<String, dynamic> toJson() => {
    'owner': owner,
    'repo': repo,
    'branch': branch,
    'dir': dir,
    'token': token,
    'plain': plain,
    'auto': autoSync,
  };

  factory GitHubConfig.fromJson(Map<String, dynamic>? j) => j == null
      ? const GitHubConfig()
      : GitHubConfig(
          owner: (j['owner'] as String?) ?? '',
          repo: (j['repo'] as String?) ?? '',
          branch: (j['branch'] as String?) ?? 'main',
          dir: (j['dir'] as String?) ?? 'letopis',
          token: (j['token'] as String?) ?? '',
          plain: (j['plain'] as bool?) ?? false,
          autoSync: (j['auto'] as bool?) ?? false,
        );

  /// Accepts `owner/repo`, `https://github.com/owner/repo(.git)` or `git@github.com:owner/repo`.
  static (String, String)? parseRepo(String input) {
    final m = RegExp(r'(?:github\.com[/:])?([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+?)(?:\.git)?/?$').firstMatch(input.trim());
    if (m == null) return null;
    return (m.group(1)!, m.group(2)!);
  }
}

/// GitHub through the REST Git Data API (blobs → tree → commit → ref): no native git needed.
class GitHubRepo implements RemoteRepo {
  GitHubRepo(this.config, {http.Client? client}) : _client = client ?? http.Client();

  final GitHubConfig config;
  final http.Client _client;

  /// GitHub refuses blobs over 100 MB.
  static const maxBlobBytes = 95 * 1024 * 1024;

  @override
  String get label => '${config.owner}/${config.repo}';

  String get _repoUrl => '${config.apiBase}/repos/${config.owner}/${config.repo}';

  Map<String, String> get _headers => {
    'Authorization': 'Bearer ${config.token.trim()}',
    'Accept': 'application/vnd.github+json',
    'X-GitHub-Api-Version': '2022-11-28',
    'Content-Type': 'application/json',
  };

  Future<dynamic> _send(String method, String path, {Object? body, Set<int> allow = const {}}) async {
    final uri = Uri.parse(path.startsWith('http') ? path : '$_repoUrl$path');
    final req = http.Request(method, uri)..headers.addAll(_headers);
    if (body != null) req.body = jsonEncode(body);
    final http.Response res;
    try {
      res = await http.Response.fromStream(await _client.send(req).timeout(const Duration(seconds: 60)));
    } catch (e) {
      throw RemoteException('network: $e');
    }
    if (allow.contains(res.statusCode)) return null;
    if (res.statusCode < 200 || res.statusCode >= 300) {
      String msg = res.body;
      try {
        msg = '${jsonDecode(res.body)['message']}';
      } catch (_) {}
      throw RemoteException(msg, statusCode: res.statusCode);
    }
    return res.body.isEmpty ? null : jsonDecode(utf8.decode(res.bodyBytes));
  }

  /// Checks the token and repository; returns whether the repo is private.
  Future<bool> check() async {
    final j = await _send('GET', '');
    return j['private'] == true;
  }

  @override
  Future<bool> isPrivate() => check();

  @override
  Future<RemoteSnapshot> snapshot() async {
    final ref = await _send('GET', '/git/ref/heads/${config.branch}', allow: {404, 409});
    if (ref == null) return RemoteSnapshot();
    final head = ref['object']['sha'] as String;
    final commit = await _send('GET', '/git/commits/$head');
    final treeSha = commit['tree']['sha'] as String;
    final tree = await _send('GET', '/git/trees/$treeSha?recursive=1');
    if (tree['truncated'] == true) {
      throw RemoteException('repository tree is too large for the API');
    }
    final files = <String, String>{
      for (final t in tree['tree'] as List)
        if (t['type'] == 'blob') t['path'] as String: t['sha'] as String,
    };
    return RemoteSnapshot(headSha: head, treeSha: treeSha, files: files);
  }

  @override
  Future<Uint8List> readBlob(String sha) async {
    final j = await _send('GET', '/git/blobs/$sha');
    return base64.decode((j['content'] as String).replaceAll('\n', ''));
  }

  @override
  Future<String> commit(
    RemoteSnapshot base, {
    required Map<String, BlobSource> put,
    required Set<String> remove,
    required String message,
  }) async {
    var current = base;
    if (current.isEmpty) {
      // The Git Data API refuses an empty repository; the Contents API can create the first file.
      final readme = put.keys.firstWhere((p) => p.endsWith('README.md'), orElse: () => put.keys.first);
      final first = await put[readme]!();
      await _send(
        'PUT',
        '/contents/${Uri.encodeComponent(readme).replaceAll('%2F', '/')}',
        body: {'message': message, 'content': base64.encode(first), 'branch': config.branch},
      );
      current = await snapshot();
      if (current.files[readme] == gitBlobSha(first)) {
        put = Map.of(put)..remove(readme);
      }
      if (put.isEmpty && remove.isEmpty) return current.headSha!;
    }
    final items = <Map<String, dynamic>>[];
    for (final e in put.entries) {
      final bytes = await e.value();
      final sha = gitBlobSha(bytes);
      if (current.files[e.key] == sha) continue;
      if (bytes.length > maxBlobBytes) {
        throw RemoteException('${e.key}: file is larger than 95 MB');
      }
      final blob = await _send('POST', '/git/blobs', body: {'content': base64.encode(bytes), 'encoding': 'base64'});
      items.add({'path': e.key, 'mode': '100644', 'type': 'blob', 'sha': blob['sha']});
    }
    for (final p in remove) {
      if (current.files.containsKey(p)) {
        items.add({'path': p, 'mode': '100644', 'type': 'blob', 'sha': null});
      }
    }
    if (items.isEmpty) return current.headSha!;
    final tree = await _send('POST', '/git/trees', body: {'base_tree': current.treeSha, 'tree': items});
    final commit = await _send(
      'POST',
      '/git/commits',
      body: {
        'message': message,
        'tree': tree['sha'],
        'parents': [current.headSha],
      },
    );
    await _send('PATCH', '/git/refs/heads/${config.branch}', body: {'sha': commit['sha'], 'force': false});
    return commit['sha'] as String;
  }
}

/// In-memory remote for tests and the offline demo.
class MemoryRemote implements RemoteRepo {
  final Map<String, Uint8List> blobs = {};
  Map<String, String> files = {};
  int commits = 0;
  String? head;
  bool private = true;

  @override
  Future<bool> isPrivate() async => private;

  /// Simulates another device pushing between snapshot and commit.
  void Function()? beforeCommit;

  @override
  String get label => 'memory';

  @override
  Future<RemoteSnapshot> snapshot() async => RemoteSnapshot(headSha: head, treeSha: head, files: Map.of(files));

  @override
  Future<Uint8List> readBlob(String sha) async => blobs[sha]!;

  @override
  Future<String> commit(
    RemoteSnapshot base, {
    required Map<String, BlobSource> put,
    required Set<String> remove,
    required String message,
  }) async {
    beforeCommit?.call();
    beforeCommit = null;
    if (base.headSha != head) throw RemoteException('moved', statusCode: 422);
    for (final e in put.entries) {
      final bytes = await e.value();
      final sha = gitBlobSha(bytes);
      blobs[sha] = bytes;
      files[e.key] = sha;
    }
    remove.forEach(files.remove);
    commits++;
    head = 'c$commits';
    return head!;
  }

  /// Writes a file as if another device pushed it.
  void pushExternal(String path, List<int> bytes) {
    final b = Uint8List.fromList(bytes);
    final sha = gitBlobSha(b);
    blobs[sha] = b;
    files[path] = sha;
    commits++;
    head = 'c$commits';
  }
}

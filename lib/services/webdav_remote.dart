import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../core/entry.dart' show newId;
import 'git_remote.dart';

/// A cloud folder over WebDAV: Yandex Disk, Mail.ru Cloud, Nextcloud, ownCloud, a home NAS…
class WebDavConfig implements SyncConfig {
  const WebDavConfig({
    this.url = '',
    this.user = '',
    this.password = '',
    this.dir = 'letopis',
    this.autoSync = false,
  });

  /// Server root, e.g. `https://webdav.yandex.ru` or `https://cloud.example.com/remote.php/dav/files/me`.
  final String url;
  final String user;

  /// An app password where the service has them (Yandex, Mail.ru, Nextcloud).
  final String password;

  /// Folder inside the cloud; empty for the root.
  @override
  final String dir;
  @override
  final bool autoSync;

  @override
  bool get plain => false;

  @override
  bool get isConfigured => url.isNotEmpty && user.isNotEmpty && password.isNotEmpty && urlProblem(url) == null;

  @override
  String get key => 'dav:${normalizeUrl(url)}|$user|$dir';

  @override
  String get label => Uri.tryParse(url)?.host ?? url;

  WebDavConfig copyWith({String? url, String? user, String? password, String? dir, bool? autoSync}) => WebDavConfig(
    url: url ?? this.url,
    user: user ?? this.user,
    password: password ?? this.password,
    dir: dir ?? this.dir,
    autoSync: autoSync ?? this.autoSync,
  );

  Map<String, dynamic> toJson() => {'url': url, 'user': user, 'password': password, 'dir': dir, 'auto': autoSync};

  factory WebDavConfig.fromJson(Map<String, dynamic>? j) => j == null
      ? const WebDavConfig()
      : WebDavConfig(
          url: (j['url'] as String?) ?? '',
          user: (j['user'] as String?) ?? '',
          password: (j['password'] as String?) ?? '',
          dir: (j['dir'] as String?) ?? 'letopis',
          autoSync: (j['auto'] as bool?) ?? false,
        );

  static String normalizeUrl(String url) => url.trim().replaceAll(RegExp(r'/+$'), '');

  /// Null when the address is usable. The password travels with every request, so plain HTTP is
  /// allowed only inside a home network (a NAS), never over the internet.
  static String? urlProblem(String url) {
    final u = Uri.tryParse(url.trim());
    if (u == null || u.host.isEmpty || !(u.scheme == 'https' || u.scheme == 'http')) return 'bad_url';
    if (u.scheme == 'http' && !isLocalHost(u.host)) return 'https_only';
    return null;
  }

  static bool isLocalHost(String host) {
    final h = host.toLowerCase();
    if (h == 'localhost' || h.endsWith('.local') || h.endsWith('.lan') || h.endsWith('.home.arpa')) return true;
    final p = h.split('.').map(int.tryParse).toList();
    if (p.length != 4 || p.any((v) => v == null || v < 0 || v > 255)) return false;
    final a = p[0]!, b = p[1]!;
    return a == 10 || a == 127 || (a == 192 && b == 168) || (a == 172 && b >= 16 && b <= 31);
  }
}

/// Ready-made addresses. The user still types the login and an app password.
class WebDavPreset {
  const WebDavPreset(this.id, this.url, this.helpKey);
  final String id;
  final String url;
  final String helpKey;

  static const all = [
    WebDavPreset('yandex', 'https://webdav.yandex.ru', 'dav_help_yandex'),
    WebDavPreset('mailru', 'https://webdav.cloud.mail.ru', 'dav_help_mailru'),
    WebDavPreset('nextcloud', 'https://', 'dav_help_nextcloud'),
    WebDavPreset('other', 'https://', 'dav_help_other'),
  ];

  static WebDavPreset forUrl(String url) {
    final n = WebDavConfig.normalizeUrl(url);
    for (final p in all.take(2)) {
      if (n == p.url) return p;
    }
    return n.contains('/remote.php/') ? all[2] : all[3];
  }
}

/// The diary in a cloud folder.
///
/// WebDAV has no commits, so the folder holds an index (`letopis-sync.json`: revision and
/// path → blob id) plus the files themselves under `objects/<blob id>`. A file is never
/// overwritten with other content — two phones syncing at once can't destroy each other's
/// upload; the index is written last and checked against the revision the sync started from.
class WebDavRepo implements RemoteRepo {
  WebDavRepo(this.config, {http.Client? client}) : _client = client ?? http.Client();

  final WebDavConfig config;
  final http.Client _client;

  static const indexName = 'letopis-sync.json';

  @override
  String get label => config.label;

  String get _dir => config.dir.replaceAll(RegExp(r'^/+|/+$'), '');
  String get _prefix => _dir.isEmpty ? '' : '$_dir/';
  String get _index => '$_prefix$indexName';
  String _object(String sha) => '${_prefix}objects/$sha';

  Uri _uri(String path) {
    final base = Uri.parse(WebDavConfig.normalizeUrl(config.url));
    final segs = [...base.pathSegments.where((s) => s.isNotEmpty), ...path.split('/').where((s) => s.isNotEmpty)];
    return base.replace(pathSegments: segs);
  }

  Uri _collection(String path) {
    final u = _uri(path);
    return u.replace(path: '${u.path}/');
  }

  Map<String, String> get _auth => {
    'Authorization': 'Basic ${base64.encode(utf8.encode('${config.user.trim()}:${config.password}'))}',
  };

  Future<http.Response> _send(
    String method,
    Uri uri, {
    List<int>? body,
    Map<String, String> headers = const {},
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final problem = WebDavConfig.urlProblem(config.url);
    if (problem != null) throw RemoteException(problem);
    final req = http.Request(method, uri)
      ..headers.addAll(_auth)
      ..headers.addAll(headers)
      ..followRedirects = false;
    if (body != null) req.bodyBytes = body;
    try {
      return await http.Response.fromStream(await _client.send(req).timeout(timeout));
    } catch (e) {
      throw RemoteException('network: $e');
    }
  }

  Never _fail(http.Response r) {
    final hint = switch (r.statusCode) {
      401 => 'login or app password rejected',
      403 => 'access denied',
      404 => 'not found',
      507 => 'cloud is full',
      _ => r.reasonPhrase ?? '',
    };
    throw RemoteException(hint, statusCode: r.statusCode == 409 ? 400 : r.statusCode);
  }

  /// Checks the address, login and password.
  Future<void> check() async {
    final r = await _send('PROPFIND', _collection(''), headers: {'Depth': '0'});
    if (r.statusCode != 207 && r.statusCode != 200) _fail(r);
  }

  /// A private place: WebDAV has no public flag (only the plain mirror asks, and the cloud
  /// target never uses it).
  @override
  Future<bool> isPrivate() async => true;

  ({String rev, Map<String, String> files})? _parseIndex(List<int> bytes) {
    try {
      final j = jsonDecode(utf8.decode(bytes));
      if (j is! Map || j['format'] != 1 || j['rev'] is! String || j['files'] is! Map) return null;
      return (rev: j['rev'] as String, files: {for (final e in (j['files'] as Map).entries) '${e.key}': '${e.value}'});
    } catch (_) {
      return null;
    }
  }

  Future<({String rev, Map<String, String> files})?> _readIndex() async {
    final r = await _send('GET', _uri(_index));
    if (r.statusCode == 404) return null;
    if (r.statusCode != 200) _fail(r);
    final idx = _parseIndex(r.bodyBytes);
    if (idx == null) throw RemoteException('$indexName is damaged');
    return idx;
  }

  @override
  Future<RemoteSnapshot> snapshot() async {
    final idx = await _readIndex();
    if (idx == null) return RemoteSnapshot();
    return RemoteSnapshot(headSha: idx.rev, files: {for (final e in idx.files.entries) '$_prefix${e.key}': e.value});
  }

  @override
  Future<Uint8List> readBlob(String sha) async {
    if (!RegExp(r'^[0-9a-f]{40}$').hasMatch(sha)) throw RemoteException('bad blob id');
    final r = await _send('GET', _uri(_object(sha)), timeout: const Duration(minutes: 10));
    // Gone or different: another phone changed the folder meanwhile; sync starts over.
    if (r.statusCode == 404) throw RemoteException('file changed during sync', statusCode: 409);
    if (r.statusCode != 200) _fail(r);
    if (gitBlobSha(r.bodyBytes) != sha) throw RemoteException('file changed during sync', statusCode: 409);
    return r.bodyBytes;
  }

  final Set<String> _made = {};

  Future<void> _mkcol(String path) async {
    if (path.isEmpty || _made.contains(path)) return;
    final parent = path.contains('/') ? path.substring(0, path.lastIndexOf('/')) : '';
    final r = await _send('MKCOL', _collection(path));
    // 405: already there. 409: the parent is missing — make it, then try again.
    if (r.statusCode == 409 && parent.isNotEmpty && !_made.contains(parent)) {
      await _mkcol(parent);
      final again = await _send('MKCOL', _collection(path));
      if (again.statusCode != 201 && again.statusCode != 405) _fail(again);
    } else if (r.statusCode != 201 && r.statusCode != 405 && r.statusCode != 200) {
      _fail(r);
    }
    _made.add(path);
  }

  Future<void> _put(String path, List<int> bytes) async {
    // Slow clouds (Yandex WebDAV) need time for big videos: a minute plus ~32 KB/s.
    final timeout = Duration(seconds: 60 + bytes.length ~/ (32 * 1024));
    final r = await _send('PUT', _uri(path), body: bytes, timeout: timeout);
    if (r.statusCode != 200 && r.statusCode != 201 && r.statusCode != 204) _fail(r);
  }

  @override
  Future<String> commit(
    RemoteSnapshot base, {
    required Map<String, BlobSource> put,
    required Set<String> remove,
    required String message,
  }) async {
    final current = await _readIndex();
    if (current?.rev != base.headSha) throw RemoteException('the folder changed', statusCode: 409);

    await _mkcol(_dir);
    await _mkcol('${_prefix}objects');
    final files = {
      for (final e in base.files.entries)
        if (e.key.startsWith(_prefix)) e.key.substring(_prefix.length): e.value,
    };
    for (final e in put.entries) {
      final rel = e.key.substring(_prefix.length);
      final bytes = await e.value();
      final sha = gitBlobSha(bytes);
      if (rel == 'README.md') {
        await _put(e.key, bytes); // for people opening the folder
      } else if (!files.containsValue(sha)) {
        await _put(_object(sha), bytes);
      }
      files[rel] = sha;
    }
    for (final p in remove) {
      files.remove(p.substring(_prefix.length));
    }

    // Last check, then the index: until it is written, nothing this sync did is visible.
    final again = await _readIndex();
    if (again?.rev != base.headSha) throw RemoteException('the folder changed', statusCode: 409);
    final rev = newId();
    await _put(_index, utf8.encode(jsonEncode({'format': 1, 'rev': rev, 'files': files})));

    // Files no path points to any more (deleted or replaced entries).
    final live = files.values.toSet();
    final old = {...?current?.files.values}..removeAll(live);
    for (final sha in old) {
      final r = await _send('DELETE', _uri(_object(sha)));
      if (r.statusCode >= 300 && r.statusCode != 404) break; // garbage only; try next time
    }
    return rev;
  }
}

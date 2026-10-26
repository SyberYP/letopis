import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Only the download-site build (`siteBuild`, see channel.dart) checks for updates; store builds
/// are updated by the store, and store rules forbid updating around it.

const siteUrl = 'https://letopis.recalltwin.com/';
const versionUrl = '${siteUrl}version.json';

/// A newer build published on the download site.
class UpdateInfo {
  const UpdateInfo({required this.version, required this.build});
  final String version;
  final int build;
}

class UpdateCheckException implements Exception {
  const UpdateCheckException(this.message);
  final String message;
  @override
  String toString() => 'UpdateCheckException: $message';
}

/// Asks the download site for the latest version. Runs only when the user taps the button;
/// the request carries nothing from the diary. Returns null when [currentBuild] is up to date.
Future<UpdateInfo?> checkForUpdate({required int currentBuild, http.Client? client}) async {
  final c = client ?? http.Client();
  try {
    final r = await c.get(Uri.parse(versionUrl)).timeout(const Duration(seconds: 15));
    if (r.statusCode != 200) throw UpdateCheckException('http ${r.statusCode}');
    final Object? j;
    try {
      j = jsonDecode(utf8.decode(r.bodyBytes));
    } on FormatException {
      throw const UpdateCheckException('bad response');
    }
    if (j is! Map) throw const UpdateCheckException('bad response');
    final version = j['version'], build = j['build'];
    if (version is! String || build is! int || !RegExp(r'^\d+\.\d+\.\d+$').hasMatch(version)) {
      throw const UpdateCheckException('bad response');
    }
    return build > currentBuild ? UpdateInfo(version: version, build: build) : null;
  } on TimeoutException {
    throw const UpdateCheckException('timeout');
  } finally {
    if (client == null) c.close();
  }
}

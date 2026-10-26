import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/entry.dart';

class AiConfig {
  const AiConfig({
    this.baseUrl = defaultBaseUrl,
    this.apiKey = '',
    this.model = defaultModel,
    this.autoTag = false,
    this.consented = false,
  });

  static const defaultBaseUrl = 'https://openrouter.ai/api/v1';
  static const defaultModel = 'google/gemini-2.5-flash-lite';

  final String baseUrl;
  final String apiKey;
  final String model;

  /// Suggest tags automatically after saving an entry.
  final bool autoTag;

  /// The user agreed that entry text is sent to the provider.
  final bool consented;

  bool get isConfigured => apiKey.trim().isNotEmpty && model.trim().isNotEmpty;

  /// Host that receives entry text; consent is given per host.
  String get host => Uri.tryParse(baseUrl.trim())?.host ?? baseUrl;

  AiConfig copyWith({String? baseUrl, String? apiKey, String? model, bool? autoTag, bool? consented}) => AiConfig(
    baseUrl: baseUrl ?? this.baseUrl,
    apiKey: apiKey ?? this.apiKey,
    model: model ?? this.model,
    autoTag: autoTag ?? this.autoTag,
    consented: consented ?? this.consented,
  );

  Map<String, dynamic> toJson() => {
    'base_url': baseUrl,
    'api_key': apiKey,
    'model': model,
    'auto': autoTag,
    'consented': consented,
  };

  factory AiConfig.fromJson(Map<String, dynamic>? j) => j == null
      ? const AiConfig()
      : AiConfig(
          baseUrl: (j['base_url'] as String?) ?? defaultBaseUrl,
          apiKey: (j['api_key'] as String?) ?? '',
          model: (j['model'] as String?) ?? defaultModel,
          autoTag: (j['auto'] as bool?) ?? false,
          consented: (j['consented'] as bool?) ?? false,
        );
}

class AiException implements Exception {
  AiException(this.message);

  /// `no_key`, `https_only` or a provider / network message.
  final String message;
  @override
  String toString() => message;
}

/// Suggests hashtags through any OpenAI-compatible `chat/completions` API (OpenRouter by default).
class AiTagger {
  AiTagger(this.config, {http.Client? client}) : _client = client ?? http.Client();

  final AiConfig config;
  final http.Client _client;

  static const maxChars = 6000;
  static const maxKnownTags = 200;

  static String systemPrompt(String languageHint) =>
      'You tag personal diary entries. Return 3 to 7 short hashtags that describe the topics, '
      'people (by role, never by full name), places, activities and emotions of the entry. '
      'Write tags in the language of the entry, lowercase, one or two words joined by "_", no "#". '
      'Prefer tags from the list of existing tags when they fit, so the vocabulary stays small. '
      'Answer only with JSON: {"tags": ["tag1", "tag2"]}.$languageHint';

  /// Builds the request body; public for tests.
  Map<String, dynamic> buildRequest(Entry entry, List<String> knownTags) {
    var text = [if (entry.title.isNotEmpty) entry.title, entry.body].join('\n\n');
    if (text.length > maxChars) text = text.substring(0, maxChars);
    final known = knownTags.take(maxKnownTags).join(', ');
    return {
      'model': config.model,
      'temperature': 0.2,
      'max_tokens': 200,
      'response_format': {'type': 'json_object'},
      'messages': [
        {'role': 'system', 'content': systemPrompt('')},
        {
          'role': 'user',
          'content': 'Existing tags: ${known.isEmpty ? '(none yet)' : known}\n\nEntry:\n"""\n$text\n"""',
        },
      ],
    };
  }

  Future<List<String>> suggest(Entry entry, List<String> knownTags) async {
    if (!config.isConfigured) throw AiException('no_key');
    final uri = Uri.tryParse('${config.baseUrl.trim().replaceAll(RegExp(r'/+$'), '')}/chat/completions');
    // The key and the diary text must never travel in clear text.
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) throw AiException('https_only');
    final http.Response res;
    try {
      res = await _client
          .post(
            uri,
            headers: {
              'Authorization': 'Bearer ${config.apiKey.trim()}',
              'Content-Type': 'application/json',
              // OpenRouter app attribution headers; other providers ignore them.
              'HTTP-Referer': 'https://github.com/SyberYP/letopis',
              'X-Title': 'Letopis',
            },
            body: jsonEncode(buildRequest(entry, knownTags)),
          )
          .timeout(const Duration(seconds: 45));
    } catch (e) {
      throw AiException('network: $e');
    }
    if (res.statusCode != 200) {
      throw AiException('HTTP ${res.statusCode}: ${_errorMessage(res.body)}');
    }
    final Map<String, dynamic> data;
    try {
      data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    } on FormatException {
      throw AiException('bad response');
    }
    final content = ((data['choices'] as List?)?.firstOrNull as Map?)?['message']?['content'];
    if (content is! String) throw AiException('empty response');
    final existing = entry.allTags.toSet();
    return parseTags(content).where((t) => !existing.contains(t)).toList();
  }

  static String _errorMessage(String body) {
    try {
      final j = jsonDecode(body);
      final m = j['error']?['message'] ?? j['message'];
      if (m != null) return '$m';
    } catch (_) {}
    return body.length > 200 ? body.substring(0, 200) : body;
  }

  /// Lenient parsing: JSON object, a JSON array somewhere in the text, or a comma/line list.
  static List<String> parseTags(String content) {
    var raw = <dynamic>[];
    final cleaned = content.replaceAll(RegExp(r'```(json)?'), '').trim();
    try {
      final j = jsonDecode(cleaned);
      if (j is Map && j['tags'] is List) raw = j['tags'] as List;
      if (j is List) raw = j;
    } on FormatException {
      final obj = RegExp(r'\{[\s\S]*\}').firstMatch(cleaned);
      final arr = RegExp(r'\[[\s\S]*?\]').firstMatch(cleaned);
      try {
        if (obj != null) {
          final j = jsonDecode(obj.group(0)!);
          if (j is Map && j['tags'] is List) raw = j['tags'] as List;
        }
      } on FormatException {
        // try the array
      }
      if (raw.isEmpty && arr != null) {
        try {
          raw = jsonDecode(arr.group(0)!) as List;
        } on FormatException {
          // fall through to plain list
        }
      }
      if (raw.isEmpty) raw = cleaned.split(RegExp(r'[,\n]'));
    }
    final out = <String>[];
    for (final r in raw) {
      final t = normalizeTag('$r');
      if (t != null && !out.contains(t)) out.add(t);
    }
    return out.take(10).toList();
  }
}

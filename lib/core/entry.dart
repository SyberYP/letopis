import 'package:uuid/uuid.dart';

const _uuid = Uuid();
String newId() => _uuid.v4();

enum AttachmentType {
  photo,
  video,
  audio,
  file;

  static AttachmentType parse(String? s) =>
      AttachmentType.values.firstWhere((t) => t.name == s, orElse: () => AttachmentType.file);

  static AttachmentType fromMime(String mime) {
    if (mime.startsWith('image/')) return photo;
    if (mime.startsWith('video/')) return video;
    if (mime.startsWith('audio/')) return audio;
    return file;
  }
}

class Attachment {
  const Attachment({
    required this.id,
    required this.type,
    required this.name,
    required this.mime,
    this.size = 0,
    this.durationMs,
  });

  final String id;
  final AttachmentType type;

  /// Original file name, shown in the UI and used for the extension in plain exports.
  final String name;
  final String mime;
  final int size;
  final int? durationMs;

  String get extension {
    final dot = name.lastIndexOf('.');
    if (dot > 0 && dot < name.length - 1) return name.substring(dot + 1).toLowerCase();
    return switch (mime) {
      'image/jpeg' => 'jpg',
      'image/png' => 'png',
      'video/mp4' => 'mp4',
      'audio/mp4' || 'audio/aac' || 'audio/m4a' => 'm4a',
      _ => 'bin',
    };
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'name': name,
    'mime': mime,
    if (size > 0) 'size': size,
    if (durationMs != null) 'duration_ms': durationMs,
  };

  factory Attachment.fromJson(Map j) => Attachment(
    id: '${j['id']}',
    type: AttachmentType.parse(j['type'] as String?),
    name: '${j['name'] ?? j['id']}',
    mime: '${j['mime'] ?? 'application/octet-stream'}',
    size: (j['size'] as num?)?.toInt() ?? 0,
    durationMs: (j['duration_ms'] as num?)?.toInt(),
  );
}

class Entry {
  Entry({
    required this.id,
    required this.created,
    required this.updated,
    this.title = '',
    this.body = '',
    List<String>? tags,
    List<Attachment>? attachments,
    this.mood,
  }) : tags = tags ?? [],
       attachments = attachments ?? [];

  factory Entry.create({DateTime? at}) {
    final now = at ?? DateTime.now();
    return Entry(id: newId(), created: now, updated: now);
  }

  final String id;
  DateTime created;
  DateTime updated;
  String title;
  String body;

  /// Tags set explicitly (chips, AI). Hashtags in the body are added by [allTags].
  List<String> tags;
  List<Attachment> attachments;
  int? mood;

  /// Explicit tags plus #hashtags found in the body, lowercase, without '#', in order.
  List<String> get allTags {
    final seen = <String>{};
    return [
      for (final t in [...tags, ...extractHashtags(body)])
        if (seen.add(t)) t,
    ];
  }

  bool get isEmpty => title.trim().isEmpty && body.trim().isEmpty && attachments.isEmpty;

  /// Title, or the first non-empty line of the body without Markdown markers.
  String get displayTitle {
    if (title.trim().isNotEmpty) return title.trim();
    for (final line in body.split('\n')) {
      final clean = plainText(line).trim();
      if (clean.isNotEmpty) return clean;
    }
    return '';
  }

  /// Body as plain text for previews and search.
  String get preview => plainText(body);

  int get wordCount => RegExp(r'[\p{L}\p{N}]+', unicode: true).allMatches(body).length;

  Entry copy() => Entry(
    id: id,
    created: created,
    updated: updated,
    title: title,
    body: body,
    tags: List.of(tags),
    attachments: List.of(attachments),
    mood: mood,
  );

  bool sameContent(Entry o) =>
      title == o.title &&
      body == o.body &&
      created.isAtSameMomentAs(o.created) &&
      mood == o.mood &&
      _listEq(tags, o.tags) &&
      _listEq([for (final a in attachments) a.id], [for (final a in o.attachments) a.id]);
}

bool _listEq(List a, List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

final _hashtag = RegExp(r'(?<![\p{L}\p{N}_&/#])#([\p{L}\p{N}_][\p{L}\p{N}_\-]*)', unicode: true);
final _fence = RegExp(r'```[\s\S]*?(```|$)|`[^`\n]*`');
final _link = RegExp(r'\]\([^)]*\)');

/// `#tags` in Markdown text, ignoring code and link targets. Lowercase, without '#'.
List<String> extractHashtags(String text) {
  final clean = text.replaceAll(_fence, ' ').replaceAll(_link, ']');
  final out = <String>[];
  for (final m in _hashtag.allMatches(clean)) {
    var tag = m.group(1)!.toLowerCase();
    while (tag.endsWith('-') || tag.endsWith('_')) {
      tag = tag.substring(0, tag.length - 1);
    }
    if (tag.isEmpty || RegExp(r'^\d+$').hasMatch(tag)) continue; // "#1" is not a tag
    if (!out.contains(tag)) out.add(tag);
  }
  return out;
}

/// Normalizes a tag typed by the user or returned by AI.
String? normalizeTag(String raw) {
  var t = raw.trim().toLowerCase();
  while (t.startsWith('#')) {
    t = t.substring(1);
  }
  t = t.replaceAll(RegExp(r'\s+'), '_').replaceAll(RegExp(r'[^\p{L}\p{N}_\-]', unicode: true), '');
  if (t.isEmpty || t.length > 40) return null;
  return t;
}

final _mdImage = RegExp(r'!\[[^\]]*\]\([^)]*\)');
final _mdLink = RegExp(r'\[([^\]]*)\]\([^)]*\)');
final _mdMarks = RegExp(r'^\s{0,3}(#{1,6}\s+|>\s?|[-*+]\s+(\[[ xX]\]\s+)?|\d+[.)]\s+)', multiLine: true);
final _mdEmph = RegExp(r'(\*\*|__|\*|_|~~|`)');

/// Rough Markdown → plain text for previews.
String plainText(String md) => md
    .replaceAll(_mdImage, '')
    .replaceAllMapped(_mdLink, (m) => m.group(1)!)
    .replaceAll(_mdMarks, '')
    .replaceAll(_mdEmph, '')
    .replaceAll(RegExp(r'^\s*([-*_]\s*){3,}$', multiLine: true), '');

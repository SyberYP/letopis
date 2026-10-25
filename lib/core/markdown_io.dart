import 'dart:convert';

import 'package:yaml/yaml.dart';

import 'entry.dart';

/// `2026-10-25T09:41:00+03:00` — local time with its UTC offset.
String isoWithOffset(DateTime t) {
  final local = t.toLocal();
  final off = local.timeZoneOffset;
  final sign = off.isNegative ? '-' : '+';
  final m = off.inMinutes.abs();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${local.year.toString().padLeft(4, '0')}-${two(local.month)}-${two(local.day)}'
      'T${two(local.hour)}:${two(local.minute)}:${two(local.second)}'
      '$sign${two(m ~/ 60)}:${two(m % 60)}';
}

DateTime? _parseTime(Object? v) {
  if (v == null) return null;
  if (v is DateTime) return v.toLocal();
  return DateTime.tryParse('$v'.trim())?.toLocal();
}

/// Entry → Markdown with a YAML front matter. Values are written as JSON, which is valid YAML,
/// so any text survives quoting.
String entryToMarkdown(Entry e) {
  final b = StringBuffer('---\n')
    ..writeln('id: ${e.id}')
    ..writeln('created: ${isoWithOffset(e.created)}')
    ..writeln('updated: ${isoWithOffset(e.updated)}');
  if (e.title.isNotEmpty) b.writeln('title: ${jsonEncode(e.title)}');
  if (e.tags.isNotEmpty) b.writeln('tags: ${jsonEncode(e.tags)}');
  if (e.mood != null) b.writeln('mood: ${e.mood}');
  if (e.attachments.isNotEmpty) {
    b.writeln('attachments:');
    for (final a in e.attachments) {
      b.writeln('  - ${jsonEncode(a.toJson())}');
    }
  }
  b
    ..writeln('---')
    ..write(e.body);
  return b.toString();
}

final _frontMatter = RegExp(r'^﻿?---[ \t]*\r?\n([\s\S]*?)\r?\n---[ \t]*(\r?\n|$)');

/// Parses Markdown with an optional front matter. Missing fields are filled from [fallbackTime]
/// (e.g. a date in the file name) and a new id.
Entry entryFromMarkdown(String text, {DateTime? fallbackTime, String? fallbackId}) {
  var meta = <dynamic, dynamic>{};
  var body = text;
  final m = _frontMatter.firstMatch(text);
  if (m != null) {
    try {
      final y = loadYaml(m.group(1)!);
      if (y is Map) {
        meta = y;
        body = text.substring(m.end);
      }
    } on YamlException {
      // Not a front matter after all: keep the whole text as the body.
    }
  }
  final created = _parseTime(meta['created'] ?? meta['date']) ?? fallbackTime ?? DateTime.now();
  final tags = <String>[];
  final rawTags = meta['tags'];
  for (final t in rawTags is List ? rawTags : (rawTags is String ? rawTags.split(',') : const [])) {
    final n = normalizeTag('$t');
    if (n != null && !tags.contains(n)) tags.add(n);
  }
  final atts = <Attachment>[];
  final rawAtts = meta['attachments'];
  if (rawAtts is List) {
    for (final a in rawAtts) {
      if (a is Map && a['id'] != null) atts.add(Attachment.fromJson(a));
    }
  }
  final mood = meta['mood'];
  return Entry(
    id: '${meta['id'] ?? fallbackId ?? newId()}',
    created: created,
    updated: _parseTime(meta['updated']) ?? created,
    title: meta['title'] == null ? '' : '${meta['title']}',
    body: body,
    tags: tags,
    attachments: atts,
    mood: mood is int && mood >= 1 && mood <= 5 ? mood : null,
  );
}

/// Link target used inside entry bodies for attachments: `att:<id>`.
String attachmentUri(String id) => 'att:$id';

final attachmentRef = RegExp(r'att:([0-9a-fA-F-]{36})');

/// Body with `att:<id>` links rewritten through [resolve] (for plain exports).
String rewriteAttachmentLinks(String body, String Function(String id) resolve) =>
    body.replaceAllMapped(attachmentRef, (m) => resolve(m.group(1)!));

/// Markdown snippet to insert for a new attachment.
String attachmentMarkdown(Attachment a, {String? label}) => switch (a.type) {
  AttachmentType.photo => '![${label ?? ''}](${attachmentUri(a.id)})',
  AttachmentType.video => '[🎬 ${label ?? a.name}](${attachmentUri(a.id)})',
  AttachmentType.audio => '[🎙 ${label ?? a.name}](${attachmentUri(a.id)})',
  AttachmentType.file => '[📎 ${label ?? a.name}](${attachmentUri(a.id)})',
};

/// A file-system friendly slug: `2026-10-25-0941-utro` style, keeps Cyrillic.
String entrySlug(Entry e, {int maxWords = 6}) {
  final t = e.created.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  final stamp = '${t.year}-${two(t.month)}-${two(t.day)}-${two(t.hour)}${two(t.minute)}';
  final words = RegExp(
    r'[\p{L}\p{N}]+',
    unicode: true,
  ).allMatches(e.displayTitle.toLowerCase()).map((m) => m.group(0)!).take(maxWords).join('-');
  final short = words.length > 50 ? words.substring(0, 50) : words;
  return short.isEmpty ? stamp : '$stamp-$short';
}

import '../core/entry.dart';
import '../core/markdown_io.dart';

/// Result of parsing an import file, shown to the user before anything is saved.
class ImportPreview {
  ImportPreview(this.format, this.entries);
  final String format;
  final List<Entry> entries;

  DateTime? get first => entries.isEmpty ? null : entries.map((e) => e.created).reduce((a, b) => a.isBefore(b) ? a : b);
  DateTime? get last => entries.isEmpty ? null : entries.map((e) => e.created).reduce((a, b) => a.isAfter(b) ? a : b);
}

const _months = {
  'января': 1, 'февраля': 2, 'марта': 3, 'апреля': 4, 'мая': 5, 'июня': 6,
  'июля': 7, 'августа': 8, 'сентября': 9, 'октября': 10, 'ноября': 11, 'декабря': 12,
  'январь': 1, 'февраль': 2, 'март': 3, 'апрель': 4, 'май': 5, 'июнь': 6,
  'июль': 7, 'август': 8, 'сентябрь': 9, 'октябрь': 10, 'ноябрь': 11, 'декабрь': 12,
};

final _separator = RegExp(r'\r?\n-{20,}[ \t]*(\r?\n|$)');

/// `27 Сентября 2026 Воскресенье 01:44`
final _diaryHeader =
    RegExp(r'^(\d{1,2}) ([А-Яа-яЁё]+) (\d{4})(?: [А-Яа-яЁё]+)? (\d{1,2}):(\d{2})\s*$');

/// `2025/05/03 text…` (MyDiary export)
final _myDiaryHeader = RegExp(r'^(\d{4})/(\d{2})/(\d{2})(?: (\d{1,2}):(\d{2}))?[ \t]*');

/// Title line `Заголовок (Категория)`: the category becomes a tag.
final _titleCategory = RegExp(r'^(.*?)\s*\(([^()]{1,40})\)\s*$');

/// Detects and parses a text export. Supported:
///  * the "date / title (category) / text / -----" diary export;
///  * MyDiary "YYYY/MM/DD text" export;
///  * a single Markdown file (with or without front matter).
ImportPreview parseImport(String text, {String fileName = ''}) {
  final normalized = text.replaceAll('\r\n', '\n').replaceFirst('﻿', '');
  final blocks = normalized.split(_separator).where((b) => b.trim().isNotEmpty).toList();
  if (blocks.isNotEmpty) {
    final heads = blocks.map((b) => b.trimLeft().split('\n').first).toList();
    if (heads.where(_diaryHeader.hasMatch).length >= (blocks.length * 0.8)) {
      return ImportPreview('diary', [for (final b in blocks) ?_parseDiaryBlock(b)]);
    }
    if (heads.where(_myDiaryHeader.hasMatch).length >= (blocks.length * 0.8)) {
      return ImportPreview('mydiary', [for (final b in blocks) ?_parseMyDiaryBlock(b)]);
    }
  }
  return ImportPreview('markdown', [
    entryFromMarkdown(normalized, fallbackTime: dateFromFileName(fileName)),
  ]);
}

Entry? _parseDiaryBlock(String block) {
  final lines = block.trimLeft().split('\n');
  final m = _diaryHeader.firstMatch(lines.first);
  if (m == null) return null;
  final month = _months[m.group(2)!.toLowerCase()];
  if (month == null) return null;
  final created = DateTime(int.parse(m.group(3)!), month, int.parse(m.group(1)!),
      int.parse(m.group(4)!), int.parse(m.group(5)!));
  var title = '';
  final tags = <String>[];
  var bodyStart = 1;
  if (lines.length > 1) {
    final t = _titleCategory.firstMatch(lines[1]);
    if (t != null) {
      title = t.group(1)!.trim();
      final tag = normalizeTag(t.group(2)!);
      if (tag != null) tags.add(tag);
      bodyStart = 2;
    }
  }
  final body = lines.skip(bodyStart).join('\n').trim();
  return Entry(id: newId(), created: created, updated: created, title: title, body: body, tags: tags);
}

Entry? _parseMyDiaryBlock(String block) {
  final text = block.trim();
  final m = _myDiaryHeader.firstMatch(text);
  if (m == null) return null;
  final created = DateTime(
    int.parse(m.group(1)!),
    int.parse(m.group(2)!),
    int.parse(m.group(3)!),
    m.group(4) == null ? 12 : int.parse(m.group(4)!),
    m.group(5) == null ? 0 : int.parse(m.group(5)!),
  );
  return Entry(
      id: newId(), created: created, updated: created, body: text.substring(m.end).trim());
}

/// `2026-10-25-0941-title.md` or `2026-10-25.md` → a time.
DateTime? dateFromFileName(String name) {
  final m = RegExp(r'(\d{4})-(\d{2})-(\d{2})(?:[-_T ](\d{2})[:\-]?(\d{2}))?').firstMatch(name);
  if (m == null) return null;
  return DateTime(int.parse(m.group(1)!), int.parse(m.group(2)!), int.parse(m.group(3)!),
      int.tryParse(m.group(4) ?? '') ?? 12, int.tryParse(m.group(5) ?? '') ?? 0);
}

/// Key that identifies the same entry imported twice.
String duplicateKey(Entry e) {
  final t = e.created;
  final text = '${e.title}\n${e.body}'.trim();
  return '${t.year}-${t.month}-${t.day}-${t.hour}-${t.minute}|'
      '${text.length > 200 ? text.substring(0, 200) : text}';
}

import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:markdown/markdown.dart' as md;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../core/entry.dart';
import '../core/store.dart';

/// Turns the diary (or part of it) into a printable book: A5 pages, a cover, entries oldest first,
/// grouped by month, Markdown formatting, photos. The PDF is NOT encrypted — like the ZIP export it
/// is written to the temporary folder (wiped on lock) and handed to the share sheet.

/// Font files: the face picked in the settings and Noto Emoji from the app assets, plus system
/// fonts for other scripts ([fallback]); read by the caller.
class PdfFonts {
  const PdfFonts({
    required this.regular,
    required this.bold,
    required this.italic,
    this.emoji,
    this.fallback = const [],
  });
  final Uint8List regular;
  final Uint8List bold;
  final Uint8List italic;
  final Uint8List? emoji;
  final List<Uint8List> fallback;
}

/// Everything the layout needs, already decrypted and formatted: it runs in a background
/// isolate, which can't read the store or the localized strings.
class PdfEntry {
  PdfEntry({
    required this.month,
    required this.date,
    required this.title,
    required this.body,
    this.mood,
    this.tags = const [],
    this.images = const {},
    this.gallery = const [],
    this.files = const [],
  });

  /// "Октябрь 2026": a heading is printed when it changes.
  final String month;

  /// "понедельник, 26 октября 2026 · 08:15".
  final String date;
  final String title;
  final String body;
  final String? mood;
  final List<String> tags;

  /// Photo id → downscaled JPEG; `![](att:id)` in the body and [gallery] point here.
  final Map<String, Uint8List> images;

  /// Photos not placed in the text, shown after it.
  final List<String> gallery;

  /// Other attachments: "Голосовая запись · Голос 18:40.m4a · 0:42".
  final List<String> files;
}

class PdfBook {
  PdfBook({
    required this.title,
    required this.subtitle,
    required this.note,
    required this.entries,
    required this.fonts,
    this.missing = '',
  });
  final String title;
  final String subtitle;

  /// Small print on the cover: number of entries and date of the export.
  final String note;
  final List<PdfEntry> entries;
  final PdfFonts fonts;

  /// Shown instead of a photo that couldn't be read.
  final String missing;
}

/// Labels and date formats from the UI layer (the service doesn't know the locale).
class PdfText {
  const PdfText({
    required this.month,
    required this.date,
    required this.mood,
    required this.attachment,
  });
  final String Function(DateTime) month;
  final String Function(DateTime) date;
  final String Function(int) mood;
  final String Function(Attachment) attachment;
}

/// Decrypts and downsizes what the selected [entries] need. [onProgress] gets (done, total).
Future<List<PdfEntry>> preparePdfEntries(
  EntryStore store,
  List<Entry> entries, {
  required bool photos,
  required PdfText text,
  void Function(int done, int total)? onProgress,
}) async {
  final sorted = [...entries]..sort((a, b) => a.created.compareTo(b.created));
  final out = <PdfEntry>[];
  for (var i = 0; i < sorted.length; i++) {
    final e = sorted[i];
    final t = e.created.toLocal();
    final images = <String, Uint8List>{};
    final files = <String>[];
    final inline = RegExp(r'\(att:([A-Za-z0-9_-]+)\)').allMatches(e.body).map((m) => m.group(1)!).toSet();
    final gallery = <String>[];
    for (final a in e.attachments) {
      if (a.type == AttachmentType.photo) {
        if (!photos) continue;
        if (store.hasMedia(a.id)) {
          try {
            final small = await makeThumbnail(await store.mediaBytes(a.id), maxSide: 1100);
            if (small != null) images[a.id] = small;
          } catch (_) {
            // a damaged photo must not stop the export
          }
        }
        if (!inline.contains(a.id)) gallery.add(a.id);
      } else {
        files.add(text.attachment(a));
      }
    }
    out.add(
      PdfEntry(
        month: text.month(t),
        date: text.date(t),
        title: e.title.trim(),
        body: e.body,
        mood: e.mood == null ? null : text.mood(e.mood!),
        tags: e.allTags,
        images: images,
        gallery: gallery,
        files: files,
      ),
    );
    onProgress?.call(i + 1, sorted.length);
  }
  return out;
}

/// Lays the book out in a background isolate and writes it to [outDir]/[fileName].
Future<File> writePdf(PdfBook book, Directory outDir, String fileName) async {
  final bytes = await Isolate.run(() => buildPdf(book));
  await outDir.create(recursive: true);
  final f = File('${outDir.path}/$fileName');
  await f.writeAsBytes(bytes, flush: true);
  return f;
}

const _accent = PdfColor.fromInt(0xFF4B4BC4);
const _muted = PdfColor.fromInt(0xFF6B6878);
const _rule = PdfColor.fromInt(0xFFD9D6E6);
const _quoteBg = PdfColor.fromInt(0xFFF1F0FA);

/// The layout itself: pure Dart, no Flutter, safe in an isolate. Public for tests.
Future<Uint8List> buildPdf(PdfBook book) async {
  final f = book.fonts;
  final regular = pw.Font.ttf(f.regular.buffer.asByteData(f.regular.offsetInBytes, f.regular.lengthInBytes));
  final bold = pw.Font.ttf(f.bold.buffer.asByteData(f.bold.offsetInBytes, f.bold.lengthInBytes));
  final italic = pw.Font.ttf(f.italic.buffer.asByteData(f.italic.offsetInBytes, f.italic.lengthInBytes));
  final emoji = f.emoji == null
      ? null
      : pw.Font.ttf(f.emoji!.buffer.asByteData(f.emoji!.offsetInBytes, f.emoji!.lengthInBytes));
  final system = [for (final b in f.fallback) b.buffer.asByteData(b.offsetInBytes, b.lengthInBytes)];
  final fallback = [?emoji, for (final b in system) pw.Font.ttf(b)];
  final arabicAt = system.indexWhere((b) {
    final glyphs = TtfParser(b).charToGlyphIndexMap;
    return glyphs.containsKey(0x0627) && glyphs.containsKey(0xFE8E);
  });
  final scripts = _Scripts(arabicAt < 0 ? null : fallback[arabicAt + (emoji == null ? 0 : 1)]);
  final theme = pw.ThemeData.withFont(
    base: regular,
    bold: bold,
    italic: italic,
    boldItalic: bold,
    fontFallback: fallback,
  ).copyWith(defaultTextStyle: pw.TextStyle(font: regular, fontSize: 10.5, lineSpacing: 2.5, fontFallback: fallback));

  final doc = pw.Document(title: book.title, creator: 'Letopis', producer: 'Letopis');
  const format = PdfPageFormat.a5;
  const margin = pw.EdgeInsets.fromLTRB(46, 44, 46, 40);

  doc.addPage(
    pw.Page(
      pageFormat: format,
      theme: theme,
      margin: margin,
      build: (_) => pw.Column(
        mainAxisAlignment: pw.MainAxisAlignment.center,
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(width: 40, height: 3, color: _accent),
          pw.SizedBox(height: 18),
          pw.Text(book.title, style: pw.TextStyle(font: bold, fontSize: 34)),
          pw.SizedBox(height: 8),
          pw.Text(book.subtitle, style: const pw.TextStyle(fontSize: 16, color: _accent)),
          pw.SizedBox(height: 40),
          pw.Text(book.note, style: const pw.TextStyle(fontSize: 10, color: _muted)),
        ],
      ),
    ),
  );

  final width = format.width - margin.horizontal;
  final children = <pw.Widget>[];
  String? month;
  for (final e in book.entries) {
    final head = <pw.Widget>[];
    if (e.month != month) {
      month = e.month;
      head.addAll([
        if (children.isNotEmpty) pw.SizedBox(height: 10),
        pw.Text(e.month, style: pw.TextStyle(font: bold, fontSize: 17)),
        pw.Container(margin: const pw.EdgeInsets.only(top: 4, bottom: 12), height: 1, color: _rule),
      ]);
    }
    head.add(pw.Text(e.date, style: const pw.TextStyle(fontSize: 9, color: _accent, letterSpacing: 0.3)));
    if (e.title.isNotEmpty) {
      head.add(pw.Padding(
        padding: const pw.EdgeInsets.only(top: 3),
        child: _dirText(e.title, pw.TextStyle(font: bold, fontSize: 13.5), width, scripts),
      ));
    }
    if (e.mood != null) head.add(pw.Text(e.mood!, style: const pw.TextStyle(fontSize: 9, color: _muted)));
    // The heading stays together with the date and title.
    children.add(pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: head));
    children.add(pw.SizedBox(height: 6));
    children.addAll(_MdToPdf(e, width, bold: bold, italic: italic, missing: book.missing, scripts: scripts).blocks());
    if (e.gallery.isNotEmpty) children.addAll(_gallery(e, width));
    for (final line in e.files) {
      children.add(pw.Padding(
        padding: const pw.EdgeInsets.only(top: 4),
        child: _dirText(line, const pw.TextStyle(fontSize: 9, color: _muted), width, scripts),
      ));
    }
    if (e.tags.isNotEmpty) {
      children.add(pw.Padding(
        padding: const pw.EdgeInsets.only(top: 6),
        child: _dirText(e.tags.map((t) => '#$t').join('  '), const pw.TextStyle(fontSize: 9, color: _accent), width, scripts),
      ));
    }
    children.add(pw.SizedBox(height: 18));
  }

  doc.addPage(
    pw.MultiPage(
      pageFormat: format,
      theme: theme,
      margin: margin,
      maxPages: 100000,
      footer: (ctx) => pw.Container(
        alignment: pw.Alignment.center,
        margin: const pw.EdgeInsets.only(top: 10),
        child: pw.Text('${ctx.pageNumber}', style: const pw.TextStyle(fontSize: 8.5, color: _muted)),
      ),
      build: (_) => children,
    ),
  );
  return doc.save();
}

/// Arabic and Urdu (and Hebrew) paragraphs run right to left; the first strong letter decides.
final _strongLetter = RegExp(
  r'[A-Za-z\u00C0-\u024F\u0370-\u03FF\u0400-\u04FF\u0590-\u08FF\u0900-\u0DFF\u1E00-\u1EFF\u3040-\u9FFF\uAC00-\uD7AF\uFB1D-\uFDFF\uFE70-\uFEFF]',
);
final _rtlLetter = RegExp(r'[\u0590-\u08FF\uFB1D-\uFDFF\uFE70-\uFEFF]');

pw.TextDirection textDirectionOf(String text) {
  final m = _strongLetter.firstMatch(text);
  return m != null && _rtlLetter.hasMatch(m.group(0)!) ? pw.TextDirection.rtl : pw.TextDirection.ltr;
}

pw.Widget _dirText(String text, pw.TextStyle style, double width, _Scripts scripts) {
  final dir = textDirectionOf(text);
  final t = pw.RichText(
    text: pw.TextSpan(style: style, children: scripts.spans(text, style)),
    textDirection: dir,
    textAlign: _align(dir),
  );
  return dir == pw.TextDirection.rtl ? _fullWidth(t, width) : t;
}

const _arabicLetter = r'[؀-ۿݐ-ݿࢠ-ࣿﭐ-﷿ﹰ-﻿]';

/// A run of Arabic-script words with the spaces, digits and punctuation between them. Public for tests.
final arabicRun = RegExp('$_arabicLetter+(?:[\\s.,!?:;()«»"\'\\-–—0-9]+$_arabicLetter+)*');

/// The pdf library hands every letter the main font lacks to a fallback font one at a time, and an
/// Arabic letter shaped on its own never joins its neighbours. So each Arabic run (with the spaces and
/// punctuation inside it) gets the Arabic font as its main font and is shaped whole.
class _Scripts {
  _Scripts(this.arabic);
  final pw.Font? arabic;


  List<pw.InlineSpan> spans(String text, pw.TextStyle style) {
    final font = arabic;
    if (font == null) return [pw.TextSpan(text: text, style: style)];
    final runStyle = style.copyWith(font: font, fontNormal: font, fontBold: font, fontItalic: font, fontBoldItalic: font);
    final out = <pw.InlineSpan>[];
    var at = 0;
    for (final m in arabicRun.allMatches(text)) {
      if (m.start > at) out.add(pw.TextSpan(text: text.substring(at, m.start), style: style));
      out.add(pw.TextSpan(text: m.group(0), style: runStyle));
      at = m.end;
    }
    if (at < text.length) out.add(pw.TextSpan(text: text.substring(at), style: style));
    return out;
  }
}

pw.TextAlign _align(pw.TextDirection dir) => dir == pw.TextDirection.rtl ? pw.TextAlign.right : pw.TextAlign.left;

/// A short right-to-left line still has to sit at the right edge, so the text gets the whole width.
/// ConstrainedBox is a SingleChildWidget: a long paragraph inside still breaks across pages.
pw.Widget _fullWidth(pw.Widget child, double width) =>
    pw.ConstrainedBox(constraints: pw.BoxConstraints(minWidth: width), child: child);

/// TextOverflow.span lets a long paragraph continue on the next page.
pw.Widget _richText(List<md.Node> nodes, List<pw.InlineSpan> spans, double width) {
  final dir = textDirectionOf(nodes.map((n) => n.textContent).join());
  final t = pw.RichText(
    text: pw.TextSpan(children: spans),
    overflow: pw.TextOverflow.span,
    textDirection: dir,
    textAlign: _align(dir),
  );
  return dir == pw.TextDirection.rtl ? _fullWidth(t, width) : t;
}

List<pw.Widget> _gallery(PdfEntry e, double width) {
  final ids = e.gallery.where(e.images.containsKey).toList();
  if (ids.isEmpty) return [];
  if (ids.length == 1) return [_photo(e.images[ids.first]!, width)];
  const gap = 6.0;
  final w = (width - gap) / 2;
  final rows = <pw.Widget>[];
  pw.Widget cell(String id) => pw.ClipRRect(
    horizontalRadius: 6,
    verticalRadius: 6,
    child: pw.Image(pw.MemoryImage(e.images[id]!), width: w, height: w * 0.75, fit: pw.BoxFit.cover),
  );
  for (var i = 0; i < ids.length; i += 2) {
    final pair = ids.skip(i).take(2).toList();
    rows.add(pw.Padding(
      padding: const pw.EdgeInsets.only(top: gap),
      child: pw.Row(children: [cell(pair[0]), if (pair.length > 1) ...[pw.SizedBox(width: gap), cell(pair[1])]]),
    ));
  }
  return rows;
}

pw.Widget _photo(Uint8List bytes, double width) => pw.Padding(
  padding: const pw.EdgeInsets.symmetric(vertical: 6),
  child: pw.ClipRRect(
    horizontalRadius: 6,
    verticalRadius: 6,
    child: pw.Image(pw.MemoryImage(bytes), width: width, height: 210, fit: pw.BoxFit.contain),
  ),
);

/// GitHub-flavoured Markdown → pdf widgets: paragraphs, headings, emphasis, lists and task
/// lists, quotes, code, rules, tables, `att:` photos.
class _MdToPdf {
  _MdToPdf(
    this.entry,
    this.width, {
    required this.bold,
    required this.italic,
    required this.missing,
    required this.scripts,
  });
  final PdfEntry entry;
  final _Scripts scripts;
  final double width;
  final pw.Font bold;
  final pw.Font italic;
  final String missing;

  List<pw.Widget> blocks() {
    final nodes = md.Document(extensionSet: md.ExtensionSet.gitHubFlavored, encodeHtml: false)
        .parseLines(entry.body.replaceAll('\r\n', '\n').split('\n'));
    return _blocks(nodes, const pw.TextStyle());
  }

  List<pw.Widget> _blocks(List<md.Node> nodes, pw.TextStyle style, {double indent = 0}) {
    final out = <pw.Widget>[];
    final loose = <md.Node>[];
    void flushLoose() {
      if (loose.isEmpty) return;
      out.addAll(_paragraph(List.of(loose), style, indent: indent));
      loose.clear();
    }

    for (final n in nodes) {
      if (n is! md.Element || !_blockTags.contains(n.tag)) {
        loose.add(n);
        continue;
      }
      flushLoose();
      switch (n.tag) {
        case 'p':
          out.addAll(_paragraph(n.children ?? [], style, indent: indent));
        case 'h1' || 'h2' || 'h3' || 'h4' || 'h5' || 'h6':
          final size = switch (n.tag) { 'h1' => 15.0, 'h2' => 13.5, 'h3' => 12.0, _ => 11.0 };
          out.add(pw.Padding(
            padding: pw.EdgeInsets.only(top: 6, bottom: 2, left: indent),
            child: _richText(
              n.children ?? [],
              _inline(n.children ?? [], style.copyWith(font: bold, fontSize: size)),
              width - indent,
            ),
          ));
        case 'blockquote':
          // Each paragraph gets its own bar, so a long quote can still break across pages.
          for (final w in _blocks(n.children ?? [], style.copyWith(font: italic, color: _muted)).where((w) => w is! pw.SizedBox)) {
            out.add(pw.Container(
              margin: pw.EdgeInsets.only(left: indent, top: 2, bottom: 2),
              padding: const pw.EdgeInsets.fromLTRB(10, 3, 6, 3),
              decoration: const pw.BoxDecoration(
                color: _quoteBg,
                border: pw.Border(left: pw.BorderSide(color: _accent, width: 2)),
              ),
              child: w,
            ));
          }
        case 'ul' || 'ol':
          var number = int.tryParse(n.attributes['start'] ?? '') ?? 1;
          for (final li in (n.children ?? []).whereType<md.Element>()) {
            final kids = li.children ?? [];
            final box = kids.whereType<md.Element>().where((k) => k.tag == 'input').firstOrNull;
            final rest = kids.where((k) => k != box).toList();
            final pw.Widget marker = box != null
                ? _checkbox(box.attributes.containsKey('checked'))
                : pw.Text(n.tag == 'ol' ? '${number++}.' : '•', style: style);
            final body = _blocks(rest, style);
            out.add(pw.Padding(
              padding: pw.EdgeInsets.only(left: indent + 4, top: 1.5),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.SizedBox(
                    width: 16,
                    child: pw.Padding(
                      padding: const pw.EdgeInsets.only(top: 2.5),
                      child: pw.Align(alignment: pw.Alignment.topLeft, child: marker),
                    ),
                  ),
                  pw.Expanded(
                    child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: body),
                  ),
                ],
              ),
            ));
          }
        case 'pre':
          out.add(pw.Container(
            width: double.infinity,
            margin: pw.EdgeInsets.only(left: indent, top: 3, bottom: 3),
            padding: const pw.EdgeInsets.all(8),
            decoration: const pw.BoxDecoration(color: _quoteBg, borderRadius: pw.BorderRadius.all(pw.Radius.circular(4))),
            child: pw.Text(n.textContent.trimRight(), style: style.copyWith(fontSize: 9)),
          ));
        case 'hr':
          out.add(pw.Container(margin: const pw.EdgeInsets.symmetric(vertical: 8), height: 0.7, color: _rule));
        case 'table':
          out.add(_table(n, style));
        default:
          out.addAll(_blocks(n.children ?? [], style, indent: indent));
      }
    }
    flushLoose();
    return out;
  }

  static const _blockTags = {
    'p', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'blockquote', 'ul', 'ol', 'pre', 'hr', 'table', 'div', 'section',
  };

  /// Inline content; photos split it into text before, the photo, text after.
  List<pw.Widget> _paragraph(List<md.Node> nodes, pw.TextStyle style, {double indent = 0}) {
    final out = <pw.Widget>[];
    var run = <md.Node>[];
    void flush() {
      final nodes = run;
      final spans = _inline(nodes, style);
      run = [];
      if (spans.isEmpty) return;
      final text = _richText(nodes, spans, width - indent);
      out.add(indent == 0 ? text : pw.Padding(padding: pw.EdgeInsets.only(left: indent), child: text));
      out.add(pw.SizedBox(height: 4));
    }

    for (final n in nodes) {
      final img = _image(n);
      if (img != null) {
        flush();
        out.add(img);
      } else {
        run.add(n);
      }
    }
    flush();
    return out;
  }

  pw.Widget? _image(md.Node n) {
    if (n is! md.Element || n.tag != 'img') return null;
    final src = n.attributes['src'] ?? '';
    if (!src.startsWith('att:')) return null;
    final bytes = entry.images[src.substring(4)];
    if (bytes == null) {
      final alt = n.attributes['alt'] ?? '';
      return pw.Text(alt.isEmpty ? missing : alt, style: const pw.TextStyle(fontSize: 9, color: _muted));
    }
    return _photo(bytes, width);
  }

  List<pw.InlineSpan> _inline(List<md.Node> nodes, pw.TextStyle style) {
    final out = <pw.InlineSpan>[];
    for (final n in nodes) {
      if (n is md.Text) {
        if (n.text.isNotEmpty) out.addAll(scripts.spans(n.text, style));
        continue;
      }
      if (n is! md.Element) continue;
      final kids = n.children ?? [];
      switch (n.tag) {
        case 'strong':
          out.addAll(_inline(kids, style.copyWith(font: bold)));
        case 'em':
          out.addAll(_inline(kids, style.copyWith(font: italic)));
        case 'del':
          out.addAll(_inline(kids, style.copyWith(decoration: pw.TextDecoration.lineThrough)));
        case 'code':
          out.add(pw.TextSpan(
            text: n.textContent,
            style: style.copyWith(fontSize: 9.5, background: const pw.BoxDecoration(color: _quoteBg)),
          ));
        case 'a':
          out.addAll(_inline(kids, style.copyWith(color: _accent)));
        case 'br':
          out.add(pw.TextSpan(text: '\n', style: style));
        case 'img':
          final alt = n.attributes['alt'] ?? '';
          if (alt.isNotEmpty) out.add(pw.TextSpan(text: alt, style: style.copyWith(color: _muted)));
        case 'input':
          break;
        default:
          out.addAll(_inline(kids, style));
      }
    }
    return out;
  }

  pw.Widget _checkbox(bool checked) => pw.Container(
    width: 8.5,
    height: 8.5,
    decoration: pw.BoxDecoration(
      color: checked ? _accent : null,
      border: pw.Border.all(color: checked ? _accent : _muted, width: 0.8),
      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(1.5)),
    ),
    child: checked
        ? pw.CustomPaint(
            size: const PdfPoint(8.5, 8.5),
            painter: (canvas, size) {
              canvas
                ..setStrokeColor(PdfColors.white)
                ..setLineWidth(1.1)
                ..moveTo(1.8, 4.4)
                ..lineTo(3.6, 2.4)
                ..lineTo(6.9, 6.4)
                ..strokePath();
            },
          )
        : null,
  );

  pw.Widget _table(md.Element t, pw.TextStyle style) {
    final rows = <pw.TableRow>[];
    void addRows(md.Element section, {bool head = false}) {
      for (final tr in (section.children ?? []).whereType<md.Element>().where((e) => e.tag == 'tr')) {
        rows.add(pw.TableRow(
          children: [
            for (final cell in (tr.children ?? []).whereType<md.Element>())
              pw.Padding(
                padding: const pw.EdgeInsets.all(4),
                child: pw.RichText(
                  text: pw.TextSpan(children: _inline(cell.children ?? [], head ? style.copyWith(font: bold) : style)),
                ),
              ),
          ],
        ));
      }
    }

    for (final s in (t.children ?? []).whereType<md.Element>()) {
      if (s.tag == 'thead') addRows(s, head: true);
      if (s.tag == 'tbody') addRows(s);
    }
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 4),
      child: pw.Table(border: pw.TableBorder.all(color: _rule, width: 0.6), children: rows),
    );
  }
}

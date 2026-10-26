import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/entry.dart';
import '../../l10n/strings.dart';
import '../../services/pdf_export.dart';
import '../../state/app_state.dart';
import '../widgets/entry_card.dart';

/// Settings → Export to PDF: pick the period and whether to include photos, then share the file.
/// With [only], exports just those entries (the entry screen's share menu) without asking.
Future<void> exportPdfFlow(BuildContext context, {List<Entry>? only}) async {
  final app = context.read<AppState>();
  final store = app.store;
  if (store == null) return;
  var entries = only ?? store.entries.toList();
  var photos = true;
  String period = 'all';

  if (only == null) {
    if (entries.isEmpty) return;
    final years = {for (final e in entries) e.created.toLocal().year}.toList()..sort((a, b) => b - a);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) {
          final picked = _pick(entries, period);
          final photoCount = picked.fold<int>(
            0,
            (n, e) => n + e.attachments.where((a) => a.type == AttachmentType.photo).length,
          );
          return AlertDialog(
            icon: const Icon(Icons.picture_as_pdf_outlined),
            title: Text(tr('pdf')),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: period,
                  decoration: InputDecoration(labelText: tr('pdf_period')),
                  items: [
                    DropdownMenuItem(value: 'all', child: Text(tr('pdf_all'))),
                    for (final y in years) DropdownMenuItem(value: '$y', child: Text('$y')),
                  ],
                  onChanged: (v) => setState(() => period = v ?? 'all'),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(tr('pdf_photos')),
                  subtitle: Text(tr('pdf_photos_sub', {'n': photoCount})),
                  value: photos,
                  onChanged: (v) => setState(() => photos = v),
                ),
                Text(plural('entries', picked.length)),
                const SizedBox(height: 10),
                Text(
                  tr('pdf_warning'),
                  style: TextStyle(fontSize: 12.5, color: Theme.of(ctx).colorScheme.onSurfaceVariant),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('cancel'))),
              FilledButton(onPressed: picked.isEmpty ? null : () => Navigator.pop(ctx, true), child: Text(tr('pdf_make'))),
            ],
          );
        },
      ),
    );
    if (ok != true || !context.mounted) return;
    entries = _pick(entries, period);
  }

  final progress = ValueNotifier<(int, int)>((0, entries.length));
  final nav = Navigator.of(context, rootNavigator: true);
  final messenger = ScaffoldMessenger.of(context);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => PopScope(
      canPop: false,
      child: AlertDialog(
        content: ValueListenableBuilder<(int, int)>(
          valueListenable: progress,
          builder: (_, p, _) => Row(
            children: [
              const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3)),
              const SizedBox(width: 20),
              Expanded(
                child: Text(
                  p.$1 < p.$2 ? tr('pdf_progress', {'done': p.$1, 'total': p.$2}) : tr('pdf_layout'),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  File? file;
  Object? error;
  try {
    Future<Uint8List> font(String name) async => (await rootBundle.load('assets/fonts/$name')).buffer.asUint8List();
    final fonts = PdfFonts(
      regular: await font('PT_Serif-Web-Regular.ttf'),
      bold: await font('PT_Serif-Web-Bold.ttf'),
      italic: await font('PT_Serif-Web-Italic.ttf'),
      emoji: await font('NotoEmoji.ttf'),
    );
    final prepared = await preparePdfEntries(
      store,
      entries,
      photos: photos,
      text: PdfText(
        month: fmtMonthYear,
        date: (t) => '${fmtFullDate(t)} · ${fmtTime(t)}',
        mood: (m) => '${tr('mood')}: ${tr('mood_$m').toLowerCase()}',
        attachment: _attachmentLine,
      ),
      onProgress: (done, total) => progress.value = (done, total),
    );
    final first = prepared.isEmpty ? DateTime.now() : entries.map((e) => e.created).reduce((a, b) => a.isBefore(b) ? a : b);
    final last = prepared.isEmpty ? DateTime.now() : entries.map((e) => e.created).reduce((a, b) => a.isAfter(b) ? a : b);
    final String subtitle, name;
    if (only != null && entries.length == 1) {
      subtitle = fmtFullDate(first);
      name = 'letopis-${_ymd(first)}.pdf';
    } else if (first.year == last.year) {
      subtitle = '${first.year}';
      name = 'letopis-${first.year}.pdf';
    } else {
      subtitle = '${first.year} — ${last.year}';
      name = 'letopis-${first.year}-${last.year}.pdf';
    }
    file = await writePdf(
      PdfBook(
        title: tr('app_name'),
        subtitle: subtitle,
        note: '${plural('entries', entries.length)} · ${tr('pdf_made', {'date': fmtDateTime(DateTime.now())})}',
        entries: prepared,
        fonts: fonts,
        missing: tr('pdf_missing_photo'),
      ),
      Directory('${app.temp.path}/export'),
      name,
    );
  } catch (e) {
    error = e;
  } finally {
    nav.pop();
    progress.dispose();
  }
  if (error != null || file == null) {
    messenger.showSnackBar(SnackBar(content: Text(tr('error', {'error': error ?? '?'}))));
    return;
  }
  final f = file;
  await app.keepUnlocked(() => SharePlus.instance.share(ShareParams(files: [XFile(f.path, mimeType: 'application/pdf')])));
}

List<Entry> _pick(List<Entry> all, String period) =>
    period == 'all' ? all : all.where((e) => '${e.created.toLocal().year}' == period).toList();

String _ymd(DateTime t) =>
    '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';

String _attachmentLine(Attachment a) {
  final kind = switch (a.type) {
    AttachmentType.audio => tr('pdf_audio'),
    AttachmentType.video => tr('pdf_video'),
    _ => tr('pdf_file'),
  };
  final d = a.durationMs;
  final len = d == null ? '' : ' · ${d ~/ 60000}:${((d ~/ 1000) % 60).toString().padLeft(2, '0')}';
  return '$kind · ${a.name}$len';
}

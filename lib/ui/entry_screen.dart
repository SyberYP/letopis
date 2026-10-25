import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/entry.dart';
import '../l10n/strings.dart';
import '../state/app_state.dart';
import 'home_screen.dart';
import 'theme.dart';
import 'widgets/attachments.dart';
import 'widgets/entry_card.dart';
import 'widgets/markdown_view.dart';

/// Reading view of one entry.
class EntryScreen extends StatelessWidget {
  const EntryScreen({super.key, required this.entryId, this.onTag});
  final String entryId;
  final ValueChanged<String>? onTag;

  Future<void> _delete(BuildContext context) async {
    final ok = await confirmDeleteEntry(context);
    if (!ok || !context.mounted) return;
    await context.read<AppState>().deleteEntry(entryId);
    if (context.mounted) Navigator.of(context).pop();
  }

  void _tag(BuildContext context, String tag) {
    if (onTag == null) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
    onTag!(tag);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final e = app.store?.byId(entryId);
    if (e == null) return const Scaffold();
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final inline = inlineAttachmentIds(e.body);
    final rest = e.attachments.where((a) => !inline.contains(a.id)).toList();
    // Body hashtags are already tappable in the text; chips show only the extra tags.
    final bodyTags = extractHashtags(e.body).toSet();
    final chipTags = e.tags.where((t) => !bodyTags.contains(t)).toList();

    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            tooltip: tr('share'),
            icon: const Icon(Icons.ios_share_rounded),
            onPressed: () => SharePlus.instance.share(
              ShareParams(text: [if (e.title.isNotEmpty) e.title, e.body].join('\n\n'), subject: e.displayTitle),
            ),
          ),
          IconButton(
            tooltip: tr('delete'),
            icon: const Icon(Icons.delete_outline_rounded),
            onPressed: () => _delete(context),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: tr('edit'),
        onPressed: () => openEditor(context, e),
        child: const Icon(Icons.edit_rounded),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(22, 0, 22, 120),
        children: [
          Text(
            fmtFullDate(e.created),
            style: text.labelLarge?.copyWith(color: cs.primary, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              Icon(Icons.schedule_rounded, size: 15, color: cs.onSurfaceVariant),
              const SizedBox(width: 4),
              Text(fmtTime(e.created), style: TextStyle(color: cs.onSurfaceVariant)),
              if (e.mood != null) ...[const SizedBox(width: 10), Text(moodEmoji(e.mood!))],
              const Spacer(),
              Text(tr('words', {'n': e.wordCount}), style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
            ],
          ),
          if (e.title.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(e.title, style: text.headlineMedium?.copyWith(fontFamily: serif, height: 1.2)),
          ],
          const SizedBox(height: 16),
          EntryMarkdown(entry: e, onTag: (t) => _tag(context, t)),
          if (rest.isNotEmpty) ...[const SizedBox(height: 20), AttachmentGallery(entry: e, attachments: rest)],
          if (chipTags.isNotEmpty) ...[
            const SizedBox(height: 24),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [for (final t in chipTags) TagChip(t, onTap: () => _tag(context, t))],
            ),
          ],
          if (!e.updated.isAtSameMomentAs(e.created) && e.updated.difference(e.created).inMinutes > 1) ...[
            const SizedBox(height: 24),
            Text('✎ ${fmtDateTime(e.updated)}', style: TextStyle(color: cs.outline, fontSize: 12)),
          ],
        ],
      ),
    );
  }
}

Future<bool> confirmDeleteEntry(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.delete_outline_rounded),
      title: Text(tr('delete_entry')),
      content: Text(tr('delete_entry_body')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('cancel'))),
        FilledButton.tonal(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('delete'))),
      ],
    ),
  );
  return ok ?? false;
}

/// Ids of attachments referenced from the body (shown inline, not repeated below).
Set<String> inlineAttachmentIds(String body) => {
  for (final m in RegExp(r'!\[[^\]]*\]\(att:([0-9a-fA-F-]{36})\)').allMatches(body)) m.group(1)!,
};

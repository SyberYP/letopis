import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/store.dart';
import '../../l10n/strings.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import '../widgets/entry_card.dart';

/// Deleted entries, kept for [EntryStore.trashDays] days: restore or delete for good.
class TrashScreen extends StatelessWidget {
  const TrashScreen({super.key});

  Future<void> _emptyAll(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.delete_forever_rounded),
        title: Text(tr('trash_empty')),
        content: Text(tr('trash_empty_body')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('cancel'))),
          FilledButton.tonal(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('delete'))),
        ],
      ),
    );
    if (ok == true && context.mounted) await context.read<AppState>().emptyTrash();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    final items = app.store?.trash ?? const [];
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('trash')),
        actions: [
          if (items.isNotEmpty)
            IconButton(
              tooltip: tr('trash_empty'),
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: () => _emptyAll(context),
            ),
        ],
      ),
      body: items.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(40),
                child: Text(
                  tr('trash_none', {'days': EntryStore.trashDays}),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
              itemCount: items.length + 1,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                if (i == 0) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
                    child: Text(
                      tr('trash_hint', {'days': EntryStore.trashDays}),
                      style: TextStyle(color: cs.onSurfaceVariant),
                    ),
                  );
                }
                final (e, deleted) = items[i - 1];
                final (title, preview) = cardTexts(e);
                final left = EntryStore.trashDays - DateTime.now().difference(deleted).inDays;
                return Card(
                  child: Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 8, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          fmtDateTime(e.created),
                          style: TextStyle(color: cs.primary, fontWeight: FontWeight.w600, fontSize: 13),
                        ),
                        if (title.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontFamily: serif),
                          ),
                        ],
                        if (preview.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            preview.replaceAll(RegExp(r'\s*\n\s*'), ' '),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: cs.onSurfaceVariant),
                          ),
                        ],
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                plural('days_left', left.clamp(0, EntryStore.trashDays)),
                                style: TextStyle(color: cs.outline, fontSize: 12),
                              ),
                            ),
                            TextButton(
                              onPressed: () => app.purgeEntry(e.id),
                              child: Text(tr('delete_forever')),
                            ),
                            FilledButton.tonal(
                              onPressed: () async {
                                await app.restoreEntry(e.id);
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('restored'))));
                                }
                              },
                              child: Text(tr('restore')),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/entry.dart';
import '../l10n/strings.dart';
import '../state/app_state.dart';
import 'calendar_view.dart';
import 'editor_screen.dart';
import 'entry_screen.dart';
import 'settings/settings_screen.dart';
import 'tags_view.dart';
import 'theme.dart';
import 'widgets/entry_card.dart';
import 'widgets/entry_tile.dart';
import 'widgets/media.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;
  String? _tag;

  void showTag(String tag) => setState(() {
    _tag = tag;
    _tab = 0;
  });

  @override
  Widget build(BuildContext context) {
    final views = [
      TimelineView(tag: _tag, onClearTag: () => setState(() => _tag = null), onTag: showTag),
      CalendarView(onTag: showTag),
      TagsView(onTag: showTag),
    ];
    return Scaffold(
      body: IndexedStack(index: _tab, children: views),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => openEditor(context, null, tags: _tag == null ? null : [_tag!]),
        icon: const Icon(Icons.edit_rounded),
        label: Text(tr('new_entry')),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.view_agenda_outlined),
            selectedIcon: const Icon(Icons.view_agenda_rounded),
            label: tr('timeline'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.calendar_month_outlined),
            selectedIcon: const Icon(Icons.calendar_month_rounded),
            label: tr('calendar'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.tag_rounded),
            selectedIcon: const Icon(Icons.tag_rounded),
            label: tr('tags'),
          ),
        ],
      ),
    );
  }
}

Future<void> openEditor(BuildContext context, Entry? entry, {DateTime? at, List<String>? tags}) {
  return Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => EditorScreen(entry: entry, at: at, initialTags: tags),
    ),
  );
}

Future<void> openEntry(BuildContext context, Entry entry, {ValueChanged<String>? onTag}) {
  return Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => EntryScreen(entryId: entry.id, onTag: onTag),
    ),
  );
}

/// Actions shared by the top bars of all tabs.
List<Widget> commonActions(BuildContext context) {
  final app = context.watch<AppState>();
  return [
    if (app.git.isConfigured)
      IconButton(
        tooltip: tr('sync_now'),
        onPressed: app.syncStatus == SyncStatus.running ? null : () => runSync(context),
        icon: app.syncStatus == SyncStatus.running
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
            : Icon(app.syncStatus == SyncStatus.error ? Icons.sync_problem_rounded : Icons.sync_rounded),
      ),
    IconButton(
      tooltip: tr('settings'),
      onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
      icon: const Icon(Icons.settings_outlined),
    ),
    IconButton(tooltip: tr('lock_now'), onPressed: () => app.lock(), icon: const Icon(Icons.lock_outline_rounded)),
  ];
}

Future<void> runSync(BuildContext context) async {
  final app = context.read<AppState>();
  final messenger = ScaffoldMessenger.of(context);
  try {
    final r = await app.syncNow();
    if (r == null) return;
    messenger.showSnackBar(SnackBar(content: Text(app.syncMessage)));
    if (r.conflicts > 0) {
      messenger.showSnackBar(SnackBar(content: Text(tr('sync_conflicts', {'n': r.conflicts}))));
    }
  } catch (_) {
    messenger.showSnackBar(SnackBar(content: Text(app.syncMessage)));
  }
}

class TimelineView extends StatefulWidget {
  const TimelineView({super.key, this.tag, required this.onClearTag, required this.onTag});
  final String? tag;
  final VoidCallback onClearTag;
  final ValueChanged<String> onTag;

  @override
  State<TimelineView> createState() => _TimelineViewState();
}

class _TimelineViewState extends State<TimelineView> {
  final _search = TextEditingController();
  bool _searching = false;
  String _query = '';

  // Cache of the grouped list, rebuilt only when data or filters change.
  int _rev = -1;
  String _cacheKey = '';
  List<(DateTime, List<Entry>)> _groups = const [];

  List<(DateTime, List<Entry>)> _grouped(AppState app) {
    final key = '${widget.tag}|$_query';
    if (_rev == app.revision && key == _cacheKey) return _groups;
    final q = _query.trim().toLowerCase();
    final list = app.entries.where((e) {
      if (widget.tag != null && !e.allTags.contains(widget.tag)) return false;
      if (q.isEmpty) return true;
      return e.title.toLowerCase().contains(q) ||
          e.body.toLowerCase().contains(q) ||
          e.allTags.any((t) => t.contains(q.replaceFirst('#', '')));
    });
    final groups = <(DateTime, List<Entry>)>[];
    for (final e in list) {
      final month = DateTime(e.created.year, e.created.month);
      if (groups.isEmpty || groups.last.$1 != month) groups.add((month, []));
      groups.last.$2.add(e);
    }
    _rev = app.revision;
    _cacheKey = key;
    _groups = groups;
    return groups;
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    final groups = _grouped(app);
    final filtering = _query.isNotEmpty || widget.tag != null;
    final memories = filtering ? const <Entry>[] : app.onThisDay();
    final total = app.entries.length;
    final tiles = app.prefs.tiles;

    return CustomScrollView(
      slivers: [
        SliverAppBar.large(
          title: Text(tr('app_name')),
          actions: [
            IconButton(
              tooltip: tiles ? tr('view_list') : tr('view_tiles'),
              icon: Icon(tiles ? Icons.view_agenda_outlined : Icons.grid_view_rounded),
              onPressed: () => app.updatePrefs((p) => p.tiles = !p.tiles),
            ),
            IconButton(
              tooltip: tr('search'),
              icon: Icon(_searching ? Icons.close_rounded : Icons.search_rounded),
              onPressed: () => setState(() {
                _searching = !_searching;
                if (!_searching) {
                  _search.clear();
                  _query = '';
                }
              }),
            ),
            ...commonActions(context),
          ],
        ),
        if (_searching)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: SearchBar(
                controller: _search,
                autoFocus: true,
                hintText: tr('search'),
                elevation: const WidgetStatePropertyAll(0),
                leading: const Icon(Icons.search_rounded),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
          ),
        if (!filtering && total > 0)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                tr('stats', {'entries': plural('entries', total), 'days': app.streak}),
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
            ),
          ),
        if (widget.tag != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  InputChip(
                    avatar: const Icon(Icons.tag_rounded, size: 18),
                    label: Text(widget.tag!),
                    onDeleted: widget.onClearTag,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    plural('entries', groups.fold(0, (n, g) => n + g.$2.length)),
                    style: TextStyle(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
        if (memories.isNotEmpty) SliverToBoxAdapter(child: _OnThisDay(memories, onTag: widget.onTag)),
        if (groups.isEmpty) SliverFillRemaining(hasScrollBody: false, child: _Empty(filtering: filtering)),
        for (final (month, list) in groups)
          SliverMainAxisGroup(
            slivers: [
              PinnedHeaderSliver(
                child: Container(
                  color: cs.surface,
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
                  child: Row(
                    children: [
                      Text(
                        fmtMonthYear(month),
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontFamily: serif, fontWeight: FontWeight.w700, color: cs.onSurface),
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: Divider(color: cs.outlineVariant)),
                      const SizedBox(width: 10),
                      Text('${list.length}', style: TextStyle(color: cs.onSurfaceVariant)),
                    ],
                  ),
                ),
              ),
              if (tiles)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  sliver: SliverGrid.builder(
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 200,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      childAspectRatio: 0.8,
                    ),
                    itemCount: list.length,
                    itemBuilder: (context, i) => EntryTile(
                      entry: list[i],
                      onTap: () => openEntry(context, list[i], onTag: widget.onTag),
                    ),
                  ),
                )
              else
                SliverList.builder(
                  itemCount: list.length,
                  itemBuilder: (context, i) {
                    final e = list[i];
                    final prev = i == 0 ? null : list[i - 1];
                    final sameDay = prev != null && DateUtils.isSameDay(prev.created, e.created);
                    return EntryCard(
                      entry: e,
                      showDate: !sameDay,
                      query: _query,
                      onTap: () => openEntry(context, e, onTag: widget.onTag),
                    );
                  },
                ),
            ],
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 96)),
      ],
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.filtering});
  final bool filtering;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            filtering ? Icons.search_off_rounded : Icons.history_edu_rounded,
            size: 72,
            color: cs.primary.withValues(alpha: 0.6),
          ),
          const SizedBox(height: 16),
          Text(
            filtering ? tr('nothing_found') : tr('empty_title'),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          if (!filtering) ...[
            const SizedBox(height: 8),
            Text(
              tr('empty_body'),
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}

/// Horizontal strip of memories: entries from this day in earlier years.
class _OnThisDay extends StatelessWidget {
  const _OnThisDay(this.entries, {required this.onTag});
  final List<Entry> entries;
  final ValueChanged<String> onTag;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final now = DateTime.now();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
          child: Row(
            children: [
              Icon(Icons.auto_awesome_rounded, size: 18, color: cs.tertiary),
              const SizedBox(width: 8),
              Text(
                tr('on_this_day'),
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontFamily: serif, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 150,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: entries.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, i) {
              final e = entries[i];
              final years = now.year - e.created.year;
              final photo = e.attachments.where((a) => a.type == AttachmentType.photo).firstOrNull;
              return SizedBox(
                width: 230,
                child: Card(
                  color: cs.tertiaryContainer,
                  child: InkWell(
                    onTap: () => openEntry(context, e, onTag: onTag),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (photo != null) ...[
                          EncryptedThumb(photo, radius: 0),
                          const DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [Colors.black12, Colors.black87],
                              ),
                            ),
                          ),
                        ],
                        Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                plural('years_ago', years),
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: photo != null ? Colors.white : cs.onTertiaryContainer,
                                ),
                              ),
                              Text(
                                '${e.created.year}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: (photo != null ? Colors.white : cs.onTertiaryContainer).withValues(alpha: 0.7),
                                ),
                              ),
                              const Spacer(),
                              Text(
                                e.displayTitle.isEmpty ? e.preview : e.displayTitle,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontFamily: serif,
                                  height: 1.3,
                                  color: photo != null ? Colors.white : cs.onTertiaryContainer,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 4),
      ],
    );
  }
}

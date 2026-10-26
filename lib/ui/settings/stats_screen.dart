import 'dart:math';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/entry.dart';
import '../../l10n/strings.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import '../widgets/entry_card.dart';

/// Numbers about the diary: totals, streaks, entries per month and weekday, top tags.
class StatsScreen extends StatelessWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final s = DiaryStats.of(app.entries);
    final cs = Theme.of(context).colorScheme;
    final locale = Lang.code;
    final now = DateTime.now();
    final months = [for (var i = 11; i >= 0; i--) DateTime(now.year, now.month - i)];
    final tags = (app.store?.tagCounts() ?? const <MapEntry<String, int>>[]).take(10).toList();

    return Scaffold(
      appBar: AppBar(title: Text(tr('stats_title'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.9,
            children: [
              _Stat('${s.entries}', tr('stat_entries')),
              _Stat(NumberFormat.decimalPattern(locale).format(s.words), tr('stat_words')),
              _Stat('${s.days}', tr('stat_days')),
              _Stat('${s.streak}', tr('stat_streak')),
              _Stat('${s.longestStreak}', tr('stat_longest')),
              _Stat(s.first == null ? '—' : fmtMonthYear(s.first!), tr('stat_since')),
              if (s.moodAverage != null) _Stat(moodEmoji(s.moodAverage!.round()), tr('stat_mood')),
            ],
          ),
          const SizedBox(height: 24),
          _Title(tr('stat_by_month')),
          _Bars(
            values: [for (final m in months) s.perMonth[DateTime(m.year, m.month)] ?? 0],
            labels: [for (final m in months) DateFormat.MMM(locale).format(m).substring(0, 1).toUpperCase()],
            tips: [for (final m in months) fmtMonthYear(m)],
          ),
          const SizedBox(height: 24),
          _Title(tr('stat_by_weekday')),
          _Bars(
            values: [for (var d = 1; d <= 7; d++) s.perWeekday[d] ?? 0],
            labels: [for (var d = 1; d <= 7; d++) fmtWeekdayShort(DateTime(2024, 1, d))],
            tips: [for (var d = 1; d <= 7; d++) DateFormat.EEEE(locale).format(DateTime(2024, 1, d))],
          ),
          if (tags.isNotEmpty) ...[
            const SizedBox(height: 24),
            _Title(tr('stat_top_tags')),
            for (final t in tags)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    SizedBox(
                      width: 120,
                      child: Text('#${t.key}', maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, c) => Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: Container(
                            height: 10,
                            width: max(4, c.maxWidth * t.value / tags.first.value),
                            decoration: BoxDecoration(color: cs.primary, borderRadius: BorderRadius.circular(4)),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 40,
                      child: Text(
                        '${t.value}',
                        textAlign: TextAlign.end,
                        style: TextStyle(color: cs.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// Plain numbers behind the statistics screen (public for tests).
class DiaryStats {
  DiaryStats._();

  int entries = 0;
  int words = 0;
  int days = 0;
  int streak = 0;
  int longestStreak = 0;
  DateTime? first;
  double? moodAverage;
  final Map<DateTime, int> perMonth = {};
  final Map<int, int> perWeekday = {};

  static DiaryStats of(List<Entry> list, {DateTime? today}) {
    final s = DiaryStats._()..entries = list.length;
    final dayset = <DateTime>{};
    var moodSum = 0, moodN = 0;
    for (final e in list) {
      s.words += e.wordCount;
      final d = DateTime(e.created.year, e.created.month, e.created.day);
      dayset.add(d);
      final m = DateTime(e.created.year, e.created.month);
      s.perMonth[m] = (s.perMonth[m] ?? 0) + 1;
      s.perWeekday[e.created.weekday] = (s.perWeekday[e.created.weekday] ?? 0) + 1;
      if (s.first == null || e.created.isBefore(s.first!)) s.first = e.created;
      if (e.mood != null) {
        moodSum += e.mood!;
        moodN++;
      }
    }
    s.days = dayset.length;
    if (moodN > 0) s.moodAverage = moodSum / moodN;

    final sorted = dayset.toList()..sort();
    var run = 0;
    DateTime? prev;
    for (final d in sorted) {
      run = prev != null && DateTime(prev.year, prev.month, prev.day + 1) == d ? run + 1 : 1;
      s.longestStreak = max(s.longestStreak, run);
      prev = d;
    }
    final t = today ?? DateTime.now();
    var day = DateTime(t.year, t.month, t.day);
    if (!dayset.contains(day)) day = DateTime(day.year, day.month, day.day - 1);
    while (dayset.contains(day)) {
      s.streak++;
      day = DateTime(day.year, day.month, day.day - 1);
    }
    return s;
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.value, this.label);
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                value,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontFamily: serif, color: cs.onSurface),
              ),
            ),
            const SizedBox(height: 2),
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: cs.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

class _Title extends StatelessWidget {
  const _Title(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(text, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontFamily: serif)),
  );
}

/// One-series column chart: thin rounded bars on a baseline, the maximum labelled, every bar
/// shows its value on tap (tooltip).
class _Bars extends StatelessWidget {
  const _Bars({required this.values, required this.labels, required this.tips});
  final List<int> values;
  final List<String> labels;
  final List<String> tips;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final top = values.fold(0, max);
    final peak = values.indexOf(top);
    const height = 120.0;
    return Column(
      children: [
        SizedBox(
          height: height + 18,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < values.length; i++)
                Expanded(
                  child: Tooltip(
                    message: '${tips[i]}: ${values[i]}',
                    triggerMode: TooltipTriggerMode.tap,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 1),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (i == peak && top > 0)
                            Text('$top', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
                          const SizedBox(height: 2),
                          Container(
                            height: top == 0 ? 0 : max(values[i] == 0 ? 0 : 3, height * values[i] / top),
                            constraints: const BoxConstraints(maxWidth: 22),
                            decoration: BoxDecoration(
                              color: cs.primary,
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Container(height: 1, color: cs.outlineVariant),
        const SizedBox(height: 4),
        Row(
          children: [
            for (final l in labels)
              Expanded(
                child: Text(
                  l,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

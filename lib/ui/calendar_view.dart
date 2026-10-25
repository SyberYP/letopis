import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../core/entry.dart';
import '../l10n/strings.dart';
import '../state/app_state.dart';
import 'home_screen.dart';
import 'theme.dart';
import 'widgets/entry_card.dart';

/// Month grid with dots on days that have entries; the selected day's entries below.
class CalendarView extends StatefulWidget {
  const CalendarView({super.key, required this.onTag});
  final ValueChanged<String> onTag;

  @override
  State<CalendarView> createState() => _CalendarViewState();
}

class _CalendarViewState extends State<CalendarView> {
  late DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  late DateTime _day = DateUtils.dateOnly(DateTime.now());

  void _shift(int months) => setState(() => _month = DateTime(_month.year, _month.month + months));

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    final byDay = <DateTime, List<Entry>>{};
    for (final e in app.entries) {
      byDay.putIfAbsent(DateUtils.dateOnly(e.created), () => []).add(e);
    }
    final dayEntries = (byDay[_day] ?? const <Entry>[]).reversed.toList();
    final first = DateTime(_month.year, _month.month);
    final leading = (first.weekday - DateTime.monday) % 7;
    final days = DateUtils.getDaysInMonth(_month.year, _month.month);
    final today = DateUtils.dateOnly(DateTime.now());
    final locale = Lang.code == 'ru' ? 'ru' : 'en';
    final weekdays = [for (var i = 0; i < 7; i++) DateFormat.E(locale).format(DateTime(2024, 1, 1 + i))];

    return CustomScrollView(
      slivers: [
        SliverAppBar(pinned: true, title: Text(tr('calendar')), actions: commonActions(context)),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Column(
              children: [
                Row(
                  children: [
                    IconButton(onPressed: () => _shift(-1), icon: const Icon(Icons.chevron_left_rounded)),
                    Expanded(
                      child: GestureDetector(
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _day,
                            firstDate: DateTime(1900),
                            lastDate: DateTime(2100),
                            initialDatePickerMode: DatePickerMode.year,
                          );
                          if (picked != null) {
                            setState(() {
                              _day = picked;
                              _month = DateTime(picked.year, picked.month);
                            });
                          }
                        },
                        child: Text(
                          fmtMonthYear(_month),
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontFamily: serif),
                        ),
                      ),
                    ),
                    IconButton(onPressed: () => _shift(1), icon: const Icon(Icons.chevron_right_rounded)),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    for (final w in weekdays)
                      Expanded(
                        child: Text(
                          w.toUpperCase(),
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                GestureDetector(
                  onHorizontalDragEnd: (d) {
                    final v = d.primaryVelocity ?? 0;
                    if (v.abs() > 200) _shift(v < 0 ? 1 : -1);
                  },
                  child: GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 7,
                      childAspectRatio: 0.95,
                    ),
                    itemCount: leading + days,
                    itemBuilder: (context, i) {
                      if (i < leading) return const SizedBox();
                      final day = DateTime(_month.year, _month.month, i - leading + 1);
                      final count = byDay[day]?.length ?? 0;
                      final selected = day == _day;
                      final isToday = day == today;
                      return Padding(
                        padding: const EdgeInsets.all(3),
                        child: Material(
                          color: selected
                              ? cs.primary
                              : count > 0
                              ? cs.primaryContainer.withValues(alpha: 0.55)
                              : Colors.transparent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                            side: isToday && !selected ? BorderSide(color: cs.primary, width: 1.5) : BorderSide.none,
                          ),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () => setState(() => _day = day),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  '${day.day}',
                                  style: TextStyle(
                                    fontWeight: count > 0 ? FontWeight.w700 : FontWeight.w400,
                                    color: selected ? cs.onPrimary : cs.onSurface,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    for (var k = 0; k < count.clamp(0, 3); k++)
                                      Container(
                                        width: 5,
                                        height: 5,
                                        margin: const EdgeInsets.symmetric(horizontal: 1),
                                        decoration: BoxDecoration(
                                          color: selected ? cs.onPrimary : cs.primary,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          fmtFullDate(_day),
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () {
                          final now = DateTime.now();
                          openEditor(
                            context,
                            null,
                            at: DateUtils.isSameDay(_day, now)
                                ? now
                                : DateTime(_day.year, _day.month, _day.day, now.hour, now.minute),
                          );
                        },
                        icon: const Icon(Icons.add_rounded),
                        label: Text(tr('write_this_day')),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (dayEntries.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                tr('no_entries_day'),
                textAlign: TextAlign.center,
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
            ),
          )
        else
          SliverList.builder(
            itemCount: dayEntries.length,
            itemBuilder: (context, i) => EntryCard(
              entry: dayEntries[i],
              showDate: i == 0,
              onTap: () => openEntry(context, dayEntries[i], onTag: widget.onTag),
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 96)),
      ],
    );
  }
}

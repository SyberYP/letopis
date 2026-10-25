import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/entry.dart';
import '../../l10n/strings.dart';
import '../theme.dart';
import 'media.dart';

String _locale() => Lang.code == 'ru' ? 'ru' : 'en';

String fmtTime(DateTime t) => DateFormat.Hm(_locale()).format(t);
String fmtWeekdayShort(DateTime t) => DateFormat.E(_locale()).format(t);

/// Russian formats end with "г."; it only adds noise next to a four-digit year.
String _noYearMark(String s) => s.replaceAll(RegExp(r'\s?г\.'), '');

String fmtMonthYear(DateTime t) {
  final s = _noYearMark(DateFormat.yMMMM(_locale()).format(t));
  return s[0].toUpperCase() + s.substring(1);
}

String fmtFullDate(DateTime t) {
  final s = _noYearMark(DateFormat.yMMMMEEEEd(_locale()).format(t));
  return s[0].toUpperCase() + s.substring(1);
}

String fmtDateTime(DateTime t) => '${_noYearMark(DateFormat.yMMMd(_locale()).format(t))}, ${fmtTime(t)}';

class TagChip extends StatelessWidget {
  const TagChip(this.tag, {super.key, this.onTap, this.onDeleted, this.small = false});
  final String tag;
  final VoidCallback? onTap;
  final VoidCallback? onDeleted;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (small) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: cs.secondaryContainer.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text('#$tag', style: TextStyle(fontSize: 12, color: cs.onSecondaryContainer)),
      );
    }
    return InputChip(
      label: Text('#$tag'),
      onPressed: onTap,
      onDeleted: onDeleted,
      deleteIcon: const Icon(Icons.close_rounded, size: 16),
      visualDensity: VisualDensity.compact,
    );
  }
}

/// One entry in the timeline: big day number on the left, the card on the right.
class EntryCard extends StatelessWidget {
  const EntryCard({super.key, required this.entry, required this.onTap, this.showDate = true, this.query});
  final Entry entry;
  final VoidCallback onTap;

  /// False for the second and later entries of the same day.
  final bool showDate;
  final String? query;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    var preview = entry.preview.trim();
    final rawTitle = entry.displayTitle;
    if (entry.title.trim().isEmpty && preview.startsWith(rawTitle)) {
      preview = preview.substring(rawTitle.length).trim();
    }
    // Hashtags are shown as chips below, so they are dropped from the title and preview.
    String noTags(String s) => s.replaceAll(_hashtagInText, '').replaceAll(RegExp(r'[ \t]{2,}'), ' ').trim();
    final title = noTags(rawTitle);
    preview = noTags(preview);
    final photos = entry.attachments.where((a) => a.type == AttachmentType.photo).toList();
    final others = entry.attachments.where((a) => a.type != AttachmentType.photo).toList();
    final tags = entry.allTags;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 16, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 52,
            child: showDate
                ? Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Column(
                      children: [
                        Text(
                          '${entry.created.day}',
                          style: text.headlineMedium?.copyWith(fontFamily: serif, color: cs.primary, height: 1),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          fmtWeekdayShort(entry.created).toUpperCase(),
                          style: text.labelSmall?.copyWith(color: cs.onSurfaceVariant, letterSpacing: 1),
                        ),
                      ],
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Card(
              child: InkWell(
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            fmtTime(entry.created),
                            style: text.labelMedium?.copyWith(color: cs.primary, fontWeight: FontWeight.w600),
                          ),
                          const Spacer(),
                          for (final a in others.take(4))
                            Padding(
                              padding: const EdgeInsets.only(left: 6),
                              child: Icon(iconFor(a.type), size: 16, color: cs.onSurfaceVariant),
                            ),
                          if (entry.mood != null)
                            Padding(
                              padding: const EdgeInsets.only(left: 6),
                              child: Text(moodEmoji(entry.mood!), style: const TextStyle(fontSize: 14)),
                            ),
                        ],
                      ),
                      if (title.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        _Highlighted(
                          title,
                          query,
                          maxLines: 2,
                          style: text.titleMedium?.copyWith(
                            fontFamily: serif,
                            fontWeight: FontWeight.w600,
                            height: 1.25,
                          ),
                        ),
                      ],
                      if (preview.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        _Highlighted(
                          preview.replaceAll(RegExp(r'\s*\n\s*'), ' '),
                          query,
                          maxLines: photos.isEmpty ? 4 : 2,
                          style: text.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ],
                      if (photos.isNotEmpty) ...[const SizedBox(height: 10), _PhotoStrip(photos)],
                      if (tags.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [for (final t in tags.take(6)) TagChip(t, small: true)],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

final _hashtagInText = RegExp(r'(?<![\p{L}\p{N}_&/#])#[\p{L}\p{N}_][\p{L}\p{N}_\-]*', unicode: true);

String moodEmoji(int mood) => const ['😞', '😕', '😐', '🙂', '😄'][(mood - 1).clamp(0, 4)];

class _PhotoStrip extends StatelessWidget {
  const _PhotoStrip(this.photos);
  final List<Attachment> photos;

  @override
  Widget build(BuildContext context) {
    if (photos.length == 1) {
      return AspectRatio(aspectRatio: 16 / 9, child: EncryptedThumb(photos.first));
    }
    final shown = photos.take(3).toList();
    return SizedBox(
      height: 96,
      child: Row(
        children: [
          for (var i = 0; i < shown.length; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  EncryptedThumb(shown[i], radius: 12),
                  if (i == 2 && photos.length > 3)
                    Container(
                      decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(12)),
                      alignment: Alignment.center,
                      child: Text(
                        '+${photos.length - 3}',
                        style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
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

/// Text with the search query highlighted.
class _Highlighted extends StatelessWidget {
  const _Highlighted(this.text, this.query, {required this.maxLines, this.style});
  final String text;
  final String? query;
  final int maxLines;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final q = query?.trim().toLowerCase() ?? '';
    if (q.isEmpty) return Text(text, maxLines: maxLines, overflow: TextOverflow.ellipsis, style: style);
    final cs = Theme.of(context).colorScheme;
    final lower = text.toLowerCase();
    var start = lower.indexOf(q);
    // Show the first match even deep in a long entry.
    var shown = text;
    if (start > 60) {
      shown = '…${text.substring(start - 30)}';
      start = 31;
    }
    final spans = <TextSpan>[];
    final lowerShown = shown.toLowerCase();
    var i = 0;
    while (true) {
      final j = lowerShown.indexOf(q, i);
      if (j < 0) break;
      spans
        ..add(TextSpan(text: shown.substring(i, j)))
        ..add(
          TextSpan(
            text: shown.substring(j, j + q.length),
            style: TextStyle(backgroundColor: cs.tertiaryContainer, color: cs.onTertiaryContainer),
          ),
        );
      i = j + q.length;
    }
    spans.add(TextSpan(text: shown.substring(i)));
    return Text.rich(
      TextSpan(children: spans),
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      style: style,
    );
  }
}

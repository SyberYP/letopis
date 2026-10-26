import 'package:flutter/material.dart';

import '../../core/entry.dart';
import '../theme.dart';
import 'entry_card.dart';
import 'media.dart';

/// One entry as a square-ish tile in the grid view: a photo entry shows its first photo with
/// the date and title on top, a text entry shows the date, title and the start of the text.
class EntryTile extends StatelessWidget {
  const EntryTile({super.key, required this.entry, required this.onTap});
  final Entry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final photo = entry.attachments.where((a) => a.type == AttachmentType.photo).firstOrNull;
    return Card(
      child: InkWell(
        onTap: onTap,
        child: photo == null ? _TextTile(entry) : _PhotoTile(entry, photo),
      ),
    );
  }
}

/// Icons for voice, video, files and the mood, in one row.
class _Badges extends StatelessWidget {
  const _Badges(this.entry, {required this.color});
  final Entry entry;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final types = <AttachmentType>{
      for (final a in entry.attachments)
        if (a.type != AttachmentType.photo) a.type,
    };
    final photos = entry.attachments.where((a) => a.type == AttachmentType.photo).length;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (photos > 1) ...[
          Icon(Icons.photo_library_rounded, size: 14, color: color),
          const SizedBox(width: 2),
          Text('$photos', style: TextStyle(fontSize: 12, color: color)),
          const SizedBox(width: 6),
        ],
        for (final t in types) ...[Icon(iconFor(t), size: 14, color: color), const SizedBox(width: 6)],
        if (entry.mood != null) Text(moodEmoji(entry.mood!), style: const TextStyle(fontSize: 13)),
      ],
    );
  }
}

class _TextTile extends StatelessWidget {
  const _TextTile(this.entry);
  final Entry entry;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final (title, preview) = cardTexts(entry);
    final tag = entry.allTags.firstOrNull;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _DateLine(entry, color: cs.primary, muted: cs.onSurfaceVariant),
          const SizedBox(height: 8),
          if (title.isNotEmpty)
            Text(
              title,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: text.titleSmall?.copyWith(fontFamily: serif, fontWeight: FontWeight.w700, height: 1.25),
            ),
          if (preview.isNotEmpty) ...[
            const SizedBox(height: 4),
            Expanded(
              child: Text(
                preview.replaceAll(RegExp(r'\s*\n\s*'), ' '),
                overflow: TextOverflow.fade,
                style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant, height: 1.4),
              ),
            ),
          ] else
            const Spacer(),
          const SizedBox(height: 8),
          Row(
            children: [
              if (tag != null)
                Flexible(
                  child: Text(
                    '#$tag',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.labelSmall?.copyWith(color: cs.secondary),
                  ),
                )
              else
                const Spacer(),
              const SizedBox(width: 6),
              _Badges(entry, color: cs.onSurfaceVariant),
            ],
          ),
        ],
      ),
    );
  }
}

class _PhotoTile extends StatelessWidget {
  const _PhotoTile(this.entry, this.photo);
  final Entry entry;
  final Attachment photo;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final (title, preview) = cardTexts(entry);
    final caption = title.isNotEmpty ? title : preview;
    const shadow = [Shadow(blurRadius: 6, color: Colors.black54)];
    return Stack(
      fit: StackFit.expand,
      children: [
        EncryptedThumb(photo, radius: 0),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: [0, 0.35, 0.6, 1],
              colors: [Colors.black38, Colors.transparent, Colors.transparent, Colors.black87],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DateLine(entry, color: Colors.white, muted: Colors.white70, shadows: shadow),
              const Spacer(),
              if (caption.isNotEmpty)
                Text(
                  caption,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: text.titleSmall?.copyWith(
                    fontFamily: serif,
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                    color: Colors.white,
                    shadows: shadow,
                  ),
                ),
              const SizedBox(height: 6),
              _Badges(entry, color: Colors.white),
            ],
          ),
        ),
      ],
    );
  }
}

/// "25 · Sun 09:41": the day big, weekday and time small.
class _DateLine extends StatelessWidget {
  const _DateLine(this.entry, {required this.color, required this.muted, this.shadows});
  final Entry entry;
  final Color color;
  final Color muted;
  final List<Shadow>? shadows;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          '${entry.created.day}',
          style: text.headlineSmall?.copyWith(fontFamily: serif, color: color, height: 1, shadows: shadows),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            '${fmtWeekdayShort(entry.created)} ${fmtTime(entry.created)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: text.labelSmall?.copyWith(color: muted, letterSpacing: 0.5, shadows: shadows),
          ),
        ),
      ],
    );
  }
}

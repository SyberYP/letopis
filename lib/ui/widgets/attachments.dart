import 'package:flutter/material.dart';

import '../../core/entry.dart';
import 'media.dart';

/// Attachments of an entry: photo/video grid, then audio players, then other files.
class AttachmentGallery extends StatelessWidget {
  const AttachmentGallery({super.key, required this.entry, required this.attachments, this.onDelete});
  final Entry entry;
  final List<Attachment> attachments;
  final ValueChanged<Attachment>? onDelete;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final visual = attachments.where((a) => a.type == AttachmentType.photo || a.type == AttachmentType.video).toList();
    final audio = attachments.where((a) => a.type == AttachmentType.audio).toList();
    final files = attachments.where((a) => a.type == AttachmentType.file).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (visual.isNotEmpty)
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: visual.length == 1 ? 1 : (visual.length == 2 || visual.length == 4 ? 2 : 3),
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
              childAspectRatio: visual.length == 1 ? 4 / 3 : 1,
            ),
            itemCount: visual.length,
            itemBuilder: (context, i) {
              final a = visual[i];
              return GestureDetector(
                onTap: () => openAttachment(context, a, entry.attachments),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (a.type == AttachmentType.photo)
                      EncryptedThumb(a)
                    else
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          gradient: LinearGradient(colors: [cs.primaryContainer, cs.tertiaryContainer]),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.play_circle_fill_rounded, size: 44, color: cs.onPrimaryContainer),
                            const SizedBox(height: 6),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              child: Text(
                                a.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 12, color: cs.onPrimaryContainer),
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (onDelete != null)
                      PositionedDirectional(
                        top: 4,
                        end: 4,
                        child: IconButton.filledTonal(
                          visualDensity: VisualDensity.compact,
                          onPressed: () => onDelete!(a),
                          icon: const Icon(Icons.close_rounded, size: 18),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        for (final a in audio) ...[
          const SizedBox(height: 8),
          AudioTile(a, key: ValueKey(a.id), onDelete: onDelete == null ? null : () => onDelete!(a)),
        ],
        for (final a in files) ...[
          const SizedBox(height: 8),
          ListTile(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            tileColor: cs.surfaceContainerHigh,
            leading: Icon(iconFor(a.type)),
            title: Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(_size(a.size)),
            onTap: () => shareAttachment(context, a),
            trailing: onDelete == null
                ? const Icon(Icons.ios_share_rounded)
                : IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => onDelete!(a)),
          ),
        ],
      ],
    );
  }

  static String _size(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
}

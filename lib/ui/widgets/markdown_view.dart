import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

import '../../core/entry.dart';
import '../theme.dart';
import 'media.dart';

final _codeOrTag = RegExp(
  r'```[\s\S]*?(```|$)|`[^`\n]*`|\]\([^)]*\)|(?<![\p{L}\p{N}_&/#\[])#([\p{L}\p{N}_][\p{L}\p{N}_\-]*)',
  unicode: true,
);

/// Turns `#tag` into a `tag:` link so it can be tapped; leaves code and link targets alone.
String linkHashtags(String body) => body.replaceAllMapped(_codeOrTag, (m) {
  final tag = m.group(2);
  if (tag == null || RegExp(r'^\d+$').hasMatch(tag)) return m.group(0)!;
  return '[#$tag](tag:${Uri.encodeComponent(tag.toLowerCase())})';
});

/// Renders an entry body: `att:` images come from the encrypted store, `att:` links open the
/// attachment, `#tags` are tappable.
class EntryMarkdown extends StatelessWidget {
  const EntryMarkdown({super.key, required this.entry, this.onTag, this.selectable = true});

  final Entry entry;
  final ValueChanged<String>? onTag;
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final atts = {for (final a in entry.attachments) a.id: a};
    final style = MarkdownStyleSheet.fromTheme(theme).copyWith(
      p: theme.textTheme.bodyLarge,
      h1: theme.textTheme.headlineSmall?.copyWith(fontFamily: serif),
      h2: theme.textTheme.titleLarge?.copyWith(fontFamily: serif),
      h3: theme.textTheme.titleMedium?.copyWith(fontFamily: serif, fontWeight: FontWeight.w700),
      a: TextStyle(color: cs.primary, fontWeight: FontWeight.w600, decoration: TextDecoration.none),
      blockquote: theme.textTheme.bodyLarge?.copyWith(color: cs.onSurfaceVariant, fontStyle: FontStyle.italic),
      blockquoteDecoration: BoxDecoration(
        border: Border(left: BorderSide(color: cs.primary, width: 3)),
        color: cs.primaryContainer.withValues(alpha: 0.25),
      ),
      blockquotePadding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      code: TextStyle(fontFamily: 'monospace', backgroundColor: cs.surfaceContainerHighest, fontSize: 14),
      codeblockDecoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)),
      horizontalRuleDecoration: BoxDecoration(
        border: Border(top: BorderSide(color: cs.outlineVariant)),
      ),
      blockSpacing: 12,
    );
    return MarkdownBody(
      data: linkHashtags(entry.body),
      selectable: selectable,
      styleSheet: style,
      extensionSet: md.ExtensionSet.gitHubFlavored,
      imageBuilder: (uri, title, alt) {
        final a = uri.scheme == 'att' ? atts[uri.path] : null;
        if (a == null) {
          return Icon(Icons.image_not_supported_rounded, color: cs.onSurfaceVariant);
        }
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: GestureDetector(
            onTap: () => openAttachment(context, a, entry.attachments),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 420),
                child: EncryptedImage(a, fit: BoxFit.cover),
              ),
            ),
          ),
        );
      },
      onTapLink: (text, href, title) {
        if (href == null) return;
        if (href.startsWith('tag:')) {
          onTag?.call(Uri.decodeComponent(href.substring(4)));
        } else if (href.startsWith('att:')) {
          final a = atts[href.substring(4)];
          if (a != null) openAttachment(context, a, entry.attachments);
        }
      },
    );
  }
}

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import '../../core/entry.dart';
import '../../l10n/strings.dart';
import '../../state/app_state.dart';

/// Decrypted thumbnail of a photo attachment; a soft placeholder while loading.
class EncryptedThumb extends StatelessWidget {
  const EncryptedThumb(this.attachment, {super.key, this.size, this.radius = 14, this.fit = BoxFit.cover});
  final Attachment attachment;
  final double? size;
  final double radius;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final store = context.read<AppState>().store;
    final cs = Theme.of(context).colorScheme;
    Widget placeholder(IconData icon) => Container(
      width: size,
      height: size,
      color: cs.surfaceContainerHighest,
      child: Icon(icon, color: cs.onSurfaceVariant),
    );
    final Widget child;
    if (attachment.type != AttachmentType.photo || store == null) {
      child = placeholder(iconFor(attachment.type));
    } else {
      child = FutureBuilder<Uint8List?>(
        initialData: store.cachedThumbnail(attachment.id),
        future: store.thumbnail(attachment.id),
        builder: (context, snap) {
          final bytes = snap.data;
          if (bytes == null) return placeholder(Icons.image_rounded);
          return Image.memory(bytes, width: size, height: size, fit: fit, gaplessPlayback: true);
        },
      );
    }
    return ClipRRect(borderRadius: BorderRadius.circular(radius), child: child);
  }
}

IconData iconFor(AttachmentType t) => switch (t) {
  AttachmentType.photo => Icons.image_rounded,
  AttachmentType.video => Icons.movie_rounded,
  AttachmentType.audio => Icons.graphic_eq_rounded,
  AttachmentType.file => Icons.insert_drive_file_rounded,
};

String formatDuration(Duration d) {
  final m = d.inMinutes, s = d.inSeconds % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}

/// Full-size photo from the encrypted store.
class EncryptedImage extends StatefulWidget {
  const EncryptedImage(this.attachment, {super.key, this.fit = BoxFit.contain});
  final Attachment attachment;
  final BoxFit fit;

  @override
  State<EncryptedImage> createState() => _EncryptedImageState();
}

class _EncryptedImageState extends State<EncryptedImage> {
  late final Future<Uint8List> _bytes = context.read<AppState>().store!.mediaBytes(widget.attachment.id);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List>(
      future: _bytes,
      builder: (context, snap) {
        if (snap.hasError) return const Center(child: Icon(Icons.broken_image_rounded));
        if (!snap.hasData) return EncryptedThumb(widget.attachment, radius: 0, fit: widget.fit);
        return Image.memory(snap.data!, fit: widget.fit, gaplessPlayback: true);
      },
    );
  }
}

/// Swipeable full-screen gallery with zoom.
class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key, required this.photos, this.initial = 0});
  final List<Attachment> photos;
  final int initial;

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  late final _page = PageController(initialPage: widget.initial);
  late int _index = widget.initial;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('${_index + 1} / ${widget.photos.length}', style: const TextStyle(color: Colors.white)),
        actions: [
          IconButton(
            tooltip: tr('share'),
            icon: const Icon(Icons.ios_share_rounded),
            onPressed: () => shareAttachment(context, widget.photos[_index]),
          ),
        ],
      ),
      body: PageView.builder(
        controller: _page,
        itemCount: widget.photos.length,
        onPageChanged: (i) => setState(() => _index = i),
        itemBuilder: (_, i) => InteractiveViewer(maxScale: 5, child: Center(child: EncryptedImage(widget.photos[i]))),
      ),
    );
  }
}

/// Inline audio player for a voice note or audio file.
class AudioTile extends StatefulWidget {
  const AudioTile(this.attachment, {super.key, this.onDelete});
  final Attachment attachment;
  final VoidCallback? onDelete;

  @override
  State<AudioTile> createState() => _AudioTileState();
}

class _AudioTileState extends State<AudioTile> {
  AudioPlayer? _player;
  bool _loading = false;
  Duration _pos = Duration.zero;
  Duration? _dur;
  final _subs = <StreamSubscription>[];

  @override
  void initState() {
    super.initState();
    final ms = widget.attachment.durationMs;
    if (ms != null) _dur = Duration(milliseconds: ms);
  }

  Future<void> _toggle() async {
    final p = _player;
    if (p != null) {
      p.playing ? await p.pause() : await p.play();
      return;
    }
    setState(() => _loading = true);
    try {
      final file = await context.read<AppState>().store!.openMedia(widget.attachment);
      final player = AudioPlayer();
      _subs
        ..add(player.positionStream.listen((d) => mounted ? setState(() => _pos = d) : null))
        ..add(player.durationStream.listen((d) => mounted && d != null ? setState(() => _dur = d) : null))
        ..add(
          player.playerStateStream.listen((s) {
            if (s.processingState == ProcessingState.completed) {
              player.pause();
              player.seek(Duration.zero);
            }
            if (mounted) setState(() {});
          }),
        );
      await player.setFilePath(file.path);
      _player = player;
      setState(() => _loading = false);
      await player.play();
    } catch (_) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('open_file_error'))));
      }
    }
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final playing = _player?.playing ?? false;
    final total = _dur ?? Duration.zero;
    final progress = total.inMilliseconds == 0 ? 0.0 : (_pos.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(6, 6, 12, 6),
      decoration: BoxDecoration(color: cs.tertiaryContainer, borderRadius: BorderRadius.circular(18)),
      child: Row(
        children: [
          IconButton.filled(
            style: IconButton.styleFrom(backgroundColor: cs.tertiary, foregroundColor: cs.onTertiary),
            onPressed: _loading ? null : _toggle,
            icon: _loading
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: cs.onTertiary),
                  )
                : Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.attachment.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: cs.onTertiaryContainer, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 5,
                    backgroundColor: cs.onTertiaryContainer.withValues(alpha: 0.15),
                    color: cs.tertiary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            _player == null ? formatDuration(total) : '${formatDuration(_pos)} / ${formatDuration(total)}',
            style: TextStyle(color: cs.onTertiaryContainer, fontFeatures: const [FontFeature.tabularFigures()]),
          ),
          if (widget.onDelete != null)
            IconButton(
              icon: Icon(Icons.close_rounded, color: cs.onTertiaryContainer),
              onPressed: widget.onDelete,
            ),
        ],
      ),
    );
  }
}

/// Full-screen video player.
class VideoScreen extends StatefulWidget {
  const VideoScreen(this.attachment, {super.key});
  final Attachment attachment;

  @override
  State<VideoScreen> createState() => _VideoScreenState();
}

class _VideoScreenState extends State<VideoScreen> {
  VideoPlayerController? _c;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final File f = await context.read<AppState>().store!.openMedia(widget.attachment);
      final c = VideoPlayerController.file(f);
      await c.initialize();
      c.addListener(() => mounted ? setState(() {}) : null);
      await c.play();
      if (mounted) setState(() => _c = c);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: tr('share'),
            icon: const Icon(Icons.ios_share_rounded),
            onPressed: () => shareAttachment(context, widget.attachment),
          ),
        ],
      ),
      body: Center(
        child: _error != null
            ? Text(tr('open_file_error'), style: const TextStyle(color: Colors.white))
            : c == null
            ? const CircularProgressIndicator()
            : GestureDetector(
                onTap: () => c.value.isPlaying ? c.pause() : c.play(),
                child: AspectRatio(
                  aspectRatio: c.value.aspectRatio,
                  child: Stack(
                    alignment: Alignment.bottomCenter,
                    children: [
                      VideoPlayer(c),
                      if (!c.value.isPlaying)
                        const Center(child: Icon(Icons.play_circle_fill_rounded, size: 72, color: Colors.white70)),
                      VideoProgressIndicator(c, allowScrubbing: true, padding: const EdgeInsets.all(12)),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}

/// Decrypts an attachment into the temp folder (wiped on lock) and hands it to the system share
/// sheet: save to files, send, or open in another app.
Future<void> shareAttachment(BuildContext context, Attachment a) async {
  final app = context.read<AppState>();
  final messenger = ScaffoldMessenger.of(context);
  try {
    final file = await app.store!.openMedia(a);
    await app.keepUnlocked(
      () => SharePlus.instance.share(ShareParams(files: [XFile(file.path, mimeType: a.mime, name: a.name)])),
    );
  } catch (_) {
    messenger.showSnackBar(SnackBar(content: Text(tr('open_file_error'))));
  }
}

/// Opens an attachment in the right viewer.
void openAttachment(BuildContext context, Attachment a, List<Attachment> all) {
  final nav = Navigator.of(context);
  switch (a.type) {
    case AttachmentType.photo:
      final photos = all.where((x) => x.type == AttachmentType.photo).toList();
      nav.push(
        MaterialPageRoute(
          builder: (_) => GalleryScreen(photos: photos, initial: photos.indexOf(a)),
        ),
      );
    case AttachmentType.video:
      nav.push(MaterialPageRoute(builder: (_) => VideoScreen(a)));
    case AttachmentType.audio:
      break; // plays inline
    case AttachmentType.file:
      shareAttachment(context, a);
  }
}

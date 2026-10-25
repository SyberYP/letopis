import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:record/record.dart';

import '../../core/entry.dart';
import '../../l10n/strings.dart';
import 'media.dart';

class RecordingResult {
  RecordingResult(this.file, this.name, this.duration);
  final File file;
  final String name;
  final Duration duration;
}

/// Bottom sheet that records a voice note into the temp folder (wiped on lock); the editor
/// encrypts it right away.
class RecorderSheet extends StatefulWidget {
  const RecorderSheet({super.key, required this.tempDir});
  final Directory tempDir;

  @override
  State<RecorderSheet> createState() => _RecorderSheetState();
}

class _RecorderSheetState extends State<RecorderSheet> {
  final _rec = AudioRecorder();
  final _levels = <double>[];
  StreamSubscription<Amplitude>? _amp;
  Timer? _tick;
  final _watch = Stopwatch();
  String? _path;
  bool _paused = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      if (!await _rec.hasPermission()) {
        setState(() => _error = tr('mic_denied'));
        return;
      }
      await widget.tempDir.create(recursive: true);
      _path = '${widget.tempDir.path}/${newId()}.m4a';
      await _rec.start(
        const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 96000, sampleRate: 44100),
        path: _path!,
      );
      _watch.start();
      _tick = Timer.periodic(const Duration(milliseconds: 200), (_) => mounted ? setState(() {}) : null);
      _amp = _rec.onAmplitudeChanged(const Duration(milliseconds: 120)).listen((a) {
        // dBFS (-60..0) → 0..1
        final v = ((a.current + 60) / 60).clamp(0.05, 1.0);
        _levels.add(v);
        if (_levels.length > 48) _levels.removeAt(0);
      });
    } catch (e) {
      setState(() => _error = '$e');
    }
  }

  Future<void> _togglePause() async {
    if (_paused) {
      await _rec.resume();
      _watch.start();
    } else {
      await _rec.pause();
      _watch.stop();
    }
    setState(() => _paused = !_paused);
  }

  Future<void> _stop({required bool keep}) async {
    _tick?.cancel();
    await _amp?.cancel();
    _watch.stop();
    final path = await _rec.stop();
    if (!mounted) return;
    if (!keep || path == null) {
      if (path != null && File(path).existsSync()) File(path).deleteSync();
      Navigator.pop(context);
      return;
    }
    final now = DateTime.now();
    final name =
        'voice-${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}'
        '-${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}.m4a';
    Navigator.pop(context, RecordingResult(File(path), name, _watch.elapsed));
  }

  @override
  void dispose() {
    _tick?.cancel();
    _amp?.cancel();
    _rec.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error ?? tr('recording'), style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 20),
            SizedBox(
              height: 56,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  for (var i = 0; i < 48; i++)
                    Expanded(
                      child: Center(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 120),
                          width: 3,
                          height: 56 * (i < 48 - _levels.length ? 0.05 : _levels[i - (48 - _levels.length)]),
                          decoration: BoxDecoration(color: cs.primary, borderRadius: BorderRadius.circular(2)),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              formatDuration(_watch.elapsed),
              style: Theme.of(context).textTheme.headlineMedium
                  ?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                TextButton(onPressed: () => _stop(keep: false), child: Text(tr('cancel'))),
                if (_error == null)
                  IconButton.filledTonal(
                    iconSize: 32,
                    onPressed: _togglePause,
                    icon: Icon(_paused ? Icons.mic_rounded : Icons.pause_rounded),
                  ),
                if (_error == null)
                  FilledButton.icon(
                    onPressed: () => _stop(keep: true),
                    icon: const Icon(Icons.stop_rounded),
                    label: Text(tr('save')),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

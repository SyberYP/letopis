import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../core/entry.dart';
import '../l10n/strings.dart';
import '../services/ai_tagger.dart';
import '../state/app_state.dart';
import 'entry_screen.dart';
import 'settings/ai_settings_screen.dart';
import 'theme.dart';
import 'widgets/attachments.dart';
import 'widgets/entry_card.dart';
import 'widgets/markdown_view.dart';
import 'widgets/recorder_sheet.dart';

class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key, this.entry, this.at, this.initialTags});

  /// Existing entry to edit; null creates a new one stamped with [at] or now.
  final Entry? entry;
  final DateTime? at;
  final List<String>? initialTags;

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  late final Entry _e = widget.entry?.copy() ?? (Entry.create(at: widget.at)..tags = [...?widget.initialTags]);
  late final _title = TextEditingController(text: _e.title);
  late final _body = TextEditingController(text: _e.body);
  final _bodyFocus = FocusNode();
  late final AppState _app = context.read<AppState>();

  bool _preview = false;
  bool _saved = false;
  bool _dirty = false;
  int _busy = 0;
  Timer? _debounce;
  List<String> _suggestions = [];
  bool _suggesting = false;

  bool get _isNew => widget.entry == null;

  @override
  void initState() {
    super.initState();
    _saved = !_isNew;
    _title.addListener(_changed);
    _body.addListener(_changed);
    _app.beforeLock.add(_flush);
    if (_isNew) WidgetsBinding.instance.addPostFrameCallback((_) => _bodyFocus.requestFocus());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _app.beforeLock.remove(_flush);
    _flush().then((_) => _saved ? _app.autoTag(_e.id) : null);
    _title.dispose();
    _body.dispose();
    _bodyFocus.dispose();
    super.dispose();
  }

  void _changed() {
    if (_title.text == _e.title && _body.text == _e.body) return;
    _e
      ..title = _title.text
      ..body = _body.text;
    _dirty = true;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 1500), _flush);
    setState(() {});
  }

  /// Saves if something changed; a new entry that stayed empty is not kept.
  Future<void> _flush() async {
    _debounce?.cancel();
    if (!_dirty || !_app.unlocked) return;
    _dirty = false;
    if (_e.isEmpty) {
      if (_saved) await _app.deleteEntry(_e.id, toTrash: false);
      _saved = false;
      return;
    }
    await _app.saveEntry(_e.copy());
    _saved = true;
    if (mounted) setState(() {});
  }

  void _touch() {
    _dirty = true;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _flush);
    setState(() {});
  }

  // ---- markdown toolbar ----------------------------------------------------------------------

  void _wrap(String left, [String? right]) {
    final r = right ?? left;
    final sel = _body.selection;
    final text = _body.text;
    if (!sel.isValid) {
      _body.text = '$text$left$r';
      _body.selection = TextSelection.collapsed(offset: text.length + left.length);
      return;
    }
    final chosen = sel.textInside(text);
    _body.value = TextEditingValue(
      text: sel.textBefore(text) + left + chosen + r + sel.textAfter(text),
      selection: chosen.isEmpty
          ? TextSelection.collapsed(offset: sel.start + left.length)
          : TextSelection(baseOffset: sel.start + left.length, extentOffset: sel.start + left.length + chosen.length),
    );
  }

  void _linePrefix(String prefix) {
    final text = _body.text;
    final sel = _body.selection.isValid ? _body.selection : TextSelection.collapsed(offset: text.length);
    final lineStart = text.lastIndexOf('\n', sel.start == 0 ? 0 : sel.start - 1) + 1;
    final hasPrefix = text.startsWith(prefix, lineStart);
    final newText = hasPrefix
        ? text.replaceRange(lineStart, lineStart + prefix.length, '')
        : text.replaceRange(lineStart, lineStart, prefix);
    final delta = hasPrefix ? -prefix.length : prefix.length;
    _body.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: (sel.end + delta).clamp(0, newText.length)),
    );
  }

  void _insert(String s) {
    final text = _body.text;
    final sel = _body.selection.isValid ? _body.selection : TextSelection.collapsed(offset: text.length);
    _body.value = TextEditingValue(
      text: sel.textBefore(text) + s + sel.textAfter(text),
      selection: TextSelection.collapsed(offset: sel.start + s.length),
    );
  }

  // ---- attachments ---------------------------------------------------------------------------

  Future<void> _addFiles(List<(File, String?, int?)> files, {bool deleteSource = true}) async {
    if (files.isEmpty) return;
    setState(() => _busy++);
    try {
      for (final (file, name, durationMs) in files) {
        final a = await _app.store!.importMedia(
          file,
          name: name,
          durationMs: durationMs,
          deleteSource: deleteSource && _isCacheFile(file),
        );
        _e.attachments.add(a);
      }
      _touch();
    } catch (e) {
      _snack(tr('error', {'error': e}));
    } finally {
      if (mounted) setState(() => _busy--);
    }
  }

  /// Pickers hand over copies in the app cache; those are deleted after encryption.
  static bool _isCacheFile(File f) => f.path.contains('/cache/') || f.path.contains('/tmp/');

  Future<void> _pick(String kind) async {
    final picker = ImagePicker();
    try {
      switch (kind) {
        case 'photo':
          final xs = await _app.keepUnlocked(
            () => picker.pickMultiImage(maxWidth: 3000, maxHeight: 3000, imageQuality: 90),
          );
          await _addFiles([for (final x in xs) (File(x.path), x.name, null)]);
        case 'camera':
          final x = await _app.keepUnlocked(
            () => picker.pickImage(source: ImageSource.camera, maxWidth: 3000, maxHeight: 3000, imageQuality: 90),
          );
          if (x != null) await _addFiles([(File(x.path), x.name, null)]);
        case 'video':
          final x = await _app.keepUnlocked(() => picker.pickVideo(source: ImageSource.gallery));
          if (x != null) await _addFiles([(File(x.path), x.name, null)]);
        case 'record_video':
          final x = await _app.keepUnlocked(() => picker.pickVideo(source: ImageSource.camera));
          if (x != null) await _addFiles([(File(x.path), x.name, null)]);
        case 'voice':
          final rec = await showModalBottomSheet<RecordingResult>(
            context: context,
            isDismissible: false,
            enableDrag: false,
            builder: (_) => RecorderSheet(tempDir: _app.temp),
          );
          if (rec != null) await _addFiles([(rec.file, rec.name, rec.duration.inMilliseconds)]);
        case 'file':
          final files = await _app.keepUnlocked(() => FilePicker.pickFiles());
          final picked = <(File, String?, int?)>[];
          for (final f in files) {
            final path = f.path;
            if (path != null) {
              picked.add((File(path), f.name, null));
            } else {
              final tmp = File('${_app.temp.path}/${newId()}');
              await tmp.parent.create(recursive: true);
              await tmp.writeAsBytes(await f.xFile.readAsBytes());
              picked.add((tmp, f.name, null));
            }
          }
          await _addFiles(picked);
      }
    } catch (e) {
      _snack(tr('error', {'error': e}));
    }
  }

  Future<void> _removeAttachment(Attachment a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('delete_attachment')),
        content: Text(a.name),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('cancel'))),
          FilledButton.tonal(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('delete'))),
        ],
      ),
    );
    if (ok != true) return;
    _e.attachments.removeWhere((x) => x.id == a.id);
    _body.text = _body.text.replaceAll(RegExp(r'!?\[[^\]]*\]\(att:' + a.id + r'\)\n?'), '');
    await _app.store!.deleteMedia(a.id);
    _touch();
  }

  // ---- tags ----------------------------------------------------------------------------------

  void _addTag(String raw) {
    final t = normalizeTag(raw);
    if (t == null || _e.allTags.contains(t)) return;
    _e.tags.add(t);
    _suggestions.remove(t);
    _touch();
  }

  Future<void> _askTag() async {
    final known = _app.knownTags.where((t) => !_e.allTags.contains(t)).toList();
    final c = TextEditingController();
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
        child: StatefulBuilder(
          builder: (ctx, setSheet) {
            final q = c.text.trim().toLowerCase().replaceFirst('#', '');
            final matches = known.where((t) => q.isEmpty || t.contains(q)).take(30).toList();
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: c,
                  autofocus: true,
                  decoration: InputDecoration(prefixText: '#', hintText: tr('tag_hint')),
                  onChanged: (_) => setSheet(() {}),
                  onSubmitted: (v) => Navigator.pop(ctx, v),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final t in matches) ActionChip(label: Text('#$t'), onPressed: () => Navigator.pop(ctx, t)),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
    if (result != null) _addTag(result);
  }

  Future<void> _suggest() async {
    final ai = _app.ai;
    if (!ai.isConfigured) return _snack(tr('ai_not_configured'));
    if (!ai.consented) {
      final host = ai.host;
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.privacy_tip_outlined),
          title: Text(tr('ai_consent_title')),
          content: Text(tr('ai_consent_body', {'host': host})),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('no'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('yes'))),
          ],
        ),
      );
      if (ok != true) return;
      _app.ai = ai.copyWith(consented: true);
      await _app.saveSettings();
    }
    setState(() => _suggesting = true);
    try {
      final tags = await _app.suggestTags(_e);
      if (!mounted) return;
      setState(() => _suggestions = tags);
      if (tags.isEmpty) _snack(tr('ai_no_new'));
    } on AiException catch (e) {
      _snack(tr('ai_error', {'error': aiErrorText(e)}));
    } finally {
      if (mounted) setState(() => _suggesting = false);
    }
  }

  // ---- time ----------------------------------------------------------------------------------

  Future<void> _changeTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _e.created,
      firstDate: DateTime(1900),
      lastDate: DateTime.now().add(const Duration(days: 366)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_e.created));
    if (time == null) return;
    _e.created = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    _touch();
  }

  void _snack(String s) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
  }

  Future<void> _delete() async {
    if (!await confirmDeleteEntry(context) || !mounted) return;
    _debounce?.cancel();
    _dirty = false;
    final messenger = ScaffoldMessenger.of(context);
    if (_saved) {
      await _app.deleteEntry(_e.id);
      showTrashedSnack(messenger, _app, _e.id);
    } else {
      for (final a in _e.attachments) {
        await _app.store?.deleteMedia(a.id);
      }
    }
    _saved = false;
    _e.attachments.clear();
    if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
  }

  // ---- build ---------------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _flush();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            _busy > 0 ? tr('adding_media') : (_saved && !_dirty ? tr('saved') : ''),
            style: text.labelLarge?.copyWith(color: cs.onSurfaceVariant),
          ),
          actions: [
            IconButton(
              tooltip: _preview ? tr('edit') : tr('preview'),
              onPressed: () => setState(() => _preview = !_preview),
              icon: Icon(_preview ? Icons.edit_note_rounded : Icons.visibility_outlined),
            ),
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'delete') _delete();
                if (v == 'time') _changeTime();
              },
              itemBuilder: (_) => [
                PopupMenuItem(value: 'time', child: Text(tr('change_time'))),
                PopupMenuItem(value: 'delete', child: Text(tr('delete'))),
              ],
            ),
          ],
        ),
        body: Column(
          children: [
            if (_busy > 0) const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                children: [
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: _changeTime,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          Icon(Icons.event_rounded, size: 18, color: cs.primary),
                          const SizedBox(width: 8),
                          Text(
                            '${fmtFullDate(_e.created)} · ${fmtTime(_e.created)}',
                            style: text.labelLarge?.copyWith(color: cs.primary, fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                  ),
                  _MoodPicker(
                    value: _e.mood,
                    onChanged: (m) {
                      _e.mood = m;
                      _touch();
                    },
                  ),
                  TextField(
                    controller: _title,
                    readOnly: _preview,
                    textCapitalization: TextCapitalization.sentences,
                    style: text.headlineSmall?.copyWith(fontFamily: serif),
                    decoration: InputDecoration(
                      hintText: tr('title_hint'),
                      filled: false,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                    maxLines: null,
                    textInputAction: TextInputAction.next,
                    onSubmitted: (_) => _bodyFocus.requestFocus(),
                  ),
                  if (_preview)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: EntryMarkdown(entry: _e, selectable: false),
                    )
                  else
                    TextField(
                      controller: _body,
                      focusNode: _bodyFocus,
                      maxLines: null,
                      minLines: 8,
                      keyboardType: TextInputType.multiline,
                      textCapitalization: TextCapitalization.sentences,
                      style: text.bodyLarge,
                      decoration: InputDecoration(
                        hintText: tr('body_hint'),
                        filled: false,
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  if (_e.attachments.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    AttachmentGallery(entry: _e, attachments: _e.attachments, onDelete: _removeAttachment),
                  ],
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      for (final t in _e.tags)
                        TagChip(
                          t,
                          onDeleted: () {
                            _e.tags.remove(t);
                            _touch();
                          },
                        ),
                      ActionChip(
                        avatar: const Icon(Icons.add_rounded, size: 18),
                        label: Text(tr('add_tag')),
                        onPressed: _askTag,
                        visualDensity: VisualDensity.compact,
                      ),
                      ActionChip(
                        avatar: _suggesting
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                            : Icon(Icons.auto_awesome_rounded, size: 18, color: cs.tertiary),
                        label: Text(_suggesting ? tr('suggesting') : tr('suggest_tags')),
                        onPressed: _suggesting ? null : _suggest,
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                  if (_suggestions.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(tr('ai_suggestions'), style: text.labelMedium?.copyWith(color: cs.tertiary)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final t in _suggestions)
                          ActionChip(
                            avatar: Icon(Icons.add_rounded, size: 16, color: cs.onTertiaryContainer),
                            backgroundColor: cs.tertiaryContainer,
                            label: Text('#$t', style: TextStyle(color: cs.onTertiaryContainer)),
                            onPressed: () => setState(() => _addTag(t)),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            _Toolbar(
              enabled: !_preview,
              words: _e.wordCount,
              onWrap: _wrap,
              onPrefix: _linePrefix,
              onInsert: _insert,
              onAttach: _pick,
            ),
          ],
        ),
      ),
    );
  }
}

/// Optional mood 1–5; tapping the chosen one clears it.
class _MoodPicker extends StatelessWidget {
  const _MoodPicker({required this.value, required this.onChanged});
  final int? value;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Text(tr('mood'), style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
        const SizedBox(width: 6),
        for (var m = 1; m <= 5; m++)
          Semantics(
            label: tr('mood_$m'),
            selected: value == m,
            button: true,
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => onChanged(value == m ? null : m),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: value == m ? cs.secondaryContainer : Colors.transparent,
                ),
                child: Opacity(
                  opacity: value == null || value == m ? 1 : 0.35,
                  child: Text(moodEmoji(m), style: const TextStyle(fontSize: 20)),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.enabled,
    required this.words,
    required this.onWrap,
    required this.onPrefix,
    required this.onInsert,
    required this.onAttach,
  });

  final bool enabled;
  final int words;
  final void Function(String left, [String? right]) onWrap;
  final ValueChanged<String> onPrefix;
  final ValueChanged<String> onInsert;
  final ValueChanged<String> onAttach;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget b(IconData icon, String tip, VoidCallback onTap) =>
        IconButton(tooltip: tr(tip), onPressed: enabled ? onTap : null, icon: Icon(icon));
    Widget a(IconData icon, String kind) => IconButton(
      tooltip: tr(kind),
      onPressed: () => onAttach(kind),
      icon: Icon(icon, color: cs.primary),
    );
    return Material(
      color: cs.surfaceContainer,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 48,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                children: [
                  a(Icons.photo_library_outlined, 'photo'),
                  a(Icons.photo_camera_outlined, 'camera'),
                  a(Icons.mic_none_rounded, 'voice'),
                  a(Icons.video_library_outlined, 'video'),
                  a(Icons.videocam_outlined, 'record_video'),
                  a(Icons.attach_file_rounded, 'file'),
                  const VerticalDivider(indent: 12, endIndent: 12),
                  b(Icons.format_bold_rounded, 'bold', () => onWrap('**')),
                  b(Icons.format_italic_rounded, 'italic', () => onWrap('*')),
                  b(Icons.title_rounded, 'heading', () => onPrefix('## ')),
                  b(Icons.format_list_bulleted_rounded, 'list', () => onPrefix('- ')),
                  b(Icons.check_box_outlined, 'checklist', () => onPrefix('- [ ] ')),
                  b(Icons.format_quote_rounded, 'quote', () => onPrefix('> ')),
                  b(Icons.link_rounded, 'link', () => onWrap('[', '](https://)')),
                  b(Icons.horizontal_rule_rounded, 'divider', () => onInsert('\n\n---\n\n')),
                  b(Icons.tag_rounded, 'hashtag', () => onInsert('#')),
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        tr('words', {'n': words}),
                        style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

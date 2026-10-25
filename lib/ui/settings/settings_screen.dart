import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../l10n/strings.dart';
import '../../services/exporter.dart';
import '../../services/importer.dart';
import '../../state/app_state.dart';
import '../lock_screen.dart';
import '../theme.dart';
import '../widgets/entry_card.dart';
import 'ai_settings_screen.dart';
import 'git_settings_screen.dart';

const appVersion = '0.1.0';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final p = app.prefs;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(tr('settings'))),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          _Section(tr('appearance')),
          ListTile(
            leading: const Icon(Icons.brightness_6_outlined),
            title: Text(tr('theme')),
            trailing: SegmentedButton<ThemeModeSetting>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                  value: ThemeModeSetting.system,
                  icon: const Icon(Icons.phone_android_rounded),
                  tooltip: tr('theme_system'),
                ),
                ButtonSegment(
                  value: ThemeModeSetting.light,
                  icon: const Icon(Icons.light_mode_rounded),
                  tooltip: tr('theme_light'),
                ),
                ButtonSegment(
                  value: ThemeModeSetting.dark,
                  icon: const Icon(Icons.dark_mode_rounded),
                  tooltip: tr('theme_dark'),
                ),
              ],
              selected: {p.themeMode},
              onSelectionChanged: (s) => app.updatePrefs((p) => p.themeMode = s.first),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.palette_outlined),
            title: Text(tr('accent')),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(
                spacing: 10,
                children: [
                  for (var i = 0; i < accents.length; i++)
                    GestureDetector(
                      onTap: () => app.updatePrefs((p) => p.accent = i),
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: accents[i],
                          shape: BoxShape.circle,
                          border: Border.all(color: p.accent == i ? cs.onSurface : Colors.transparent, width: 3),
                        ),
                        child: p.accent == i ? const Icon(Icons.check_rounded, color: Colors.white, size: 18) : null,
                      ),
                    ),
                ],
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.translate_rounded),
            title: Text(tr('language')),
            trailing: DropdownButton<String>(
              value: p.language,
              underline: const SizedBox(),
              items: const [
                DropdownMenuItem(value: 'ru', child: Text('Русский')),
                DropdownMenuItem(value: 'en', child: Text('English')),
              ],
              onChanged: (v) => app.updatePrefs((p) => p.language = v ?? 'ru'),
            ),
          ),
          _Section(tr('security')),
          ListTile(
            leading: const Icon(Icons.timer_outlined),
            title: Text(tr('auto_lock')),
            trailing: DropdownButton<int>(
              value: [0, 60, 300].contains(p.autoLockSeconds) ? p.autoLockSeconds : 60,
              underline: const SizedBox(),
              items: [
                for (final s in [0, 60, 300]) DropdownMenuItem(value: s, child: Text(tr('auto_lock_$s'))),
              ],
              onChanged: (v) => app.updatePrefs((p) => p.autoLockSeconds = v ?? 60),
            ),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.fingerprint_rounded),
            title: Text(tr('biometric')),
            subtitle: Text(tr('biometric_sub')),
            value: p.biometric,
            onChanged: (v) async {
              final ok = await app.setBiometric(v);
              if (!ok && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('biometric_unavailable'))));
              }
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.screenshot_monitor_outlined),
            title: Text(tr('secure_screen')),
            subtitle: Text(tr('secure_screen_sub')),
            value: p.secureScreen,
            onChanged: (v) => app.updatePrefs((p) => p.secureScreen = v),
          ),
          ListTile(
            leading: const Icon(Icons.password_rounded),
            title: Text(tr('change_password')),
            onTap: () => _changePassword(context),
          ),
          _Section(tr('ai_section')),
          ListTile(
            leading: Icon(Icons.auto_awesome_rounded, color: cs.tertiary),
            title: Text(tr('ai_section')),
            subtitle: Text(app.ai.isConfigured ? app.ai.model : tr('ai_sub')),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AiSettingsScreen())),
          ),
          _Section(tr('git_section')),
          ListTile(
            leading: const Icon(Icons.cloud_sync_outlined),
            title: Text(tr('git_section')),
            subtitle: Text(
              app.git.isConfigured
                  ? '${app.git.owner}/${app.git.repo} · ${app.git.plain ? tr('git_mode_plain') : tr('git_mode_enc')}'
                  : tr('git_sub_off'),
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const GitSettingsScreen())),
          ),
          _Section(tr('data')),
          ListTile(
            leading: const Icon(Icons.file_download_outlined),
            title: Text(tr('import')),
            subtitle: Text(tr('import_sub')),
            onTap: () => _import(context),
          ),
          ListTile(
            leading: const Icon(Icons.archive_outlined),
            title: Text(tr('export')),
            subtitle: Text(tr('export_sub')),
            onTap: () => _export(context),
          ),
          ListTile(
            leading: const Icon(Icons.insights_rounded),
            title: Text(tr('stats_title')),
            onTap: () => _stats(context),
          ),
          _Section(tr('about')),
          ListTile(
            leading: const Icon(Icons.info_outline_rounded),
            title: Text('${tr('app_name')} $appVersion'),
            subtitle: Text(tr('about_body', {'version': appVersion})),
            isThreeLine: true,
          ),
        ],
      ),
    );
  }

  Future<void> _changePassword(BuildContext context) async {
    final cur = TextEditingController(), next = TextEditingController(), again = TextEditingController();
    String? error;
    var busy = false;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) {
          Future<void> go() async {
            if (next.text.length < 6) return setD(() => error = tr('password_short'));
            if (next.text != again.text) return setD(() => error = tr('password_mismatch'));
            setD(() => busy = true);
            final ok = await ctx.read<AppState>().changePassword(cur.text, next.text);
            if (!ctx.mounted) return;
            if (!ok) {
              return setD(() {
                busy = false;
                error = tr('wrong_password');
              });
            }
            Navigator.pop(ctx);
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('password_changed'))));
          }

          return AlertDialog(
            title: Text(tr('change_password')),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  PasswordField(controller: cur, label: tr('current_password')),
                  const SizedBox(height: 10),
                  PasswordField(controller: next, label: tr('new_password')),
                  const SizedBox(height: 10),
                  PasswordField(controller: again, label: tr('password_repeat'), error: error),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: busy ? null : () => Navigator.pop(ctx), child: Text(tr('cancel'))),
              FilledButton(onPressed: busy ? null : go, child: Text(busy ? tr('deriving_key') : tr('save'))),
            ],
          );
        },
      ),
    );
  }

  Future<void> _import(BuildContext context) async {
    final app = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    final files = await app.keepUnlocked(() => FilePicker.pickFiles());
    if (files.isEmpty || !context.mounted) return;
    final previews = <ImportPreview>[];
    for (final f in files) {
      final bytes = f.path != null ? await File(f.path!).readAsBytes() : await f.xFile.readAsBytes();
      previews.add(parseImport(_decode(bytes), fileName: f.name));
    }
    final all = [for (final p in previews) ...p.entries];
    if (all.isEmpty || !context.mounted) return;
    final merged = ImportPreview(previews.map((p) => p.format).toSet().join(', '), all);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.file_download_outlined),
        title: Text(tr('import')),
        content: Text(
          tr('import_found', {
            'n': all.length,
            'from': fmtDateTime(merged.first!),
            'to': fmtDateTime(merged.last!),
            'format': merged.format,
          }),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('import_go'))),
        ],
      ),
    );
    if (ok != true) return;
    final existing = {for (final e in app.entries) duplicateKey(e)};
    final fresh = all.where((e) => existing.add(duplicateKey(e))).toList();
    await app.saveAll(fresh);
    messenger.showSnackBar(
      SnackBar(content: Text(tr('import_done', {'n': fresh.length, 'skipped': all.length - fresh.length}))),
    );
  }

  static String _decode(List<int> bytes) {
    try {
      return const Utf8Codec().decode(bytes);
    } on FormatException {
      return const Utf8Codec(allowMalformed: true).decode(bytes);
    }
  }

  Future<void> _export(BuildContext context) async {
    final app = context.read<AppState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded),
        title: Text(tr('export')),
        content: Text(tr('export_warning')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('export'))),
        ],
      ),
    );
    if (ok != true) return;
    final dir = Directory('${app.temp.path}/export');
    final file = await exportZip(app.store!, dir);
    await app.keepUnlocked(() => SharePlus.instance.share(ShareParams(files: [XFile(file.path)])));
  }

  void _stats(BuildContext context) {
    final app = context.read<AppState>();
    final entries = app.entries;
    final days = {for (final e in entries) DateUtils.dateOnly(e.created)}.length;
    final words = entries.fold<int>(0, (n, e) => n + e.wordCount);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.insights_rounded),
        title: Text(tr('stats_title')),
        content: Text(
          tr('stats_body', {'entries': entries.length, 'words': words, 'days': days, 'streak': app.streak}),
          style: const TextStyle(height: 1.6),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('close')))],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title);
  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 24, 20, 6),
    child: Text(
      title.toUpperCase(),
      style: Theme.of(context).textTheme.labelMedium
          ?.copyWith(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w700, letterSpacing: 1.2),
    ),
  );
}

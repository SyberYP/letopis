import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/strings.dart';
import '../../services/exporter.dart';
import '../../services/channel.dart';
import '../../services/importer.dart';
import '../../services/support.dart';
import '../../services/update_check.dart';
import '../../state/app_state.dart';
import '../lock_screen.dart';
import '../theme.dart';
import '../widgets/entry_card.dart';
import '../widgets/markdown_view.dart';
import 'ai_settings_screen.dart';
import 'cloud_settings_screen.dart';
import 'git_settings_screen.dart';
import 'pdf_export_flow.dart';
import 'stats_screen.dart';
import 'trash_screen.dart';

/// Privacy policy, also linked from the store listings.
const privacyUrl = 'https://letopis.recalltwin.com/privacy';

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
          _Section(tr('sync_section')),
          ListTile(
            leading: const Icon(Icons.cloud_sync_outlined),
            title: Text(tr('dav_title')),
            subtitle: Text(app.dav.isConfigured ? '${app.dav.label} · ${app.dav.dir}' : tr('dav_sub_off')),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CloudSettingsScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.code_rounded),
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
            leading: const Icon(Icons.picture_as_pdf_outlined),
            title: Text(tr('pdf')),
            subtitle: Text(tr('pdf_sub')),
            onTap: () => exportPdfFlow(context),
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
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const StatsScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline_rounded),
            title: Text(tr('trash')),
            subtitle: Text(plural('entries', app.store?.trash.length ?? 0)),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TrashScreen())),
          ),
          _Section(tr('about')),
          ListTile(
            leading: const Icon(Icons.info_outline_rounded),
            title: Text('${tr('app_name')} ${app.version}'),
            subtitle: Text(tr('about_body')),
          ),
          if (siteBuild || rustoreBuild)
            ListTile(
              leading: Icon(Icons.favorite_rounded, color: Theme.of(context).colorScheme.primary),
              title: Text(tr('support')),
              subtitle: Text(tr('support_sub')),
              onTap: () => siteBuild ? _supportOnSite(context) : _supportInRuStore(context),
            ),
          if (siteBuild) const _UpdateTile(),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: Text(tr('privacy_policy')),
            trailing: const Icon(Icons.open_in_new_rounded, size: 18),
            onTap: () => openExternalLink(context, privacyUrl),
          ),
          ListTile(
            leading: const Icon(Icons.gavel_rounded),
            title: Text(tr('licenses')),
            onTap: () => showLicensePage(
              context: context,
              applicationName: tr('app_name'),
              applicationVersion: app.version,
            ),
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

/// "Check for updates" — only in the download-site build, only on tap.
class _UpdateTile extends StatefulWidget {
  const _UpdateTile();

  @override
  State<_UpdateTile> createState() => _UpdateTileState();
}

class _UpdateTileState extends State<_UpdateTile> {
  bool _busy = false;

  Future<void> _check() async {
    final app = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    UpdateInfo? update;
    var failed = false;
    try {
      update = await checkForUpdate(currentBuild: app.buildNumber);
    } catch (_) {
      failed = true;
    }
    if (!mounted) return;
    setState(() => _busy = false);
    if (failed || update == null) {
      messenger.showSnackBar(SnackBar(content: Text(tr(failed ? 'update_error' : 'update_none'))));
      return;
    }
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.system_update_rounded),
        title: Text(tr('update_title')),
        content: Text(tr('update_body', {'version': update!.version})),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('update_download'))),
        ],
      ),
    );
    if (go != true) return;
    try {
      if (!await launchUrl(Uri.parse(siteUrl), mode: LaunchMode.externalApplication)) {
        messenger.showSnackBar(SnackBar(content: Text(tr('open_link_error'))));
      }
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(tr('open_link_error'))));
    }
  }

  @override
  Widget build(BuildContext context) => ListTile(
    leading: const Icon(Icons.system_update_rounded),
    title: Text(tr('update_check')),
    subtitle: Text(tr('update_check_sub')),
    trailing: _busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : null,
    onTap: _busy ? null : _check,
  );
}

/// Site build: the author's CloudTips page, after saying where it leads.
Future<void> _supportOnSite(BuildContext context) async {
  final messenger = ScaffoldMessenger.of(context);
  final go = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.favorite_rounded),
      title: Text(tr('support')),
      content: Text(tr('support_site_body')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('cancel'))),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('support_open'))),
      ],
    ),
  );
  if (go != true) return;
  try {
    if (!await launchUrl(Uri.parse(supportUrl), mode: LaunchMode.externalApplication)) {
      messenger.showSnackBar(SnackBar(content: Text(tr('open_link_error'))));
    }
  } catch (_) {
    messenger.showSnackBar(SnackBar(content: Text(tr('open_link_error'))));
  }
}

/// RuStore build: a one-off payment through RuStore.
Future<void> _supportInRuStore(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  builder: (_) => const RuStoreSupportSheet(),
);

/// Public for tests.
class RuStoreSupportSheet extends StatefulWidget {
  const RuStoreSupportSheet({super.key});

  @override
  State<RuStoreSupportSheet> createState() => _RuStoreSupportSheetState();
}

class _RuStoreSupportSheetState extends State<RuStoreSupportSheet> {
  List<SupportOption>? _options;
  String? _error;
  bool _paying = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _error = null;
      _options = null;
    });
    try {
      final list = await supportStore.options();
      if (mounted) setState(() => _options = list);
    } on SupportException catch (e) {
      if (mounted) setState(() => _error = e.code);
    } catch (_) {
      if (mounted) setState(() => _error = 'failed');
    }
  }

  Future<void> _pay(SupportOption o) async {
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    setState(() => _paying = true);
    try {
      final r = await supportStore.pay(o.id, dark: dark);
      if (r == SupportResult.thanks) {
        nav.pop();
        messenger.showSnackBar(SnackBar(content: Text(tr('support_thanks'))));
        return;
      }
    } on SupportException catch (e) {
      if (mounted) setState(() => _error = e.code);
    } catch (_) {
      if (mounted) setState(() => _error = 'failed');
    }
    if (mounted) setState(() => _paying = false);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(tr('support'), style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(tr('support_store_body'), style: TextStyle(color: cs.onSurfaceVariant)),
            const SizedBox(height: 20),
            if (_error != null) ...[
              Text(tr('support_err_$_error'), style: TextStyle(color: cs.error)),
              const SizedBox(height: 12),
              if (_error == 'unauthorized')
                FilledButton(
                  onPressed: () async {
                    try {
                      await supportStore.signIn();
                    } catch (_) {}
                    _load();
                  },
                  child: Text(tr('support_sign_in')),
                )
              else
                OutlinedButton(onPressed: _load, child: Text(tr('support_retry'))),
            ] else if (_options == null || _paying)
              const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()))
            else
              Wrap(
                spacing: 12,
                runSpacing: 12,
                alignment: WrapAlignment.center,
                children: [
                  for (final o in _options!) FilledButton.tonal(onPressed: () => _pay(o), child: Text(o.price)),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/strings.dart';
import '../../services/git_remote.dart';
import '../../services/webdav_remote.dart';
import '../../state/app_state.dart';
import '../home_screen.dart';
import '../lock_screen.dart';
import '../widgets/entry_card.dart';
import 'cloud_settings_screen.dart';

/// Repository, branch, folder and token fields, shared by settings and restore.
class _GitForm extends StatefulWidget {
  const _GitForm({required this.initial, required this.onChanged, this.showMode = true});
  final GitHubConfig initial;
  final ValueChanged<GitHubConfig> onChanged;
  final bool showMode;

  @override
  State<_GitForm> createState() => _GitFormState();
}

class _GitFormState extends State<_GitForm> {
  late final _repo = TextEditingController(
    text: widget.initial.owner.isEmpty ? '' : '${widget.initial.owner}/${widget.initial.repo}',
  );
  late final _branch = TextEditingController(text: widget.initial.branch);
  late final _dir = TextEditingController(text: widget.initial.dir);
  late final _token = TextEditingController(text: widget.initial.token);
  late bool _plain = widget.initial.plain;
  late bool _auto = widget.initial.autoSync;
  bool _hide = true;

  void _emit() {
    final parsed = GitHubConfig.parseRepo(_repo.text);
    widget.onChanged(
      widget.initial.copyWith(
        owner: parsed?.$1 ?? '',
        repo: parsed?.$2 ?? '',
        branch: _branch.text.trim().isEmpty ? 'main' : _branch.text.trim(),
        dir: _dir.text.trim().replaceAll(RegExp(r'^/+|/+$'), ''),
        token: _token.text.trim(),
        plain: _plain,
        autoSync: _auto,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _repo,
          autocorrect: false,
          decoration: InputDecoration(
            labelText: tr('git_repo'),
            hintText: 'SyberYP/diary',
            prefixIcon: const Icon(Icons.book_outlined),
          ),
          onChanged: (_) => _emit(),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _branch,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: tr('git_branch'),
                  prefixIcon: const Icon(Icons.alt_route_rounded),
                ),
                onChanged: (_) => _emit(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _dir,
                autocorrect: false,
                decoration: InputDecoration(labelText: tr('git_dir'), prefixIcon: const Icon(Icons.folder_outlined)),
                onChanged: (_) => _emit(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _token,
          obscureText: _hide,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(
            labelText: tr('git_token'),
            hintText: 'github_pat_…',
            prefixIcon: const Icon(Icons.vpn_key_outlined),
            suffixIcon: IconButton(
              icon: Icon(_hide ? Icons.visibility_rounded : Icons.visibility_off_rounded),
              onPressed: () => setState(() => _hide = !_hide),
            ),
          ),
          onChanged: (_) => _emit(),
        ),
        const SizedBox(height: 6),
        Text(tr('git_token_help'), style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
        if (widget.showMode) ...[
          const SizedBox(height: 16),
          Text(tr('git_mode'), style: Theme.of(context).textTheme.titleSmall),
          RadioGroup<bool>(
            groupValue: _plain,
            onChanged: (v) {
              setState(() => _plain = v ?? false);
              _emit();
            },
            child: Column(
              children: [
                RadioListTile<bool>(
                  contentPadding: EdgeInsets.zero,
                  value: false,
                  title: Text(tr('git_mode_enc')),
                  subtitle: Text(tr('git_mode_enc_sub')),
                ),
                RadioListTile<bool>(
                  contentPadding: EdgeInsets.zero,
                  value: true,
                  title: Text(tr('git_mode_plain')),
                  subtitle: Text(tr('git_mode_plain_sub')),
                ),
              ],
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr('git_auto')),
            value: _auto,
            onChanged: (v) {
              setState(() => _auto = v);
              _emit();
            },
          ),
        ],
      ],
    );
  }
}

class GitSettingsScreen extends StatefulWidget {
  const GitSettingsScreen({super.key});

  @override
  State<GitSettingsScreen> createState() => _GitSettingsScreenState();
}

class _GitSettingsScreenState extends State<GitSettingsScreen> {
  late final AppState _app = context.read<AppState>();
  late GitHubConfig _config = _app.git;
  String? _check;
  bool _checking = false;
  DateTime? _last;

  @override
  void initState() {
    super.initState();
    _app.loadLastSync().then((d) => mounted ? setState(() => _last = d) : null);
  }

  Future<void> _save() async {
    if (_config.key != _app.git.key || _config.token != _app.git.token || _config.autoSync != _app.git.autoSync) {
      _app.git = _config;
      // One sync target at a time: connecting GitHub switches the cloud off.
      if (_config.isConfigured && _app.dav.isConfigured) _app.dav = const WebDavConfig();
      await _app.saveSettings();
    }
  }

  Future<void> _checkAccess() async {
    setState(() {
      _checking = true;
      _check = null;
    });
    try {
      final private = await GitHubRepo(_config).check();
      _check = private
          ? tr('git_ok_private')
          : '${tr('git_ok_public')}. ${_config.plain ? tr('git_public_plain') : ''}';
    } catch (e) {
      _check = tr('error', {'error': e});
    }
    if (mounted) setState(() => _checking = false);
  }

  @override
  void dispose() {
    _save();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: Text(tr('git_section'))),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (app.dav.isConfigured) ...[
            Card(
              color: Theme.of(context).colorScheme.tertiaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Text(
                  tr('git_replaces_dav', {'name': app.dav.label}),
                  style: TextStyle(color: Theme.of(context).colorScheme.onTertiaryContainer),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          _GitForm(initial: _config, onChanged: (c) => setState(() => _config = c)),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _checking || !_config.isConfigured ? null : _checkAccess,
                  icon: _checking
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.verified_user_outlined),
                  label: Text(tr('git_check')),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: !_config.isConfigured || app.syncStatus == SyncStatus.running
                      ? null
                      : () async {
                          await _save();
                          if (!context.mounted) return;
                          await runSync(context);
                          _last = await app.loadLastSync();
                          if (mounted) setState(() {});
                        },
                  icon: app.syncStatus == SyncStatus.running
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.sync_rounded),
                  label: Text(tr('sync_now')),
                ),
              ),
            ],
          ),
          if (_check != null) ...[const SizedBox(height: 12), Text(_check!)],
          const SizedBox(height: 12),
          Text(
            _last == null ? tr('git_never') : tr('git_last_sync', {'time': fmtDateTime(_last!)}),
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          if (app.syncStatus == SyncStatus.error) ...[
            const SizedBox(height: 8),
            Text(app.syncMessage, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
        ],
      ),
    );
  }
}

/// First-launch path: bring an encrypted diary back from GitHub.
class RestoreScreen extends StatefulWidget {
  const RestoreScreen({super.key});

  @override
  State<RestoreScreen> createState() => _RestoreScreenState();
}

class _RestoreScreenState extends State<RestoreScreen> {
  GitHubConfig _config = const GitHubConfig(autoSync: true);
  WebDavConfig _cloud = const WebDavConfig(autoSync: true);
  bool _fromCloud = false;
  final _pw = TextEditingController();
  String? _error;
  bool _busy = false;

  Future<void> _go() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final app = context.read<AppState>();
    final nav = Navigator.of(context);
    try {
      final err = _fromCloud
          ? await app.restore(_cloud, _pw.text)
          : await app.restoreFromGit(_config.copyWith(plain: false), _pw.text);
      if (err != null) {
        setState(() => _error = tr(err));
      } else {
        nav.popUntil((r) => r.isFirst);
        return;
      }
    } catch (e) {
      setState(() => _error = cloudError(e));
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('restore_title'))),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(tr('restore_body')),
          const SizedBox(height: 16),
          SegmentedButton<bool>(
            segments: [
              const ButtonSegment(value: false, label: Text('GitHub'), icon: Icon(Icons.code_rounded)),
              ButtonSegment(value: true, label: Text(tr('dav_short')), icon: const Icon(Icons.cloud_outlined)),
            ],
            selected: {_fromCloud},
            onSelectionChanged: (s) => setState(() {
              _fromCloud = s.first;
              _error = null;
            }),
          ),
          const SizedBox(height: 20),
          if (_fromCloud)
            CloudForm(initial: _cloud, showAuto: false, onChanged: (c) => _cloud = c)
          else
            _GitForm(initial: _config, showMode: false, onChanged: (c) => _config = c),
          const SizedBox(height: 16),
          PasswordField(controller: _pw, label: tr('password'), error: _error),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _busy ? null : _go,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            icon: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.cloud_download_rounded),
            label: Text(tr('restore_go')),
          ),
        ],
      ),
    );
  }
}

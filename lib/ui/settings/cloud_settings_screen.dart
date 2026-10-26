import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/strings.dart';
import '../../services/git_remote.dart';
import '../../services/webdav_remote.dart';
import '../../state/app_state.dart';
import '../home_screen.dart';
import '../widgets/entry_card.dart';

/// Service, address, login, app password and folder; shared by settings and restore.
class CloudForm extends StatefulWidget {
  const CloudForm({super.key, required this.initial, required this.onChanged, this.showAuto = true});
  final WebDavConfig initial;
  final ValueChanged<WebDavConfig> onChanged;
  final bool showAuto;

  @override
  State<CloudForm> createState() => _CloudFormState();
}

class _CloudFormState extends State<CloudForm> {
  late WebDavPreset _preset = widget.initial.url.isEmpty
      ? WebDavPreset.all.first
      : WebDavPreset.forUrl(widget.initial.url);
  late final _url = TextEditingController(text: widget.initial.url.isEmpty ? _preset.url : widget.initial.url);
  late final _user = TextEditingController(text: widget.initial.user);
  late final _password = TextEditingController(text: widget.initial.password);
  late final _dir = TextEditingController(text: widget.initial.dir);
  late bool _auto = widget.initial.autoSync;
  bool _hide = true;

  @override
  void initState() {
    super.initState();
    if (widget.initial.url.isEmpty) WidgetsBinding.instance.addPostFrameCallback((_) => _emit());
  }

  void _emit() => widget.onChanged(
    widget.initial.copyWith(
      url: _url.text.trim(),
      user: _user.text.trim(),
      password: _password.text,
      dir: _dir.text.trim().replaceAll(RegExp(r'^/+|/+$'), ''),
      autoSync: _auto,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final urlError = _url.text.trim().isEmpty || _url.text.trim() == 'https://'
        ? null
        : switch (WebDavConfig.urlProblem(_url.text)) {
            null => null,
            final p => tr('dav_err_$p'),
          };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final p in WebDavPreset.all)
              ChoiceChip(
                label: Text(tr('dav_p_${p.id}')),
                selected: _preset.id == p.id,
                onSelected: (_) => setState(() {
                  _preset = p;
                  _url.text = p.url;
                  _emit();
                }),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Text(tr(_preset.helpKey), style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
        const SizedBox(height: 14),
        TextField(
          controller: _url,
          autocorrect: false,
          keyboardType: TextInputType.url,
          decoration: InputDecoration(
            labelText: tr('dav_url'),
            prefixIcon: const Icon(Icons.dns_outlined),
            errorText: urlError,
          ),
          onChanged: (_) => setState(_emit),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _user,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(labelText: tr('dav_user'), prefixIcon: const Icon(Icons.person_outline_rounded)),
          onChanged: (_) => _emit(),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _password,
          obscureText: _hide,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(
            labelText: tr('dav_password'),
            prefixIcon: const Icon(Icons.vpn_key_outlined),
            suffixIcon: IconButton(
              icon: Icon(_hide ? Icons.visibility_rounded : Icons.visibility_off_rounded),
              onPressed: () => setState(() => _hide = !_hide),
            ),
          ),
          onChanged: (_) => _emit(),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _dir,
          autocorrect: false,
          decoration: InputDecoration(labelText: tr('dav_dir'), prefixIcon: const Icon(Icons.folder_outlined)),
          onChanged: (_) => _emit(),
        ),
        if (widget.showAuto)
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
    );
  }
}

/// Readable reason for a failed check or sync.
String cloudError(Object e) {
  if (e is RemoteException) {
    if (e.statusCode == 401) return tr('dav_err_401');
    if (e.statusCode == 507) return tr('dav_err_full');
    if (e.message == 'bad_url' || e.message == 'https_only') return tr('dav_err_${e.message}');
  }
  return tr('error', {'error': e});
}

class CloudSettingsScreen extends StatefulWidget {
  const CloudSettingsScreen({super.key});

  @override
  State<CloudSettingsScreen> createState() => _CloudSettingsScreenState();
}

class _CloudSettingsScreenState extends State<CloudSettingsScreen> {
  late final AppState _app = context.read<AppState>();
  late WebDavConfig _config = _app.dav.url.isEmpty ? const WebDavConfig(autoSync: true) : _app.dav;
  String? _check;
  bool _checkOk = false;
  bool _checking = false;
  DateTime? _last;
  int _formKey = 0;

  @override
  void initState() {
    super.initState();
    _app.loadLastSync().then((d) => mounted ? setState(() => _last = d) : null);
  }

  /// Saves the form; connecting the cloud switches GitHub sync off (one target at a time).
  Future<void> _save() async {
    final a = _app.dav;
    final changed = _config.key != a.key || _config.password != a.password || _config.autoSync != a.autoSync;
    if (!changed) return;
    if (!_config.isConfigured && !a.isConfigured) return;
    _app.dav = _config;
    if (_config.isConfigured && _app.git.isConfigured) _app.git = const GitHubConfig();
    await _app.saveSettings();
  }

  Future<void> _checkAccess() async {
    setState(() {
      _checking = true;
      _check = null;
    });
    try {
      await WebDavRepo(_config).check();
      _check = tr('dav_ok');
      _checkOk = true;
    } catch (e) {
      _check = cloudError(e);
      _checkOk = false;
    }
    if (mounted) setState(() => _checking = false);
  }

  Future<void> _disconnect() async {
    _app.dav = const WebDavConfig();
    await _app.saveSettings();
    setState(() {
      _config = const WebDavConfig(autoSync: true);
      _check = null;
      _formKey++;
    });
  }

  @override
  void dispose() {
    _save();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(tr('dav_title'))),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(tr('dav_note'), style: TextStyle(color: cs.onSurfaceVariant)),
          if (app.git.isConfigured) ...[
            const SizedBox(height: 12),
            Card(
              color: cs.tertiaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Text(tr('dav_replaces_git'), style: TextStyle(color: cs.onTertiaryContainer)),
              ),
            ),
          ],
          const SizedBox(height: 16),
          CloudForm(
            key: ValueKey(_formKey),
            initial: _config,
            onChanged: (c) => setState(() => _config = c),
          ),
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
          if (_check != null) ...[
            const SizedBox(height: 12),
            Text(_check!, style: TextStyle(color: _checkOk ? null : cs.error)),
          ],
          if (app.dav.isConfigured) ...[
            const SizedBox(height: 12),
            Text(
              _last == null ? tr('git_never') : tr('git_last_sync', {'time': fmtDateTime(_last!)}),
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
            if (app.syncStatus == SyncStatus.error) ...[
              const SizedBox(height: 8),
              Text(app.syncMessage, style: TextStyle(color: cs.error)),
            ],
            const SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: _disconnect,
                icon: const Icon(Icons.link_off_rounded),
                label: Text(tr('dav_disconnect')),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

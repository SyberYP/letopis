import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/entry.dart';
import '../../l10n/strings.dart';
import '../../services/ai_tagger.dart';
import '../../state/app_state.dart';

/// User-facing text for an AI error.
String aiErrorText(AiException e) => switch (e.message) {
  'no_key' => tr('ai_not_configured'),
  'https_only' => tr('ai_https_only'),
  _ => e.message,
};

class AiSettingsScreen extends StatefulWidget {
  const AiSettingsScreen({super.key});

  @override
  State<AiSettingsScreen> createState() => _AiSettingsScreenState();
}

class _AiSettingsScreenState extends State<AiSettingsScreen> {
  late final AppState _app = context.read<AppState>();
  late final _url = TextEditingController(text: _app.ai.baseUrl);
  late final _key = TextEditingController(text: _app.ai.apiKey);
  late final _model = TextEditingController(text: _app.ai.model);
  late bool _auto = _app.ai.autoTag;
  bool _hideKey = true;
  bool _testing = false;
  String? _result;

  AiConfig get _config {
    final next = _app.ai.copyWith(
      baseUrl: _url.text.trim().isEmpty ? AiConfig.defaultBaseUrl : _url.text.trim(),
      apiKey: _key.text.trim(),
      model: _model.text.trim().isEmpty ? AiConfig.defaultModel : _model.text.trim(),
      autoTag: _auto,
    );
    // Consent covers one provider: a new host asks again before any entry text goes there.
    return next.host == _app.ai.host ? next : next.copyWith(consented: false);
  }

  Future<void> _save() async {
    _app.ai = _config;
    await _app.saveSettings();
  }

  Future<void> _test() async {
    setState(() {
      _testing = true;
      _result = null;
    });
    try {
      final sample = Entry.create()
        ..body = tr('ai_test_sample');
      final tags = await AiTagger(_config).suggest(sample, const []);
      _result = tr('ai_ok', {'tags': tags.map((t) => '#$t').join(' ')});
    } on AiException catch (e) {
      _result = tr('ai_error', {'error': aiErrorText(e)});
    }
    if (mounted) setState(() => _testing = false);
  }

  @override
  void dispose() {
    _save();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(tr('ai_section'))),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(tr('ai_sub'), style: TextStyle(color: cs.onSurfaceVariant)),
          const SizedBox(height: 20),
          TextField(
            controller: _key,
            obscureText: _hideKey,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: tr('ai_key'),
              hintText: 'sk-or-v1-…',
              prefixIcon: const Icon(Icons.vpn_key_outlined),
              suffixIcon: IconButton(
                icon: Icon(_hideKey ? Icons.visibility_rounded : Icons.visibility_off_rounded),
                onPressed: () => setState(() => _hideKey = !_hideKey),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _model,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: tr('ai_model'),
              hintText: AiConfig.defaultModel,
              prefixIcon: const Icon(Icons.psychology_outlined),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _url,
            autocorrect: false,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(labelText: tr('ai_base_url'), prefixIcon: const Icon(Icons.link_rounded)),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr('ai_auto')),
            value: _auto,
            onChanged: (v) => setState(() => _auto = v),
          ),
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            onPressed: _testing ? null : _test,
            icon: _testing
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.play_arrow_rounded),
            label: Text(tr('ai_test')),
          ),
          if (_result != null) ...[const SizedBox(height: 12), Text(_result!)],
        ],
      ),
    );
  }
}

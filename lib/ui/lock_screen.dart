import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/strings.dart';
import '../state/app_state.dart';
import 'settings/git_settings_screen.dart';
import 'theme.dart';

/// Brand header used on the setup and lock screens.
class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        Container(
          width: 84,
          height: 84,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [cs.primary, Color.lerp(cs.primary, Colors.black, 0.35)!],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(color: cs.primary.withValues(alpha: 0.3), blurRadius: 24, offset: const Offset(0, 10)),
            ],
          ),
          child: Icon(Icons.auto_stories_rounded, size: 44, color: cs.onPrimary),
        ),
        const SizedBox(height: 20),
        Text(
          tr('app_name'),
          style: Theme.of(context).textTheme.displaySmall?.copyWith(fontFamily: serif, color: cs.onSurface),
        ),
        const SizedBox(height: 8),
        Text(
          tr('tagline'),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _Frame extends StatelessWidget {
  const _Frame({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
            ),
          ),
        ),
      ),
    );
  }
}

class PasswordField extends StatefulWidget {
  const PasswordField({
    super.key,
    required this.controller,
    required this.label,
    this.error,
    this.onSubmitted,
    this.autofocus = false,
  });
  final TextEditingController controller;
  final String label;
  final String? error;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _hidden = true;

  @override
  Widget build(BuildContext context) => TextField(
    controller: widget.controller,
    obscureText: _hidden,
    autofocus: widget.autofocus,
    enableSuggestions: false,
    autocorrect: false,
    onSubmitted: widget.onSubmitted,
    decoration: InputDecoration(
      labelText: widget.label,
      errorText: widget.error,
      prefixIcon: const Icon(Icons.key_rounded),
      suffixIcon: IconButton(
        icon: Icon(_hidden ? Icons.visibility_rounded : Icons.visibility_off_rounded),
        onPressed: () => setState(() => _hidden = !_hidden),
      ),
    ),
  );
}

/// First launch: create the password (or restore an existing diary from GitHub).
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _pw = TextEditingController();
  final _pw2 = TextEditingController();
  String? _error;
  bool _busy = false;

  Future<void> _create() async {
    if (_pw.text.length < 6) return setState(() => _error = tr('password_short'));
    if (_pw.text != _pw2.text) return setState(() => _error = tr('password_mismatch'));
    setState(() {
      _error = null;
      _busy = true;
    });
    await context.read<AppState>().createVault(_pw.text);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return _Frame(
      children: [
        const _Brand(),
        const SizedBox(height: 36),
        Text(tr('setup_title'), style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(tr('setup_body'), style: TextStyle(color: cs.onSurfaceVariant, height: 1.4)),
        const SizedBox(height: 20),
        PasswordField(controller: _pw, label: tr('password'), autofocus: true),
        const SizedBox(height: 12),
        PasswordField(controller: _pw2, label: tr('password_repeat'), error: _error, onSubmitted: (_) => _create()),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _busy ? null : _create,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
          child: _busy
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                    const SizedBox(width: 12),
                    Text(tr('deriving_key')),
                  ],
                )
              : Text(tr('create_diary')),
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: _busy
              ? null
              : () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const RestoreScreen())),
          icon: const Icon(Icons.cloud_download_rounded),
          label: Text(tr('restore_from_git')),
        ),
      ],
    );
  }
}

class LockScreen extends StatefulWidget {
  const LockScreen({super.key});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  final _pw = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _biometric());
  }

  Future<void> _biometric() async {
    final app = context.read<AppState>();
    if (!app.prefs.biometric) return;
    setState(() => _busy = true);
    final ok = await app.unlockWithBiometrics();
    if (!ok && mounted) setState(() => _busy = false);
  }

  Future<void> _unlock() async {
    if (_pw.text.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await context.read<AppState>().unlock(_pw.text);
    if (!ok && mounted) {
      setState(() {
        _busy = false;
        _error = tr('wrong_password');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bio = context.select<AppState, bool>((a) => a.prefs.biometric);
    return _Frame(
      children: [
        const _Brand(),
        const SizedBox(height: 40),
        PasswordField(
          controller: _pw,
          label: tr('password'),
          error: _error,
          autofocus: !bio,
          onSubmitted: (_) => _unlock(),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _busy ? null : _unlock,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
          child: _busy
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                    const SizedBox(width: 12),
                    Text(tr('deriving_key')),
                  ],
                )
              : Text(tr('unlock')),
        ),
        if (bio) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _busy ? null : _biometric,
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
            icon: const Icon(Icons.fingerprint_rounded),
            label: Text(tr('unlock_biometric')),
          ),
        ],
      ],
    );
  }
}

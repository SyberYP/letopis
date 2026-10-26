import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show DateUtils;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/crypto.dart';
import '../core/entry.dart';
import '../core/store.dart';
import '../core/vault.dart';
import '../l10n/strings.dart';
import '../services/ai_tagger.dart';
import '../services/git_remote.dart';
import '../services/sync.dart';
import '../services/webdav_remote.dart';

/// Settings that must work before unlock (theme, language, lock behaviour). Not secret.
class Prefs {
  Prefs({
    this.themeMode = ThemeModeSetting.system,
    this.accent = 0,
    this.language = 'ru',
    this.autoLockSeconds = 60,
    this.biometric = false,
    this.secureScreen = true,
    this.tiles = false,
  });

  ThemeModeSetting themeMode;
  int accent;
  String language;
  int autoLockSeconds;
  bool biometric;
  bool secureScreen;

  /// Timeline as a grid of tiles instead of a list of cards.
  bool tiles;

  static Future<Prefs> load() async {
    final p = await SharedPreferences.getInstance();
    return Prefs(
      themeMode: ThemeModeSetting.values[(p.getInt('theme') ?? 0).clamp(0, 2)],
      accent: p.getInt('accent') ?? 0,
      language: p.getString('lang') ?? _systemLanguage(),
      autoLockSeconds: p.getInt('autolock') ?? 60,
      biometric: p.getBool('biometric') ?? false,
      secureScreen: p.getBool('secure') ?? true,
      tiles: p.getBool('tiles') ?? false,
    );
  }

  static String _systemLanguage() {
    final code = PlatformDispatcher.instance.locale.languageCode;
    return code == 'ru' || code == 'uk' || code == 'be' ? 'ru' : 'en';
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setInt('theme', themeMode.index);
    await p.setInt('accent', accent);
    await p.setString('lang', language);
    await p.setInt('autolock', autoLockSeconds);
    await p.setBool('biometric', biometric);
    await p.setBool('secure', secureScreen);
    await p.setBool('tiles', tiles);
  }
}

enum ThemeModeSetting { system, light, dark }

enum SyncStatus { idle, running, ok, error }

/// Platform pieces behind one seam so widget tests can replace them.
class DeviceServices {
  Future<bool> canUseBiometrics() async {
    try {
      final auth = LocalAuthentication();
      return await auth.isDeviceSupported() && await auth.canCheckBiometrics;
    } catch (_) {
      return false;
    }
  }

  Future<bool> authenticate(String reason) async {
    try {
      return await LocalAuthentication().authenticate(localizedReason: reason);
    } catch (_) {
      return false;
    }
  }

  static const _secure = FlutterSecureStorage();
  Future<String?> readSecret(String key) => _secure.read(key: key);
  Future<void> writeSecret(String key, String value) => _secure.write(key: key, value: value);
  Future<void> deleteSecret(String key) => _secure.delete(key: key);

  static const _channel = MethodChannel('letopis/secure');
  Future<void> setSecureScreen(bool on) async {
    try {
      await _channel.invokeMethod('setSecure', on);
    } catch (_) {
      // not on Android
    }
  }

  Future<Directory> dataDir() async => Directory('${(await getApplicationSupportDirectory()).path}/letopis');
  Future<Directory> tempDir() async => Directory('${(await getTemporaryDirectory()).path}/letopis_open');

  String get deviceName => Platform.isAndroid ? 'Android' : Platform.operatingSystem;
}

class AppState extends ChangeNotifier with WidgetsBindingObserver {
  AppState({DeviceServices? platform, this.kdf = const KdfParams()}) : platform = platform ?? DeviceServices();

  final DeviceServices platform;
  final KdfParams kdf;

  late Prefs prefs;

  /// App version for the About section, e.g. `1.1.0 (3)`.
  String version = '';

  /// Build number (`versionCode`), compared with the download site by the update check.
  int buildNumber = 0;
  late Directory root;
  late Directory temp;
  bool ready = false;

  VaultFile? vault;
  EntryStore? store;
  AiConfig ai = const AiConfig();
  GitHubConfig git = const GitHubConfig();
  WebDavConfig dav = const WebDavConfig();

  /// One sync target at a time: the cloud folder if connected, otherwise GitHub.
  SyncConfig? get syncTarget => dav.isConfigured ? dav : (git.isConfigured ? git : null);

  static RemoteRepo remoteFor(SyncConfig c) => c is WebDavConfig ? WebDavRepo(c) : GitHubRepo(c as GitHubConfig);

  bool get hasVault => vault != null;
  bool get unlocked => store != null;

  int _revision = 0;

  /// Bumped on every data change; widgets use it to rebuild cached lists.
  int get revision => _revision;

  // ---- lifecycle ---------------------------------------------------------------------------

  Future<void> init({Prefs? withPrefs, Directory? dataDir, Directory? tempDir}) async {
    prefs = withPrefs ?? await Prefs.load();
    try {
      final info = await PackageInfo.fromPlatform();
      version = '${info.version} (${info.buildNumber})';
      buildNumber = int.tryParse(info.buildNumber) ?? 0;
    } catch (_) {
      // tests and unsupported platforms
    }
    Lang.code = prefs.language;
    root = dataDir ?? await platform.dataDir();
    temp = tempDir ?? await platform.tempDir();
    await root.create(recursive: true);
    vault = await EntryStore.readVault(root);
    await platform.setSecureScreen(prefs.secureScreen);
    // Leftovers of a crash while unlocked.
    if (await temp.exists()) await temp.delete(recursive: true);
    WidgetsBinding.instance.addObserver(this);
    ready = true;
    notifyListeners();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  DateTime? _pausedAt;
  Timer? _lockTimer;
  int _suspend = 0;

  /// Keeps the diary open while a system picker or camera is in front (the app is "paused").
  Future<T> keepUnlocked<T>(Future<T> Function() action) async {
    _suspend++;
    try {
      return await action();
    } finally {
      // The resume event arrives right after the picker closes.
      Future.delayed(const Duration(seconds: 2), () => _suspend--);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!unlocked) return;
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      if (_suspend > 0) return;
      _pausedAt ??= DateTime.now();
      _lockTimer?.cancel();
      if (prefs.autoLockSeconds == 0) {
        lock();
      } else {
        _lockTimer = Timer(Duration(seconds: prefs.autoLockSeconds), lock);
      }
    } else if (state == AppLifecycleState.resumed) {
      _lockTimer?.cancel();
      final at = _pausedAt;
      _pausedAt = null;
      if (at != null && DateTime.now().difference(at).inSeconds >= prefs.autoLockSeconds) lock();
    }
  }

  // ---- vault -------------------------------------------------------------------------------

  Future<void> createVault(String password) async {
    final (v, box) = await VaultFile.create(password, kdf: kdf);
    await EntryStore.writeVault(root, v);
    vault = v;
    await _open(box);
  }

  /// Returns false on a wrong password.
  Future<bool> unlock(String password) async {
    try {
      final box = await vault!.unlock(password);
      await _open(box);
      return true;
    } on WrongPasswordException {
      return false;
    }
  }

  String get _bioKey => 'dek_${vault!.id}';

  Future<bool> unlockWithBiometrics() async {
    if (!prefs.biometric || vault == null) return false;
    if (!await platform.authenticate(tr('biometric_reason'))) return false;
    final stored = await platform.readSecret(_bioKey);
    if (stored == null) return false;
    final box = await vault!.unlockWithKey(base64.decode(stored));
    if (box == null) return false;
    await _open(box);
    return true;
  }

  Future<bool> setBiometric(bool on) async {
    if (on) {
      if (!await platform.canUseBiometrics()) return false;
      if (!await platform.authenticate(tr('biometric_reason'))) return false;
      await platform.writeSecret(_bioKey, base64.encode(store!.box.keyBytes));
    } else {
      await platform.deleteSecret(_bioKey);
    }
    prefs.biometric = on;
    await prefs.save();
    notifyListeners();
    return true;
  }

  Future<bool> changePassword(String current, String next) async {
    try {
      final check = await vault!.unlock(current);
      check.wipe();
    } on WrongPasswordException {
      return false;
    }
    final v = await vault!.rewrap(store!.box, next);
    await EntryStore.writeVault(root, v);
    vault = v;
    _scheduleAutoSync();
    return true;
  }

  Future<void> _open(CryptoBox box) async {
    final s = EntryStore(root, box, tempDir: temp);
    await s.load();
    final settings = await s.readJson('settings');
    ai = AiConfig.fromJson(settings?['ai'] as Map<String, dynamic>?);
    git = GitHubConfig.fromJson(settings?['git'] as Map<String, dynamic>?);
    dav = WebDavConfig.fromJson(settings?['dav'] as Map<String, dynamic>?);
    store = s;
    _revision++;
    notifyListeners();
  }

  /// Called before the key is wiped: open editors save their text here.
  final List<Future<void> Function()> beforeLock = [];

  Future<void> lock() async {
    _lockTimer?.cancel();
    _syncTimer?.cancel();
    if (store == null) return;
    for (final f in List.of(beforeLock)) {
      try {
        await f();
      } catch (_) {
        // locking must not fail
      }
    }
    final s = store;
    if (s == null) return;
    // A stuck disk must not keep the diary open: wait a little, then lock anyway.
    await Future.wait(List.of(_writes)).timeout(const Duration(seconds: 5), onTimeout: () => const []);
    try {
      await s.flushIndex();
    } catch (_) {
      // the index is only a cache
    }
    store = null;
    s.clearTemp();
    s.box.wipe();
    ai = const AiConfig();
    git = const GitHubConfig();
    dav = const WebDavConfig();
    notifyListeners();
  }

  /// Replaces the local diary with one restored from GitHub.
  Future<String?> restoreFromGit(GitHubConfig config, String password) => restore(config, password);

  /// Replaces the local diary with one restored from GitHub or a cloud folder.
  Future<String?> restore(SyncConfig config, String password) async {
    final repo = remoteFor(config);
    final snap = await repo.snapshot();
    final prefix = config.dir.isEmpty ? '' : '${config.dir}/';
    final sha = snap.files['${prefix}vault.json'];
    if (sha == null) return 'restore_no_vault';
    final v = VaultFile.decode(utf8.decode(await repo.readBlob(sha)));
    final CryptoBox box;
    try {
      box = await v.unlock(password);
    } on WrongPasswordException {
      return 'wrong_password';
    }
    await EntryStore.writeVault(root, v);
    vault = v;
    await _open(box);
    if (config is WebDavConfig) {
      dav = config;
    } else {
      git = config as GitHubConfig;
    }
    await saveSettings();
    try {
      await syncNow();
    } catch (_) {
      // The status line shows the error; the diary itself is open.
    }
    return null;
  }

  // ---- settings ----------------------------------------------------------------------------

  Future<void> saveSettings() async {
    await store?.writeJson('settings', {'ai': ai.toJson(), 'git': git.toJson(), 'dav': dav.toJson()});
    notifyListeners();
  }

  Future<void> updatePrefs(void Function(Prefs p) change) async {
    change(prefs);
    Lang.code = prefs.language;
    await prefs.save();
    await platform.setSecureScreen(prefs.secureScreen);
    notifyListeners();
  }

  // ---- entries -----------------------------------------------------------------------------

  List<Entry> get entries => store?.entries ?? const [];

  /// Store writes still running; [lock] waits for them so the key is never wiped mid-write.
  final Set<Future<void>> _writes = {};

  /// True while an entry is being written.
  bool get busy => _writes.isNotEmpty;

  Future<T> _write<T>(Future<T> Function(EntryStore s) op) async {
    final s = store;
    if (s == null) throw StateError('vault is locked');
    final f = op(s);
    final done = f.then<void>((_) {}, onError: (_) {});
    _writes.add(done);
    try {
      final r = await f;
      _changed();
      return r;
    } finally {
      _writes.remove(done);
    }
  }

  Future<void> saveEntry(Entry e) => _write((s) => s.save(e));

  /// Moves an entry to the trash ([toTrash] false deletes it for good, e.g. an emptied draft).
  Future<void> deleteEntry(String id, {bool toTrash = true}) => _write((s) => s.delete(id, toTrash: toTrash));

  Future<Entry?> restoreEntry(String id) => _write((s) => s.restore(id));

  Future<void> purgeEntry(String id) => _write((s) => s.purge(id));

  Future<void> emptyTrash() => _write((s) => s.emptyTrash());

  /// Saves several entries (import) with one notification.
  Future<void> saveAll(Iterable<Entry> list) => _write((s) async {
    for (final e in list) {
      await s.save(e, touch: false);
    }
  });

  void _changed() {
    _revision++;
    notifyListeners();
    _scheduleAutoSync();
  }

  List<String> get knownTags => [for (final t in store?.tagCounts() ?? const []) t.key];

  /// Days in a row with at least one entry, ending today or yesterday.
  int get streak {
    final days = {for (final e in entries) DateUtils.dateOnly(e.created)};
    var day = DateUtils.dateOnly(DateTime.now());
    if (!days.contains(day)) day = day.subtract(const Duration(days: 1));
    var n = 0;
    while (days.contains(day)) {
      n++;
      day = DateTime(day.year, day.month, day.day - 1);
    }
    return n;
  }

  /// Entries from the same day and month in earlier years.
  List<Entry> onThisDay([DateTime? now]) {
    final d = now ?? DateTime.now();
    return [
      for (final e in entries)
        if (e.created.month == d.month && e.created.day == d.day && e.created.year < d.year) e,
    ];
  }

  // ---- AI ----------------------------------------------------------------------------------

  Future<List<String>> suggestTags(Entry e) => AiTagger(ai).suggest(e, knownTags);

  /// "Suggest tags on save": adds AI tags to an entry that has none, in the background.
  Future<void> autoTag(String entryId) async {
    if (!ai.autoTag || !ai.consented || !ai.isConfigured) return;
    final e = store?.byId(entryId);
    if (e == null || e.allTags.isNotEmpty || e.body.trim().length < 20) return;
    try {
      final tags = await suggestTags(e);
      final current = store?.byId(entryId);
      if (current == null || tags.isEmpty) return;
      current.tags = [...current.tags, ...tags.take(5)];
      await saveEntry(current);
    } catch (_) {
      // best effort
    }
  }

  // ---- sync --------------------------------------------------------------------------------

  SyncStatus syncStatus = SyncStatus.idle;
  String syncMessage = '';
  DateTime? lastSync;
  Timer? _syncTimer;

  void _scheduleAutoSync() {
    final t = syncTarget;
    if (t == null || !t.autoSync) return;
    _syncTimer?.cancel();
    _syncTimer = Timer(const Duration(seconds: 20), () => syncNow());
  }

  /// Runs a sync; returns the report or throws [SyncException].
  Future<SyncReport?> syncNow() async {
    final s = store;
    final target = syncTarget;
    if (s == null || target == null || syncStatus == SyncStatus.running) return null;
    syncStatus = SyncStatus.running;
    notifyListeners();
    try {
      final report = await SyncEngine(
        store: s,
        remote: remoteFor(target),
        config: target,
        device: platform.deviceName,
      ).run();
      if (report.vaultChanged) vault = await EntryStore.readVault(root);
      syncStatus = SyncStatus.ok;
      syncMessage = report.nothing ? tr('sync_nothing') : tr('sync_done', {'report': '$report'});
      lastSync = DateTime.now();
      _revision++;
      notifyListeners();
      return report;
    } on SyncException catch (e) {
      syncStatus = SyncStatus.error;
      syncMessage = switch (e.code) {
        'other_vault' => tr('sync_other_vault'),
        'public_repo' => tr('sync_public_repo'),
        _ => tr('sync_error', {'error': e.detail}),
      };
      notifyListeners();
      rethrow;
    } catch (e) {
      syncStatus = SyncStatus.error;
      syncMessage = tr('sync_error', {'error': '$e'});
      notifyListeners();
      rethrow;
    }
  }

  Future<DateTime?> loadLastSync() async {
    final s = await store?.readJson('sync');
    return lastSync ?? DateTime.tryParse('${s?['last']}');
  }
}

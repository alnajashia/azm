/// Dart-domain configuration repositories (ARCH §8.2).
///
/// These stores hold UI/domain configuration — browser blocklists, focus
/// and impulse config, challenge selection, usage-warning stages, forced
/// removal state — persisted in the native SharedPreferences files through
/// the channel's allowlisted `getSetting`/`setSetting`, mirroring the
/// original's storage shapes under the same keys (StringSets stay
/// StringSets, the original's JSON encodings are kept byte-compatible).
/// Enforcement state (limits, windows, groups, words, logs) goes through
/// the typed channel methods instead.
library;

import 'dart:convert';

import '../domain/challenges.dart';
import '../domain/entry_grace.dart';
import '../domain/entry_password.dart';
import '../domain/focus.dart';
import '../domain/recovery.dart';
import 'dns_protection.dart';
import 'privileged_channel.dart';

class BlockedList {
  const BlockedList({required this.id, required this.title, this.sites = const []});
  final String id;
  final String title;
  final List<String> sites;

  Map<String, dynamic> toJson() => {'id': id, 'title': title, 'sites': sites};
  factory BlockedList.fromJson(Map<String, dynamic> j) => BlockedList(
        id: j['id'] as String,
        title: j['title'] as String? ?? '',
        sites: (j['sites'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      );
  BlockedList copyWith({String? title, List<String>? sites}) =>
      BlockedList(id: id, title: title ?? this.title, sites: sites ?? this.sites);
}

/// A user-written reading passage, mirroring the original
/// `ReadingPassage(text, source)` (`data/ReadingPassages.kt`). Custom
/// passages are stored under `reading_custom_passages` as a JSON array
/// of `{"text": ..., "source": ...}` objects — the original's shape
/// (`SecurityManager.kt` L209–229).
class ReadingPassage {
  const ReadingPassage(this.text, {this.source = ''});
  final String text;
  final String source;

  Map<String, dynamic> toJson() => {'text': text, 'source': source};
  factory ReadingPassage.fromJson(Map<String, dynamic> j) => ReadingPassage(
        j['text'] as String? ?? '',
        source: j['source'] as String? ?? '',
      );
}

/// Where the reading challenge takes its texts from — the original
/// `SecurityManager.ReadingSource`, stored under `reading_source` as the
/// enum name (`BIBLE` by default).
enum ReadingSource { bible, quran, quotes, custom }

enum ImpulseAction { timerOnly, timerAndSuspend }

class ImpulseConfig {
  const ImpulseConfig({
    // The original's default action is TIMER_ONLY
    // (`SecurityManager.getImpulseAction` falls back to it both when
    // unset and when the stored name is unrecognised).
    this.action = ImpulseAction.timerOnly,
    this.durationMinutes = 60,
    this.suspendApps = const [],
  });
  final ImpulseAction action;
  final int durationMinutes;
  final List<String> suspendApps;

  Map<String, dynamic> toJson() => {
        'action': action.name,
        'durationMinutes': durationMinutes,
        'suspendApps': suspendApps,
      };
  factory ImpulseConfig.fromJson(Map<String, dynamic> j) => ImpulseConfig(
        action: ImpulseAction.values.firstWhere(
          (a) => a.name == j['action'],
          orElse: () => ImpulseAction.timerOnly,
        ),
        durationMinutes: (j['durationMinutes'] as num?)?.toInt() ?? 60,
        suspendApps:
            (j['suspendApps'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      );
  ImpulseConfig copyWith({ImpulseAction? action, int? durationMinutes, List<String>? suspendApps}) =>
      ImpulseConfig(
        action: action ?? this.action,
        durationMinutes: durationMinutes ?? this.durationMinutes,
        suspendApps: suspendApps ?? this.suspendApps,
      );
}

enum UsageWarningType { silent, sound, vibrate }

/// One usage-warning stage, mirroring the original `UsageAlertStage`
/// and its JSON encoding (`UsageWarningSettings.encodeStages`):
/// `{"id": ..., "minutes": ..., "type": "SILENT"|"SOUND"|"VIBRATE",
/// "vibrationCount": ...}` — the type is stored under the original's
/// uppercase enum name. Values written by the previous Dart schema
/// (lowercase type names, no `id`) are still parsed. Bounds mirror the
/// original: minutes 0.1–180 (`MIN/MAX_MINUTES_BEFORE`),
/// vibrationCount ≤ 10 (`MAX_VIBRATION_COUNT`).
class UsageWarningStage {
  const UsageWarningStage({
    this.id = '',
    required this.minutesBefore,
    required this.type,
    this.vibrationCount = 0,
  });

  /// Stable stage identifier (the original generates a UUID when
  /// seeding). Empty until the stage has been through [ConfigStore],
  /// which assigns one — see `ConfigStore._withStageIds`.
  final String id;
  final double minutesBefore;
  final UsageWarningType type;
  final int vibrationCount;

  Map<String, dynamic> toJson() => {
        'id': id,
        'minutes': minutesBefore,
        'type': type.name.toUpperCase(),
        'vibrationCount': vibrationCount,
      };

  factory UsageWarningStage.fromJson(Map<String, dynamic> j) => UsageWarningStage(
        id: j['id'] as String? ?? '',
        minutesBefore: ((j['minutes'] as num?)?.toDouble() ?? 0).clamp(0.1, 180.0).toDouble(),
        type: UsageWarningType.values.firstWhere(
          // Accepts the original's uppercase names and the previous
          // schema's lowercase ones.
          (t) => t.name == (j['type'] as String?)?.toLowerCase(),
          // The original's decoder falls back to SOUND on unknown types.
          orElse: () => UsageWarningType.sound,
        ),
        vibrationCount: ((j['vibrationCount'] as num?)?.toInt() ?? 0).clamp(0, 10),
      );

  UsageWarningStage copyWith({
    String? id,
    double? minutesBefore,
    UsageWarningType? type,
    int? vibrationCount,
  }) =>
      UsageWarningStage(
        id: id ?? this.id,
        minutesBefore: minutesBefore ?? this.minutesBefore,
        type: type ?? this.type,
        vibrationCount: vibrationCount ?? this.vibrationCount,
      );
}

/// The original's defaults: 15 min silent, 5 min sound, 1 min vibrate×1,
/// 0.5 min vibrate×3 (`UsageWarningSettings.defaultStages`). The
/// original assigns each a fresh UUID when seeding; here the ids are
/// left empty and assigned by [ConfigStore] on first read/write.
const defaultUsageWarningStages = <UsageWarningStage>[
  UsageWarningStage(minutesBefore: 15, type: UsageWarningType.silent),
  UsageWarningStage(minutesBefore: 5, type: UsageWarningType.sound),
  UsageWarningStage(minutesBefore: 1, type: UsageWarningType.vibrate, vibrationCount: 1),
  UsageWarningStage(minutesBefore: 0.5, type: UsageWarningType.vibrate, vibrationCount: 3),
];

class ConfigStore {
  ConfigStore(this._channel);

  final PrivilegedChannel _channel;

  static const security = 'security_prefs';
  static const browser = 'browser_prefs';
  static const focus = 'focus_prefs';
  static const usageWarning = 'usage_warning_prefs';
  static const recoveryState = 'recovery_prefs';

  Future<Map<String, dynamic>?> _getJson(String store, String key) async {
    final raw = await _channel.getSetting(store, key);
    if (raw is String && raw.isNotEmpty) {
      final decoded = jsonDecode(raw);
      if (decoded is Map) return decoded.cast<String, dynamic>();
    }
    return null;
  }

  Future<void> _setJson(String store, String key, Object? value) =>
      _channel.setSetting(store, key, value == null ? null : jsonEncode(value));

  // ------------------------------------------------------------ challenges

  /// The original stores `access_challenges` as a SharedPreferences
  /// **StringSet** of enum names (`MATH`, `WORDS`, `TETRIS`, `READING`)
  /// (`SecurityManager.getAccessChallenges`). The channel persists a
  /// Dart `List<String>` as exactly that StringSet, so reads accept the
  /// List form; values left by the previous Dart schema (a JSON string
  /// of lowercase names under the same key) are parsed case-insensitively
  /// and migrated to the StringSet shape on read.
  Future<List<ChallengeType>> getChallengeSelection() async {
    final raw = await _channel.getSetting(security, 'access_challenges');
    List<String>? names;
    var legacyJson = false;
    if (raw is List) {
      names = raw.map((e) => e.toString()).toList();
    } else if (raw is String && raw.isNotEmpty) {
      legacyJson = true;
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) names = decoded.map((e) => e.toString()).toList();
      } catch (_) {
        names = null;
      }
    }
    if (names == null) return const [ChallengeType.math];
    final nameList = names;
    final selected = ChallengeType.values
        .where((t) => nameList.any((n) => n.toLowerCase() == t.name))
        .toList();
    if (selected.isEmpty) return const [ChallengeType.math];
    if (legacyJson) {
      // Best-effort migration to the original's StringSet shape; the
      // parsed selection above is returned either way.
      try {
        await setChallengeSelection(selected);
      } catch (_) {
        // The stored value is left as-is; the next write fixes it.
      }
    }
    return selected;
  }

  Future<void> setChallengeSelection(List<ChallengeType> types) => _channel.setSetting(
      security, 'access_challenges', types.map((t) => t.name.toUpperCase()).toList());

  /// Tetris (Batch I-C, item 2): the original's `SecurityManager`
  /// keys `tetris_minutes` (1–15, default 3) and `tetris_sound`
  /// (default on), stored as a plain int / bool in `security_prefs`
  /// via the generic channel settings.
  static const tetrisMinMinutes = 1;
  static const tetrisMaxMinutes = 15;
  static const tetrisDefaultMinutes = 3;

  Future<int> getTetrisMinutes() async {
    final raw = await _channel.getSetting(security, 'tetris_minutes');
    final minutes = raw is int
        ? raw
        : (raw is String ? int.tryParse(raw) : null);
    return (minutes ?? tetrisDefaultMinutes)
        .clamp(tetrisMinMinutes, tetrisMaxMinutes);
  }

  Future<void> setTetrisMinutes(int minutes) => _channel.setSetting(
        security,
        'tetris_minutes',
        minutes.clamp(tetrisMinMinutes, tetrisMaxMinutes),
      );

  Future<bool> isTetrisSoundEnabled() async {
    final raw = await _channel.getSetting(security, 'tetris_sound');
    if (raw is bool) return raw;
    if (raw is String) return raw.toLowerCase() != 'false';
    return true;
  }

  Future<void> setTetrisSoundEnabled(bool enabled) =>
      _channel.setSetting(security, 'tetris_sound', enabled);

  /// Custom reading passages in the original's `{text, source}` object
  /// shape. Entries written by the previous Dart schema (plain strings
  /// in the same JSON array) are read as passages with an empty source
  /// and upgraded to objects on the next write.
  Future<List<ReadingPassage>> getCustomReadingPassages() async {
    final raw = await _channel.getSetting(security, 'reading_custom_passages');
    if (raw is String && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          return decoded
              .map((e) => e is Map
                  ? ReadingPassage.fromJson(e.cast<String, dynamic>())
                  : ReadingPassage(e.toString()))
              .toList();
        }
      } catch (_) {
        return const [];
      }
    }
    return const [];
  }

  Future<void> setCustomReadingPassages(List<ReadingPassage> passages) =>
      _channel.setSetting(security, 'reading_custom_passages',
          jsonEncode(passages.map((p) => p.toJson()).toList()));

  Future<List<String>> getCustomReadingPhrases() async =>
      (await getCustomReadingPassages()).map((p) => p.text).toList();

  Future<void> setCustomReadingPhrases(List<String> phrases) => setCustomReadingPassages(
      phrases.map((p) => ReadingPassage(p)).toList());

  // ------------------------------------------------------------ reading

  /// The original's `reading_source` (`SecurityManager.getReadingSource`):
  /// the enum name as a String, BIBLE when unset or unrecognised.
  Future<ReadingSource> getReadingSource() async {
    final raw = await _channel.getSetting(security, 'reading_source');
    if (raw is String) {
      for (final source in ReadingSource.values) {
        if (source.name == raw.toLowerCase()) return source;
      }
    }
    return ReadingSource.bible;
  }

  Future<void> setReadingSource(ReadingSource source) =>
      _channel.setSetting(security, 'reading_source', source.name.toUpperCase());

  /// The original's `reading_count` (`SecurityManager.getReadingCount`):
  /// an int, `READING_DEFAULT_COUNT` = 5 when unset, never below
  /// `READING_MIN_COUNT` = 1.
  Future<int> getReadingCount() async {
    final raw = await _channel.getSetting(security, 'reading_count');
    final value = raw is num ? raw.toInt() : 5;
    return value < 1 ? 1 : value;
  }

  Future<void> setReadingCount(int count) =>
      _channel.setSetting(security, 'reading_count', count < 1 ? 1 : count);

  Future<bool> getShuffleKeyboard() async =>
      await _channel.getSetting(security, 'shuffle_keyboard') == true;

  Future<void> setShuffleKeyboard(bool v) =>
      _channel.setSetting(security, 'shuffle_keyboard', v);

  // ------------------------------------------------------------ impulse

  Future<ImpulseConfig> getImpulseConfig() async {
    final j = await _getJson(security, 'impulse_config');
    return j == null ? const ImpulseConfig() : ImpulseConfig.fromJson(j);
  }

  Future<void> setImpulseConfig(ImpulseConfig config) =>
      _setJson(security, 'impulse_config', config.toJson());

  Future<ImpulseLock> getImpulseLock() async {
    final j = await _getJson(security, 'impulse_lock');
    return j == null ? const ImpulseLock() : ImpulseLock.fromJson(j);
  }

  Future<void> setImpulseLock(ImpulseLock lock) =>
      _setJson(security, 'impulse_lock', lock.toJson());

  // ------------------------------------------------------------ focus

  Future<FocusConfig> getFocusConfig() async {
    final j = await _getJson(focus, 'config');
    // FocusConfig.fromJson clamps every value into the original's
    // bounds, as the original's getters do on read.
    return j == null ? const FocusConfig() : FocusConfig.fromJson(j);
  }

  Future<void> setFocusConfig(FocusConfig config) =>
      _setJson(focus, 'config', config.normalized().toJson());

  // ------------------------------------------------------------ browser lists

  Future<List<BlockedList>> getBlockedLists() async {
    final raw = await _channel.getSetting(browser, 'blocked_lists_json');
    if (raw is String && raw.isNotEmpty) {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .map((e) => BlockedList.fromJson((e as Map).cast<String, dynamic>()))
            .toList();
      }
    }
    return const [];
  }

  Future<void> setBlockedLists(List<BlockedList> lists) => _channel.setSetting(
      browser, 'blocked_lists_json', jsonEncode(lists.map((l) => l.toJson()).toList()));

  // ------------------------------------------------------------ DNS protection

  /// DNS filtering for unsupported browsers (Batch DNS): the persisted
  /// selection behind the DNS card. Absent/corrupt JSON reads as the
  /// default (off, CleanBrowsing) — never as enabled.
  Future<DnsProtection> getDnsProtection() async {
    final raw = await _getJson(browser, 'dns_protection_json');
    if (raw == null) return const DnsProtection();
    try {
      return DnsProtection.fromJson(raw);
    } catch (_) {
      return const DnsProtection();
    }
  }

  Future<void> setDnsProtection(DnsProtection dns) =>
      _setJson(browser, 'dns_protection_json', dns.toJson());

  // ------------------------------------------------------------ torrent apps (Batch F, item 4)

  /// Packages the torrent toggle suspended. Kept so disabling the
  /// toggle unsuspends exactly the apps it blocked — never a package
  /// suspended by another feature. Corrupt/absent reads as empty.
  Future<Set<String>> getTorrentBlockedPackages() async {
    final raw = await _channel.getSetting(browser, 'torrent_blocked_json');
    if (raw is String && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          return decoded.map((e) => e.toString()).toSet();
        }
      } catch (_) {}
    }
    return const {};
  }

  Future<void> setTorrentBlockedPackages(Set<String> packages) =>
      _channel.setSetting(browser, 'torrent_blocked_json', jsonEncode(packages.toList()));

  // ------------------------------------------------------------ blocked groups (Batch F, items 7/9)

  /// IDs of groups the user blocked as a whole (group-block). The
  /// enforcement is per-package suspension; this set is the record of
  /// WHICH groups are blocked, so member edits and the list UI can
  /// tell a blocked group from a merely limited one. Corrupt/absent
  /// reads as empty.
  Future<Set<String>> getBlockedGroupIds() async {
    final raw = await _channel.getSetting(browser, 'blocked_groups_json');
    if (raw is String && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          return decoded.map((e) => e.toString()).toSet();
        }
      } catch (_) {}
    }
    return const {};
  }

  Future<void> setBlockedGroupIds(Set<String> ids) =>
      _channel.setSetting(browser, 'blocked_groups_json', jsonEncode(ids.toList()));

  // ------------------------------------------------------------ usage warnings

  static int _stageIdSeq = 0;

  /// The original seeds each stage with a `UUID.randomUUID()`; any
  /// unique opaque string satisfies the schema.
  static String _newStageId() =>
      'stage-${DateTime.now().microsecondsSinceEpoch}-${_stageIdSeq++}';

  static List<UsageWarningStage> _withStageIds(List<UsageWarningStage> stages) => [
        for (final s in stages) s.id.isEmpty ? s.copyWith(id: _newStageId()) : s,
      ];

  Future<({bool enabled, List<UsageWarningStage> stages})> getUsageWarnings() async {
    final rawEnabled = await _channel.getSetting(usageWarning, 'enabled');
    // The original's DEFAULT_ENABLED is true: only an explicitly stored
    // boolean overrides it.
    final enabled = rawEnabled is bool ? rawEnabled : true;
    final raw = await _channel.getSetting(usageWarning, 'stages');
    if (raw is String && raw.isNotEmpty) {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return (
          enabled: enabled,
          stages: _withStageIds(decoded
              .map((e) => UsageWarningStage.fromJson((e as Map).cast<String, dynamic>()))
              .toList()),
        );
      }
    }
    return (enabled: enabled, stages: _withStageIds(defaultUsageWarningStages));
  }

  Future<void> setUsageWarnings(bool enabled, List<UsageWarningStage> stages) async {
    await _channel.setSetting(usageWarning, 'enabled', enabled);
    await _channel.setSetting(usageWarning, 'stages',
        jsonEncode(_withStageIds(stages).map((s) => s.toJson()).toList()));
  }

  // ------------------------------------------------------------ forced removal

  Future<ForcedRemoval> getForcedRemoval() async {
    final j = await _getJson(recoveryState, 'forced_removal');
    return j == null ? const ForcedRemoval() : ForcedRemoval.fromJson(j);
  }

  Future<void> setForcedRemoval(ForcedRemoval value) =>
      _setJson(recoveryState, 'forced_removal', value.toJson());

  // ------------------------------------------------------ entry lock timing (Phase C)

  /// App-lock timing state (v1.0.6 Phase C): the chosen grace period
  /// and the persisted wall-clock moment of the last successful entry.
  /// Persisting the timestamp means process death and reboots cannot
  /// extend the grace; a future timestamp is clamped to expired by
  /// the decision function (`entryShouldRelock`).
  Future<({EntryGracePeriod period, DateTime? lastUnlockAt})>
  getEntryLockState() async {
    final j = await _getJson(security, 'entry_lock');
    final ms = (j?['lastUnlockMs'] as num?)?.toInt();
    return (
      period: EntryGracePeriod.fromName(j?['period'] as String?),
      lastUnlockAt: ms == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(ms),
    );
  }

  Future<void> setEntryGracePeriod(EntryGracePeriod period) async {
    final current = await getEntryLockState();
    await _setJson(security, 'entry_lock', {
      'period': period.name,
      'lastUnlockMs': current.lastUnlockAt?.millisecondsSinceEpoch,
    });
  }

  Future<void> setEntryLastUnlock(DateTime at) async {
    final current = await getEntryLockState();
    await _setJson(security, 'entry_lock', {
      'period': current.period.name,
      'lastUnlockMs': at.millisecondsSinceEpoch,
    });
  }

  // ------------------------------------------------------ entry password

  /// The stored entry-password record (salted PBKDF2 hash only), or null
  /// when no entry password is set. See `domain/entry_password.dart` for
  /// the security model: the password opens the app, nothing more.
  Future<EntryPasswordHash?> getEntryPassword() async {
    final j = await _getJson(security, 'entry_password');
    if (j == null) return null;
    try {
      return EntryPasswordHash.fromJson(j);
    } catch (_) {
      // Verification treats a corrupt record as "no password" rather
      // than crashing the lock screen — but it is NOT silently the same
      // as unset: [getEntryPasswordRecordState] reports it as corrupt
      // so the Config UI can surface it (v1.0.5 audit B-9). Setting a
      // new password overwrites the corrupt record.
      return null;
    }
  }

  /// Whether an entry-password record exists and parses, exists but is
  /// corrupt, or does not exist at all (v1.0.5 audit B-9).
  Future<EntryPasswordRecordState> getEntryPasswordRecordState() async {
    final j = await _getJson(security, 'entry_password');
    if (j == null) return EntryPasswordRecordState.unset;
    try {
      EntryPasswordHash.fromJson(j);
      return EntryPasswordRecordState.set;
    } catch (_) {
      return EntryPasswordRecordState.corrupt;
    }
  }

  Future<bool> isEntryPasswordSet() async =>
      (await getEntryPassword()) != null;

  // ------------------------------------------------- anti-guess throttle

  /// The persisted entry-password failure count and the wall-clock time
  /// of the most recent failure (v1.0.5 audit B-3). Persisting both is
  /// what makes the anti-guess delay cumulative: dismissing the prompt
  /// or killing the app no longer resets it, and a prompt opened inside
  /// the delay window waits out the remainder.
  Future<({int failures, DateTime? lastFailure})>
      getEntryPasswordThrottle() async {
    final j = await _getJson(security, 'entry_password_throttle');
    if (j == null) return (failures: 0, lastFailure: null);
    final failures = (j['failures'] as num?)?.toInt() ?? 0;
    final lastMs = (j['lastFailureMs'] as num?)?.toInt();
    return (
      failures: failures < 0 ? 0 : failures,
      lastFailure:
          lastMs == null ? null : DateTime.fromMillisecondsSinceEpoch(lastMs),
    );
  }

  /// Records one more consecutive wrong attempt and returns the new
  /// count. Called only for genuine wrong-password results — never for
  /// verification errors (v1.0.5 audit C-M2).
  Future<int> recordEntryPasswordFailure() async {
    final current = await getEntryPasswordThrottle();
    final next = current.failures + 1;
    await _setJson(security, 'entry_password_throttle', {
      'failures': next,
      'lastFailureMs': DateTime.now().millisecondsSinceEpoch,
    });
    return next;
  }

  /// Clears the failure count after a successful verification, or when
  /// the password is set/changed/removed.
  Future<void> resetEntryPasswordThrottle() =>
      _setJson(security, 'entry_password_throttle', null);

  /// The anti-guess wait still owed right now: the delay for the
  /// persisted failure count minus the time already waited since the
  /// last failure (zero when no wait is owed).
  Future<Duration> entryPasswordWaitRemaining() async {
    final throttle = await getEntryPasswordThrottle();
    final delay = entryPasswordDelaySeconds(throttle.failures);
    final last = throttle.lastFailure;
    if (delay == 0 || last == null) return Duration.zero;
    final elapsed = DateTime.now().difference(last);
    final remaining = Duration(seconds: delay) - elapsed;
    return remaining.isNegative ? Duration.zero : remaining;
  }

  /// Sets (or replaces) the entry password, storing only its salted
  /// hash. Enforces the minimum length; callers surface the
  /// [ArgumentError] as user feedback.
  Future<void> setEntryPassword(
    String password, {
    int iterations = EntryPasswordHash.standardIterations,
  }) async {
    if (password.length < entryPasswordMinLength) {
      // Deliberately NOT ArgumentError.value: the exception may surface
      // in an error snackbar, and the attempted password must never be
      // echoed anywhere.
      throw ArgumentError(
        'Entry password must be at least $entryPasswordMinLength characters',
      );
    }
    final hash = EntryPasswordHash.create(password, iterations: iterations);
    await _setJson(security, 'entry_password', hash.toJson());
    // A fresh password starts with a clean throttle slate.
    await resetEntryPasswordThrottle();
  }

  /// Verifies [password] against the stored hash. False when no
  /// password is set.
  Future<bool> verifyEntryPassword(String password) async {
    final stored = await getEntryPassword();
    if (stored == null) return false;
    return stored.verify(password);
  }

  Future<void> removeEntryPassword() async {
    await _channel.setSetting(security, 'entry_password', null);
    await resetEntryPasswordThrottle();
  }

  // ------------------------------------------------------------ language & theme

  /// The user's explicitly saved UI language ('ar' or 'en'), or null
  /// when they have never picked one — in which case the controller
  /// falls back to the device locale (Arabic/English, else English).
  /// Values saved by older builds (e.g. 'pt') count as "never picked".
  Future<String?> getSavedLanguage() async {
    final v = await _channel.getSetting(security, 'language');
    return v is String && (v == 'ar' || v == 'en') ? v : null;
  }

  Future<void> setLanguage(String language) =>
      _channel.setSetting(security, 'language', language);
}

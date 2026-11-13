/// App-wide controller: startup routing (F31), the recovery session (F23),
/// language (F33), and the persisted long-running timers (impulse lock F21,
/// forced removal F2).
///
/// Timer accounting note (honest limitation): the original accumulates
/// forced-removal / impulse time natively across reboots with
/// elapsedRealtime. This Dart model advances the timers only by
/// *measured* elapsed time while the app process is alive (a 30 s
/// ticker). The deltas are measured on the process **monotonic** clock
/// (a Stopwatch, via [MonotonicDelta]) — never on the wall clock — so
/// changing the device clock can neither shorten nor stretch a timer
/// (v1.0.5 audit B-1: previously the delta came from `DateTime.now()`,
/// and a +48 h clock jump would have completed forced removal at the
/// next tick). Time never advances while the app is dead, so a timer
/// can take longer than wall-clock — never shorter — which fails safe
/// for this product's threat model. Full reboot-proof native accounting
/// is future Kotlin work.
library;

import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';

import 'data/config_store.dart';
import 'data/privileged_channel.dart';
import 'domain/entry_grace.dart';
import 'domain/focus.dart';
import 'domain/recovery.dart';

/// The app's display version (matches `pubspec.yaml`'s versionName;
/// shown in the lock-screen footer).
const String kAppVersion = '1.0.0';

enum StartupState { loading, needsRecoverySetup, locked, unlocked, error }

class AppController extends ChangeNotifier {
  AppController({PrivilegedChannel? channel})
      : channel = channel ?? PrivilegedChannel() {
    config = ConfigStore(this.channel);
  }

  AppController.test(this.channel) {
    config = ConfigStore(channel);
    startup = StartupState.locked;
  }

  PrivilegedChannel channel;
  late final ConfigStore config;
  final RecoverySession session = RecoverySession();

  StartupState startup = StartupState.loading;
  Object? startupError;
  String language = 'en';
  ThemeMode themeMode = ThemeMode.system;

  PrivilegedEvent? lastEvent;
  StreamSubscription<PrivilegedEvent>? _eventSub;
  Timer? _ticker;
  final MonotonicDelta _tickDelta = MonotonicDelta();
  bool _tickRunning = false;
  ImpulseLock impulseLock = const ImpulseLock();
  ForcedRemoval forcedRemoval = const ForcedRemoval();

  /// The forced-removal delay in force. The authoritative value is
  /// native (RecoveryStore.FORCED_REMOVAL_DELAY_HOURS) and arrives via
  /// the channel's owner state during [initialise]; until then the
  /// Dart bootstrap mirror (24 h) applies.
  Duration forcedRemovalDelay = ForcedRemoval.defaultTotal;

  /// App-lock timing (Phase C): the user's chosen entry grace period
  /// and the persisted moment of the last successful entry. Default
  /// is [EntryGracePeriod.immediately] — the pre-v1.0.6 strict
  /// behaviour — so existing users are never silently weakened.
  EntryGracePeriod entryGracePeriod = EntryGracePeriod.immediately;
  DateTime? entryLastUnlockAt;

  /// Device Owner removal in flight (Batch D Addendum): modal teardown &
  /// verification is active. Disables duplicate removal triggers and prevents
  /// the app from relocking when backgrounded during teardown.
  bool _isRemovingDeviceOwner = false;
  bool get isRemovingDeviceOwner => _isRemovingDeviceOwner;
  set isRemovingDeviceOwner(bool value) {
    if (_isRemovingDeviceOwner != value) {
      _isRemovingDeviceOwner = value;
      notifyListeners();
    }
  }

  /// The exact set of packages suspended when the current impulse lock
  /// started. The original records this as the "active impulse
  /// suspension" (`SecurityManager.setActiveImpulseSuspension`) and
  /// releases exactly that set when the block expires
  /// (`releaseImpulseSuspension`). Captured in [startImpulseLock];
  /// re-seeded in [initialise] for a lock that outlives the process
  /// (from the then-current config — impulse settings are
  /// session-gated, so the list can only have drifted through a
  /// recovery session).
  List<String> _impulseSuspendedApps = const [];

  Future<void> initialise() async {
    startup = StartupState.loading;
    notifyListeners();
    try {
      // Language (v1.0.4): the saved choice wins; until the user picks
      // one, default to the device locale — Arabic when the device is
      // Arabic, English otherwise (the app's only two UI languages).
      final savedLanguage = await config.getSavedLanguage();
      if (savedLanguage != null) {
        language = savedLanguage;
      } else {
        final device = PlatformDispatcher.instance.locale.languageCode;
        language = device == 'ar' ? 'ar' : 'en';
      }
      impulseLock = await config.getImpulseLock();
      if (impulseLock.active && !impulseLock.isComplete) {
        // A lock from a previous process is still running: re-seed the
        // recorded suspension set so its natural expiry releases the
        // same apps it suspended.
        final ic = await config.getImpulseConfig();
        if (ic.action == ImpulseAction.timerAndSuspend) {
          _impulseSuspendedApps = ic.suspendApps;
        }
      }
      forcedRemoval = await config.getForcedRemoval();
      // App-lock timing state (Phase C).
      final entryLock = await config.getEntryLockState();
      entryGracePeriod = entryLock.period;
      entryLastUnlockAt = entryLock.lastUnlockAt;
      // The forced-removal delay's native value, via the owner state.
      try {
        final owner = await channel.isDeviceOwner();
        final hours = owner.forcedRemovalDelayHours;
        if (hours != null && hours > 0) {
          forcedRemovalDelay = Duration(hours: hours);
          forcedRemoval = forcedRemoval.withTotal(forcedRemovalDelay);
        }
      } catch (_) {
        // Channel unavailable (widget tests, non-Android hosts): the
        // bootstrap mirror stays in force.
      }
      final isSet = await channel.isRecoveryCodeSet();
      startup = isSet ? StartupState.locked : StartupState.needsRecoverySetup;
      // Re-initialisation (the startup error screen's Retry) must not
      // stack a second subscription on the broadcast stream.
      await _eventSub?.cancel();
      _eventSub = channel.events.listen((e) {
        lastEvent = e;
        notifyListeners();
      });
      _startTicker();
    } catch (e) {
      startup = StartupState.error;
      startupError = e;
    }
    notifyListeners();
  }

  void _startTicker() {
    _ticker?.cancel();
    _tickDelta.reset(FocusSession.monotonicNow);
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) => _tick());
  }

  Future<void> _tick() async {
    // Re-entrancy + error containment (v1.0.5 audit B-12): a tick slower
    // than the 30 s period must not overlap the next one (both would
    // read/update the same timer state), and a channel/config failure
    // inside a tick must not surface as an unhandled async error. On
    // failure the in-memory advance is simply not persisted; the next
    // tick re-measures from the monotonic anchor, so time is lost —
    // never gained.
    if (_tickRunning) return;
    _tickRunning = true;
    try {
      final delta = _tickDelta.take(FocusSession.monotonicNow);
      var changed = false;
      if (impulseLock.active && !impulseLock.isComplete) {
        impulseLock = impulseLock.tick(delta);
        await config.setImpulseLock(impulseLock);
        changed = true;
        if (impulseLock.isComplete) {
          // Natural expiry: release exactly the apps this lock
          // suspended (the original releases its recorded impulse
          // suspension when the block ends).
          await _releaseImpulseSuspension();
        }
      }
      if (forcedRemoval.active && !forcedRemoval.isComplete) {
        forcedRemoval = forcedRemoval.advance(delta);
        await config.setForcedRemoval(forcedRemoval);
        changed = true;
      }
      if (changed) notifyListeners();
    } catch (_) {
      // Contained by design: see the note above.
    } finally {
      _tickRunning = false;
    }
  }

  /// Ends the active impulse lock early because the user completed the
  /// challenges they selected for Impulse Lock (v1.0.5 audit H-1 — the
  /// ONLY early-end path, reachable solely from the Impulse Lock
  /// screen's challenge runner; the recovery gate never runs
  /// challenges). Releases exactly the recorded impulse suspension,
  /// through the same [_releaseImpulseSuspension] the natural-expiry
  /// path uses, and persists the completed lock. No-op when no lock is
  /// running.
  Future<void> completeImpulseLockEarly() async {
    if (!impulseLock.active || impulseLock.isComplete) return;
    impulseLock = impulseLock.tick(impulseLock.remaining);
    await config.setImpulseLock(impulseLock);
    await _releaseImpulseSuspension();
    notifyListeners();
  }

  void onRecoverySetupComplete() {
    startup = StartupState.unlocked;
    notifyListeners();
  }

  void unlock() {
    if (startup == StartupState.locked) {
      startup = StartupState.unlocked;
      // Phase C: EVERY successful entry (fingerprint, app password,
      // device credential, no-credential fallback) funnels through
      // here, so this is the single place the grace period starts.
      // Failed attempts never reach this method — they start no
      // grace. Persistence is best-effort: the in-memory timestamp
      // still governs this process if the write fails.
      entryLastUnlockAt = DateTime.now();
      unawaited(
        config.setEntryLastUnlock(entryLastUnlockAt!).catchError((_) {}),
      );
      notifyListeners();
    }
  }

  /// Re-locks the app (Phase C): back to the entry gate. Called by
  /// the shell's lifecycle observer when the grace decision says the
  /// return needs a fresh entry. The recovery session is NOT touched
  /// — entry state and the paper-code gate are independent.
  void relock() {
    if (startup == StartupState.unlocked) {
      startup = StartupState.locked;
      notifyListeners();
    }
  }

  // --- Cross-tab navigation (v1.0.6, user item 13) ---

  /// Tab indices in shell order.
  static const int tabStatus = 0;
  static const int tabRestrictions = 1;
  static const int tabApps = 2;
  static const int tabConfig = 3;

  int? _requestedTab;

  /// A pending request to switch tabs (e.g. the Restrictions
  /// not-owner card sending the user to the Config tab, where
  /// provisioning lives). The shell consumes and clears it.
  int? get requestedTab => _requestedTab;

  void requestTab(int index) {
    _requestedTab = index;
    notifyListeners();
  }

  void clearTabRequest() {
    _requestedTab = null;
  }

  Future<void> setEntryGracePeriod(EntryGracePeriod period) async {
    entryGracePeriod = period;
    await config.setEntryGracePeriod(period);
    notifyListeners();
  }

  Future<void> setLanguage(String value) async {
    language = value;
    await config.setLanguage(value);
    notifyListeners();
  }

  void setThemeMode(ThemeMode mode) {
    themeMode = mode;
    notifyListeners();
  }

  Future<void> startImpulseLock(Duration duration) async {
    impulseLock = impulseLock.start(duration);
    await config.setImpulseLock(impulseLock);
    // Record exactly what the caller is about to suspend: both start
    // paths (Impulse screen, lock-screen panic button) suspend the
    // configured list with reason IMPULSE_LOCK right after this call,
    // and natural expiry must release that set and nothing else.
    try {
      final ic = await config.getImpulseConfig();
      _impulseSuspendedApps =
          ic.action == ImpulseAction.timerAndSuspend ? ic.suspendApps : const [];
    } catch (_) {
      // Without the record, expiry releases nothing — the fail-safe
      // direction (apps stay suspended rather than the wrong set being
      // released).
      _impulseSuspendedApps = const [];
    }
    notifyListeners();
  }

  /// Releases the recorded impulse suspension. Called from the two lock
  /// end paths only: natural expiry in [_tick] and
  /// [completeImpulseLockEarly].
  Future<void> _releaseImpulseSuspension() async {
    final apps = _impulseSuspendedApps;
    _impulseSuspendedApps = const [];
    if (apps.isEmpty) return;
    try {
      await channel.setAppSuspended(apps, false, reason: 'IMPULSE_LOCK');
    } catch (_) {
      // Best effort: the lock itself is already complete and
      // persisted. A failed release leaves the apps suspended — the
      // fail-safe direction for this app — and they remain releasable
      // from the Apps tab.
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _eventSub?.cancel();
    session.dispose();
    super.dispose();
  }
}

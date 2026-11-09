/// App-wide controller: startup routing (F31), the recovery session (F23),
/// language (F33), and the persisted long-running timers (impulse lock F21,
/// forced removal F2).
///
/// Timer accounting note (honest limitation): the original accumulates
/// forced-removal / impulse time natively across reboots with
/// elapsedRealtime. This Dart model advances the timers only by *measured*
/// elapsed time while the app process is alive (a 30 s ticker). Time never
/// advances while the app is dead, so a timer can take longer than
/// wall-clock — never shorter — which fails safe for this product's threat
/// model. Full reboot-proof native accounting is future Kotlin work.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import 'data/config_store.dart';
import 'data/privileged_channel.dart';
import 'domain/recovery.dart';

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
  DateTime? _lastTick;
  ImpulseLock impulseLock = const ImpulseLock();
  ForcedRemoval forcedRemoval = const ForcedRemoval();

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
      language = await config.getLanguage();
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
      final isSet = await channel.isRecoveryCodeSet();
      startup = isSet ? StartupState.locked : StartupState.needsRecoverySetup;
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
    _lastTick = DateTime.now();
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) => _tick());
  }

  Future<void> _tick() async {
    final now = DateTime.now();
    final delta = now.difference(_lastTick ?? now);
    _lastTick = now;
    var changed = false;
    if (impulseLock.active && !impulseLock.isComplete) {
      impulseLock = impulseLock.tick(delta);
      await config.setImpulseLock(impulseLock);
      changed = true;
      if (impulseLock.isComplete) {
        // Natural expiry: release exactly the apps this lock suspended
        // (the original releases its recorded impulse suspension when
        // the block ends — there is no other release path, and no
        // early stop).
        await _releaseImpulseSuspension();
      }
    }
    if (forcedRemoval.active && !forcedRemoval.isComplete) {
      forcedRemoval = forcedRemoval.advance(delta);
      await config.setForcedRemoval(forcedRemoval);
      changed = true;
    }
    if (changed) notifyListeners();
  }

  void onRecoverySetupComplete() {
    startup = StartupState.unlocked;
    notifyListeners();
  }

  void unlock() {
    if (startup == StartupState.locked) {
      startup = StartupState.unlocked;
      notifyListeners();
    }
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

  /// Releases the recorded impulse suspension. Called only from the
  /// natural-expiry path in [_tick].
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

  Future<void> stopImpulseLock() async {
    impulseLock = impulseLock.stop();
    _impulseSuspendedApps = const [];
    await config.setImpulseLock(impulseLock);
    notifyListeners();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _eventSub?.cancel();
    session.dispose();
    super.dispose();
  }
}

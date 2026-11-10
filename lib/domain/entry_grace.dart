/// App-lock timing (v1.0.6, Phase C — WhatsApp-style): how long Azm
/// stays unlocked after a successful entry before it demands
/// fingerprint/password again on return.
///
/// Independence (spec): this grace governs ONLY the app-entry gate.
/// The paper-code recovery session and every sensitive-action gate
/// are untouched — an entry grace never opens the recovery gate.
library;

/// The four options, mirroring WhatsApp's app-lock timing choices.
enum EntryGracePeriod {
  immediately,
  oneMinute,
  fifteenMinutes,
  oneHour;

  Duration get duration => switch (this) {
    EntryGracePeriod.immediately => Duration.zero,
    EntryGracePeriod.oneMinute => const Duration(minutes: 1),
    EntryGracePeriod.fifteenMinutes => const Duration(minutes: 15),
    EntryGracePeriod.oneHour => const Duration(hours: 1),
  };

  static EntryGracePeriod fromName(String? name) =>
      EntryGracePeriod.values.firstWhere(
        (p) => p.name == name,
        orElse: () => EntryGracePeriod.immediately,
      );

  /// Lengthening the grace loosens entry security (paper-code
  /// session required); shortening tightens and is free.
  bool loosenedBy(EntryGracePeriod next) => next.duration > duration;
}

/// Absences shorter than this are treated as transient system
/// surfaces (the biometric prompt itself, permission dialogs,
/// share/picker intents) and never trigger a relock — the standard
/// debounce that keeps "Immediately" from loop-locking.
const entryTransientDebounce = Duration(seconds: 3);

/// The relock decision on returning to the foreground.
///
/// * [lastUnlockAt] is the persisted wall-clock moment of the last
///   successful entry. A FUTURE timestamp (clock moved backwards, or
///   a forged value) is clamped to expired — process death and
///   reboots can never extend the grace.
/// * A failed entry attempt never calls this with a fresh timestamp:
///   only successful entries record one (see AppController.unlock).
/// * [backgroundedFor] is how long the app was actually away; below
///   [entryTransientDebounce] the departure counts as a transient
///   system surface and never relocks.
bool entryShouldRelock({
  required DateTime now,
  required DateTime? lastUnlockAt,
  required EntryGracePeriod period,
  required Duration backgroundedFor,
}) {
  if (backgroundedFor < entryTransientDebounce) return false;
  final last = lastUnlockAt;
  if (last == null) return true;
  if (last.isAfter(now)) return true; // future timestamp → expired
  final elapsed = now.difference(last);
  return elapsed >= period.duration;
}

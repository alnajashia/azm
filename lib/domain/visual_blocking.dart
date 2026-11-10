/// Visual blocking (F16/F17, v1.0.6): the Dart-side model of the
/// on-device NSFW image-inspection settings. The authoritative store
/// is native (`VisualBlockingSettings` in Kotlin, read/written through
/// the privileged channel); this model mirrors its keys, defaults and
/// clamps exactly so the UI and the native reader can never drift.
///
/// Behavioural reference: the original's `VisualBlockingSettings`
/// (Apache-2.0) — same defaults: disabled by default, Reddit as the
/// default target, categories {hentai, porn, sexy}, threshold 0.5,
/// escalation off with 5 blocks / 15 min window / 30 min suspension.
library;

/// Categories the model can report, minus `neutral` (which means
/// "nothing flagged" and is never a block category).
const visualSelectableCategories = <String>[
  'drawings',
  'hentai',
  'porn',
  'sexy',
];

const visualDefaultTargetPackages = <String>{'com.reddit.frontpage'};
const visualDefaultCategories = <String>{'hentai', 'porn', 'sexy'};
const visualDefaultThreshold = 0.5;
const visualDefaultSuspendBlockCount = 5;
const visualDefaultSuspendWindowMinutes = 15;
const visualDefaultSuspendDurationMinutes = 30;

class VisualBlockingConfig {
  const VisualBlockingConfig({
    this.enabled = false,
    this.targetPackages = visualDefaultTargetPackages,
    this.categories = visualDefaultCategories,
    this.threshold = visualDefaultThreshold,
    this.suspendEnabled = false,
    this.suspendBlockCount = visualDefaultSuspendBlockCount,
    this.suspendWindowMinutes = visualDefaultSuspendWindowMinutes,
    this.suspendDurationMinutes = visualDefaultSuspendDurationMinutes,
  });

  final bool enabled;
  final Set<String> targetPackages;
  final Set<String> categories;
  final double threshold;
  final bool suspendEnabled;
  final int suspendBlockCount;
  final int suspendWindowMinutes;
  final int suspendDurationMinutes;

  VisualBlockingConfig copyWith({
    bool? enabled,
    Set<String>? targetPackages,
    Set<String>? categories,
    double? threshold,
    bool? suspendEnabled,
    int? suspendBlockCount,
    int? suspendWindowMinutes,
    int? suspendDurationMinutes,
  }) => VisualBlockingConfig(
    enabled: enabled ?? this.enabled,
    targetPackages: targetPackages ?? this.targetPackages,
    categories: categories ?? this.categories,
    threshold: threshold ?? this.threshold,
    suspendEnabled: suspendEnabled ?? this.suspendEnabled,
    suspendBlockCount: suspendBlockCount ?? this.suspendBlockCount,
    suspendWindowMinutes: suspendWindowMinutes ?? this.suspendWindowMinutes,
    suspendDurationMinutes:
        suspendDurationMinutes ?? this.suspendDurationMinutes,
  );

  Map<String, dynamic> toMap() => {
    'enabled': enabled,
    'targetPackages': targetPackages.toList()..sort(),
    'categories': categories.toList()..sort(),
    'threshold': threshold,
    'suspendEnabled': suspendEnabled,
    'suspendBlockCount': suspendBlockCount,
    'suspendWindowMinutes': suspendWindowMinutes,
    'suspendDurationMinutes': suspendDurationMinutes,
  };

  factory VisualBlockingConfig.fromMap(Map<String, dynamic> m) {
    Set<String> strSet(String key, Set<String> fallback) {
      final v = m[key];
      if (v is List) {
        return v.whereType<String>().toSet();
      }
      return fallback;
    }

    int intVal(String key, int fallback) =>
        (m[key] as num?)?.toInt() ?? fallback;

    final categories = strSet(
      'categories',
      visualDefaultCategories,
    ).intersection(visualSelectableCategories.toSet());
    return VisualBlockingConfig(
      enabled: m['enabled'] as bool? ?? false,
      targetPackages: strSet(
        'targetPackages',
        visualDefaultTargetPackages,
      ),
      categories: categories.isEmpty ? visualDefaultCategories : categories,
      threshold: ((m['threshold'] as num?)?.toDouble() ?? visualDefaultThreshold)
          .clamp(0.05, 0.99),
      suspendEnabled: m['suspendEnabled'] as bool? ?? false,
      suspendBlockCount: intVal(
        'suspendBlockCount',
        visualDefaultSuspendBlockCount,
      ).clamp(1, 100),
      suspendWindowMinutes: intVal(
        'suspendWindowMinutes',
        visualDefaultSuspendWindowMinutes,
      ).clamp(1, 1440),
      suspendDurationMinutes: intVal(
        'suspendDurationMinutes',
        visualDefaultSuspendDurationMinutes,
      ).clamp(1, 10080),
    );
  }

  /// Whether changing `this` → [next] LOOSENS protection (and so
  /// requires the paper-code session): switching inspection off,
  /// dropping a target app or a category, raising the threshold, or
  /// weakening the escalation. Everything else is a tightening or a
  /// neutral change and is free.
  bool loosenedBy(VisualBlockingConfig next) {
    if (enabled && !next.enabled) return true;
    if (!next.targetPackages.containsAll(targetPackages)) return true;
    if (!next.categories.containsAll(categories)) return true;
    if (next.threshold > threshold) return true;
    if (suspendEnabled && !next.suspendEnabled) return true;
    if (next.suspendBlockCount > suspendBlockCount) return true;
    if (next.suspendWindowMinutes < suspendWindowMinutes) return true;
    if (next.suspendDurationMinutes < suspendDurationMinutes) return true;
    return false;
  }

  @override
  bool operator ==(Object other) =>
      other is VisualBlockingConfig &&
      other.enabled == enabled &&
      other.targetPackages.length == targetPackages.length &&
      other.targetPackages.containsAll(targetPackages) &&
      other.categories.length == categories.length &&
      other.categories.containsAll(categories) &&
      other.threshold == threshold &&
      other.suspendEnabled == suspendEnabled &&
      other.suspendBlockCount == suspendBlockCount &&
      other.suspendWindowMinutes == suspendWindowMinutes &&
      other.suspendDurationMinutes == suspendDurationMinutes;

  @override
  int get hashCode => Object.hash(
    enabled,
    Object.hashAllUnordered(targetPackages),
    Object.hashAllUnordered(categories),
    threshold,
    suspendEnabled,
    suspendBlockCount,
    suspendWindowMinutes,
    suspendDurationMinutes,
  );
}

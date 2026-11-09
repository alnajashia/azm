/// Dart-domain configuration repositories (ARCH §8.2).
///
/// These stores hold UI/domain configuration — browser blocklists, focus
/// and impulse config, challenge selection, usage-warning stages, forced
/// removal state — persisted in the native SharedPreferences files through
/// the channel's allowlisted `getSetting`/`setSetting`, as JSON strings
/// mirroring the original schema. Enforcement state (limits, windows,
/// groups, words, logs) goes through the typed channel methods instead.
library;

import 'dart:convert';

import '../domain/challenges.dart';
import '../domain/focus.dart';
import '../domain/recovery.dart';
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

enum ImpulseAction { timerOnly, timerAndSuspend }

class ImpulseConfig {
  const ImpulseConfig({
    this.action = ImpulseAction.timerAndSuspend,
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
          orElse: () => ImpulseAction.timerAndSuspend,
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

class UsageWarningStage {
  const UsageWarningStage({
    required this.minutesBefore,
    required this.type,
    this.vibrationCount = 0,
  });
  final double minutesBefore;
  final UsageWarningType type;
  final int vibrationCount;

  Map<String, dynamic> toJson() =>
      {'minutes': minutesBefore, 'type': type.name, 'vibrationCount': vibrationCount};
  factory UsageWarningStage.fromJson(Map<String, dynamic> j) => UsageWarningStage(
        minutesBefore: (j['minutes'] as num?)?.toDouble() ?? 0,
        type: UsageWarningType.values.firstWhere(
          (t) => t.name == j['type'],
          orElse: () => UsageWarningType.silent,
        ),
        vibrationCount: (j['vibrationCount'] as num?)?.toInt() ?? 0,
      );
}

/// The original's defaults: 15 min silent, 5 min sound, 1 min vibrate×1,
/// 0.5 min vibrate×3.
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

  Future<List<ChallengeType>> getChallengeSelection() async {
    final raw = await _channel.getSetting(security, 'access_challenges');
    final names = raw is String && raw.isNotEmpty
        ? (jsonDecode(raw) as List).map((e) => e.toString()).toList()
        : <String>['math'];
    final selected = ChallengeType.values.where((t) => names.contains(t.name)).toList();
    return selected.isEmpty ? [ChallengeType.math] : selected;
  }

  Future<void> setChallengeSelection(List<ChallengeType> types) => _channel.setSetting(
      security, 'access_challenges', jsonEncode(types.map((t) => t.name).toList()));

  Future<List<String>> getCustomReadingPhrases() async {
    final raw = await _channel.getSetting(security, 'reading_custom_passages');
    if (raw is String && raw.isNotEmpty) {
      return (jsonDecode(raw) as List).map((e) => e.toString()).toList();
    }
    return const [];
  }

  Future<void> setCustomReadingPhrases(List<String> phrases) => _channel.setSetting(
      security, 'reading_custom_passages', jsonEncode(phrases));

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
    return j == null ? const FocusConfig() : FocusConfig.fromJson(j);
  }

  Future<void> setFocusConfig(FocusConfig config) => _setJson(focus, 'config', config.toJson());

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

  // ------------------------------------------------------------ usage warnings

  Future<({bool enabled, List<UsageWarningStage> stages})> getUsageWarnings() async {
    final enabled = await _channel.getSetting(usageWarning, 'enabled') == true;
    final raw = await _channel.getSetting(usageWarning, 'stages');
    if (raw is String && raw.isNotEmpty) {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return (
          enabled: enabled,
          stages: decoded
              .map((e) => UsageWarningStage.fromJson((e as Map).cast<String, dynamic>()))
              .toList(),
        );
      }
    }
    return (enabled: enabled, stages: defaultUsageWarningStages);
  }

  Future<void> setUsageWarnings(bool enabled, List<UsageWarningStage> stages) async {
    await _channel.setSetting(usageWarning, 'enabled', enabled);
    await _channel.setSetting(
        usageWarning, 'stages', jsonEncode(stages.map((s) => s.toJson()).toList()));
  }

  // ------------------------------------------------------------ forced removal

  Future<ForcedRemoval> getForcedRemoval() async {
    final j = await _getJson(recoveryState, 'forced_removal');
    return j == null ? const ForcedRemoval() : ForcedRemoval.fromJson(j);
  }

  Future<void> setForcedRemoval(ForcedRemoval value) =>
      _setJson(recoveryState, 'forced_removal', value.toJson());

  // ------------------------------------------------------------ language & theme

  Future<String> getLanguage() async {
    final v = await _channel.getSetting(security, 'language');
    return v is String && (v == 'pt' || v == 'en') ? v : 'en';
  }

  Future<void> setLanguage(String language) =>
      _channel.setSetting(security, 'language', language);
}

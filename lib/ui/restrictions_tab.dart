/// Restrictions tab (F3): every discoverable `UserManager` restriction,
/// draft/apply model as in the original — toggles edit a draft, Apply
/// commits. Applying a restriction is tightening (free); clearing one is
/// loosening and routes through the recovery gate. Without Device Owner
/// the tab shows the original's NoDeviceOwnerPrivileges state.
///
/// Presentation follows the original's `RestrictionAccordion` /
/// `RestrictionItem` (`RestrictionsTab.kt`): each row shows a humanised
/// label with the raw key beneath it (the original resolves a string
/// resource per key and falls back to the key; the channel model carries
/// no label, so the humanised key is the label and the raw key stays
/// visible), an Active badge for applied restrictions, a per-section
/// select-all checkbox that toggles the section's (filtered) drafts, and
/// search normalised the way the original's
/// `SystemRestrictions.normalizeForSearch` normalises (case- and
/// diacritic-insensitive, matched against label and key).
library;

import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../data/privileged_channel.dart';
import '../l10n/l10n.dart';
import 'common.dart';
import 'recovery_ui.dart';
import 'setup_screen.dart';

class RestrictionsTab extends StatefulWidget {
  const RestrictionsTab({super.key, required this.controller});
  final AppController controller;
  @override
  State<RestrictionsTab> createState() => _RestrictionsTabState();
}

class _RestrictionsTabState extends State<RestrictionsTab> {
  List<UserRestriction>? _restrictions;
  final Map<String, bool> _draft = {};
  Object? _error;
  bool _notOwner = false;
  bool _applying = false;
  String _query = '';

  PrivilegedChannel get _channel => widget.controller.channel;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _error = null;
      _notOwner = false;
    });
    try {
      final list = await _channel.listUserRestrictions();
      if (mounted) {
        setState(() {
          _restrictions = list;
          _draft
            ..clear()
            ..addEntries(list.map((r) => MapEntry(r.key, r.active)));
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _notOwner = e is PrivilegedException && e.isNotOwner;
        });
      }
    }
  }

  bool get _dirty {
    final list = _restrictions;
    if (list == null) return false;
    return list.any((r) => _draft[r.key] != r.active);
  }

  List<UserRestriction> _filter(
    List<UserRestriction> list, {
    required bool recommended,
  }) {
    final query = _normalizeForSearch(_query);
    return list.where((r) {
      if (r.recommended != recommended) return false;
      if (query.isEmpty) return true;
      // The original matches the normalised query against the normalised
      // label and the normalised key (`RestrictionsTab.kt` accordion).
      return _normalizeForSearch(
            _humaniseRestrictionKey(r.key),
          ).contains(query) ||
          _normalizeForSearch(r.key).contains(query);
    }).toList();
  }

  Future<void> _apply() async {
    final list = _restrictions!;
    final toApply = list
        .where((r) => _draft[r.key] == true && !r.active)
        .toList();
    final toClear = list
        .where((r) => _draft[r.key] == false && r.active)
        .toList();
    // Clearing a restriction is a loosening (F23). APPLYING one is an
    // activation of system-level blocking, which the user's v1.0.4
    // security directive also puts behind the paper recovery code —
    // so any apply with pending changes in either direction opens the
    // gate first; a refused gate applies nothing at all.
    if ((toApply.isNotEmpty || toClear.isNotEmpty) &&
        !await ensureRecoverySession(context, widget.controller)) {
      return; // gate refused: nothing is applied at all
    }
    setState(() => _applying = true);
    try {
      for (final r in toApply) {
        await _channel.applyUserRestriction(r.key);
      }
      for (final r in toClear) {
        await _channel.clearUserRestriction(r.key);
      }
      if (mounted) {
        showInfoSnackBar(context, context.l10n.restrictionsUpdated);
      }
    } catch (e) {
      if (!mounted) return;
      await showErrorSnackBar(context, e);
    } finally {
      if (mounted) {
        setState(() => _applying = false);
        _load();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (_notOwner) {
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Icon(Icons.shield_outlined, size: 48),
          const SizedBox(height: 12),
          Text(
            l10n.noDeviceOwnerPrivileges,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(l10n.noOwnerRestrictionsBody),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => Scaffold(
                  appBar: AppBar(title: Text(l10n.setupTitle)),
                  body: SetupScreen(controller: widget.controller),
                ),
              ),
            ),
            icon: const Icon(Icons.admin_panel_settings),
            label: Text(l10n.openSetup),
          ),
        ],
      );
    }
    if (_error != null) return ErrorView(error: _error!, onRetry: _load);
    final list = _restrictions;
    if (list == null) return LoadingView(message: l10n.loadingRestrictions);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: TextField(
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              labelText: l10n.searchRestrictions,
              border: const OutlineInputBorder(),
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        Expanded(
          child: ListView(
            children: [
              _section(
                l10n.recommendedSection,
                _filter(list, recommended: true),
              ),
              _section(
                l10n.otherRestrictionsSection,
                _filter(list, recommended: false),
              ),
            ],
          ),
        ),
        if (_dirty)
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton.icon(
                onPressed: _applying ? null : _apply,
                icon: const Icon(Icons.check),
                label: Text(_applying ? l10n.applying : l10n.applyChanges),
              ),
            ),
          ),
      ],
    );
  }

  Widget _section(String title, List<UserRestriction> items) {
    if (items.isEmpty) return const SizedBox.shrink();
    // The original's accordion header carries a select-all checkbox bound
    // to `isAllDraftsEnabled(filteredKeys)`; toggling it sets every draft
    // in the (filtered) section (`RestrictionsTab.kt` RestrictionAccordion).
    final allEnabled = items.every((r) => _draft[r.key] == true);
    // v1.0.5 UX (user directive): each section is a titled card, like
    // the Status tab's groups — header row and rows inside one Card.
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(4, 8, 16, 0),
            child: Row(
              children: [
                Checkbox(
                  value: allEnabled,
                  onChanged: _applying
                      ? null
                      : (v) => setState(() {
                          for (final r in items) {
                            _draft[r.key] = v ?? true;
                          }
                        }),
                ),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          for (final r in items)
            SwitchListTile(
              title: Row(
                children: [
                  Expanded(child: Text(_humaniseRestrictionKey(r.key))),
                  if (r.active) _activeBadge(),
                ],
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    r.key,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontFamily: 'monospace',
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (_draft[r.key] != r.active)
                    Text(context.l10n.changedNotApplied),
                ],
              ),
              value: _draft[r.key] ?? r.active,
              onChanged: (v) => setState(() => _draft[r.key] = v),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  /// The original's "Active" badge for an applied restriction
  /// (`RestrictionsTab.kt` RestrictionItem).
  Widget _activeBadge() {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        context.l10n.activeBadge,
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(color: scheme.onPrimaryContainer),
      ),
    );
  }
}

/// Humanised form of a restriction key (`no_install_apps` → "No Install
/// Apps") — the label shown when no richer label exists for the key.
String _humaniseRestrictionKey(String key) {
  final words = key
      .split(RegExp(r'[_\.\-]+'))
      .where((w) => w.isNotEmpty)
      .toList();
  if (words.isEmpty) return key;
  return words.map((w) => '${w[0].toUpperCase()}${w.substring(1)}').join(' ');
}

/// Port of the original's `SystemRestrictions.normalizeForSearch`
/// (`SystemRestrictions.kt:79-82`): NFD-normalise, strip combining
/// diacritical marks, lowercase. Dart has no Unicode normaliser, so
/// precomposed Latin letters are folded to their base letters directly —
/// the same net effect for the Latin-script labels these keys produce —
/// and any combining marks already present are dropped.
String _normalizeForSearch(String text) {
  final buffer = StringBuffer();
  for (final rune in text.toLowerCase().runes) {
    if (rune >= 0x0300 && rune <= 0x036f) continue;
    final ch = String.fromCharCode(rune);
    buffer.write(_diacriticFold[ch] ?? ch);
  }
  return buffer.toString();
}

const Map<String, String> _diacriticFold = {
  'à': 'a',
  'á': 'a',
  'â': 'a',
  'ã': 'a',
  'ä': 'a',
  'å': 'a',
  'ā': 'a',
  'ă': 'a',
  'ą': 'a',
  'æ': 'ae',
  'ç': 'c',
  'ć': 'c',
  'ĉ': 'c',
  'ċ': 'c',
  'č': 'c',
  'ď': 'd',
  'đ': 'd',
  'è': 'e',
  'é': 'e',
  'ê': 'e',
  'ë': 'e',
  'ē': 'e',
  'ĕ': 'e',
  'ė': 'e',
  'ę': 'e',
  'ě': 'e',
  'ĝ': 'g',
  'ğ': 'g',
  'ġ': 'g',
  'ģ': 'g',
  'ĥ': 'h',
  'ħ': 'h',
  'ì': 'i',
  'í': 'i',
  'î': 'i',
  'ï': 'i',
  'ĩ': 'i',
  'ī': 'i',
  'ĭ': 'i',
  'į': 'i',
  'ı': 'i',
  'ĵ': 'j',
  'ķ': 'k',
  'ĺ': 'l',
  'ļ': 'l',
  'ľ': 'l',
  'ŀ': 'l',
  'ł': 'l',
  'ñ': 'n',
  'ń': 'n',
  'ņ': 'n',
  'ň': 'n',
  'ŋ': 'n',
  'ò': 'o',
  'ó': 'o',
  'ô': 'o',
  'õ': 'o',
  'ö': 'o',
  'ø': 'o',
  'ō': 'o',
  'ŏ': 'o',
  'ő': 'o',
  'œ': 'oe',
  'ŕ': 'r',
  'ŗ': 'r',
  'ř': 'r',
  'ś': 's',
  'ŝ': 's',
  'ş': 's',
  'š': 's',
  'ș': 's',
  'ß': 'ss',
  'ť': 't',
  'ŧ': 't',
  'ț': 't',
  'ù': 'u',
  'ú': 'u',
  'û': 'u',
  'ü': 'u',
  'ũ': 'u',
  'ū': 'u',
  'ŭ': 'u',
  'ů': 'u',
  'ű': 'u',
  'ų': 'u',
  'ý': 'y',
  'ÿ': 'y',
  'ŷ': 'y',
  'ź': 'z',
  'ż': 'z',
  'ž': 'z',
  'þ': 'th',
};

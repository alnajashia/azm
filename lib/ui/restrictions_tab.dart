/// Restrictions tab (F3): every discoverable `UserManager` restriction,
/// draft/apply model as in the original — toggles edit a draft, Apply
/// commits. Applying a restriction is tightening (free); clearing one is
/// loosening and routes through the recovery gate. Without Device Owner
/// the tab shows the original's NoDeviceOwnerPrivileges state.
library;

import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../data/privileged_channel.dart';
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

  List<UserRestriction> _filter(List<UserRestriction> list, {required bool recommended}) {
    return list.where((r) {
      if (r.recommended != recommended) return false;
      if (_query.isEmpty) return true;
      return r.key.toLowerCase().contains(_query.toLowerCase());
    }).toList();
  }

  Future<void> _apply() async {
    final list = _restrictions!;
    final toApply = list.where((r) => _draft[r.key] == true && !r.active).toList();
    final toClear = list.where((r) => _draft[r.key] == false && r.active).toList();
    if (toClear.isNotEmpty &&
        !await ensureRecoverySession(context, widget.controller)) {
      return; // loosening refused: nothing is applied at all
    }
    setState(() => _applying = true);
    try {
      for (final r in toApply) {
        await _channel.applyUserRestriction(r.key);
      }
      for (final r in toClear) {
        await _channel.clearUserRestriction(r.key);
      }
      if (mounted) showInfoSnackBar(context, 'Restrictions updated and verified.');
    } catch (e) {
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
    if (_notOwner) {
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Icon(Icons.shield_outlined, size: 48),
          const SizedBox(height: 12),
          Text(
            'No Device Owner privileges',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          const Text(
            'System restrictions only work while Dominanter is the Device '
            'Owner. Complete the Setup flow first — restrictions are not '
            'faked without it.',
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => Scaffold(
                appBar: AppBar(title: const Text('Setup')),
                body: SetupScreen(controller: widget.controller),
              ),
            )),
            icon: const Icon(Icons.admin_panel_settings),
            label: const Text('Open Setup'),
          ),
        ],
      );
    }
    if (_error != null) return ErrorView(error: _error!, onRetry: _load);
    final list = _restrictions;
    if (list == null) return const LoadingView(message: 'Loading restrictions…');
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              labelText: 'Search restrictions',
              border: OutlineInputBorder(),
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        Expanded(
          child: ListView(
            children: [
              _section('Recommended', _filter(list, recommended: true)),
              _section('Other restrictions', _filter(list, recommended: false)),
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
                label: Text(_applying ? 'Applying…' : 'Apply changes'),
              ),
            ),
          ),
      ],
    );
  }

  Widget _section(String title, List<UserRestriction> items) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
        for (final r in items)
          SwitchListTile(
            title: Text(r.key),
            subtitle: _draft[r.key] != r.active
                ? const Text('Changed — not applied yet')
                : null,
            value: _draft[r.key] ?? r.active,
            onChanged: (v) => setState(() => _draft[r.key] = v),
          ),
      ],
    );
  }
}

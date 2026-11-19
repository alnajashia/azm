import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../data/privileged_channel.dart';
import '../domain/internet_block.dart';
import '../l10n/l10n.dart';
import 'common.dart';
import 'recovery_ui.dart';

/// Internet blocking + VPN-based DNS filtering (user order
/// 2026-11-19): one local, no-configuration VPN. DNS filtering
/// over DoH (port 443) plus internet blocking per app, per group,
/// or for the whole phone. Weakening changes (turning off, a
/// weaker level, a smaller blocked set) are recovery-code-gated
/// via [runLoosening]; strengthening is free.
class InternetBlockScreen extends StatefulWidget {
  const InternetBlockScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<InternetBlockScreen> createState() => _InternetBlockScreenState();
}

class _InternetBlockScreenState extends State<InternetBlockScreen> {
  InternetBlockConfig? _config;
  bool _running = false;
  List<AppGroupModel> _groups = const [];
  final _customUrlController = TextEditingController();

  AppController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _customUrlController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final config = await _c.channel.getInternetBlockConfig();
      final status = await _c.channel.getVpnStatus();
      final groups = await _c.channel.getGroups();
      if (!mounted) return;
      setState(() {
        _config = config;
        _running = status.running;
        _groups = groups;
        _customUrlController.text = config.customDohUrl;
      });
    } catch (e) {
      if (mounted) await showErrorCard(context, e);
    }
  }

  /// Applies [next]; gated through the recovery code when it
  /// weakens the current protection.
  Future<void> _apply(InternetBlockConfig next) async {
    final current = _config;
    if (current == null) return;
    Future<void> doApply() async {
      try {
        final saved = await _c.channel.setInternetBlockConfig(next);
        final status = await _c.channel.getVpnStatus();
        if (!mounted) return;
        setState(() {
          _config = saved;
          _running = status.running;
        });
      } catch (e) {
        if (mounted) await showErrorCard(context, e);
      }
    }

    if (next.isLooseningFrom(current)) {
      await runLoosening(context, _c, doApply);
    } else {
      await doApply();
    }
  }

  Future<void> _pickApps() async {
    final config = _config;
    if (config == null) return;
    final picked = await showAppPicker(
      context: context,
      channel: _c.channel,
      initialSelected: config.packages,
    );
    if (picked == null || !mounted) return;
    await _apply(config.copyWith(packages: picked));
  }

  Future<void> _pickGroups() async {
    final config = _config;
    if (config == null) return;
    final picked = await showDialog<Set<String>>(
      context: context,
      builder: (dialogContext) {
        var selected = {...config.groupIds};
        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text(AppLocalizations.of(context).internetBlockPickGroups),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final group in _groups)
                    CheckboxListTile(
                      title: Text(group.name),
                      value: selected.contains(group.id),
                      onChanged: (v) => setDialogState(() {
                        if (v == true) {
                          selected.add(group.id);
                        } else {
                          selected.remove(group.id);
                        }
                      }),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text(AppLocalizations.of(context).cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(selected),
                child: Text(AppLocalizations.of(context).save),
              ),
            ],
          ),
        );
      },
    );
    if (picked == null || !mounted) return;
    await _apply(config.copyWith(groupIds: picked));
  }

  String _providerLabel(AppLocalizations l10n, DohProvider provider) =>
      switch (provider) {
        DohProvider.cleanBrowsing => l10n.dnsProviderCleanbrowsing,
        DohProvider.adguard => l10n.dnsProviderAdguard,
        DohProvider.cloudflare => l10n.dnsProviderCloudflare,
        DohProvider.custom => l10n.dnsCustom,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final config = _config;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.internetBlockTitle)),
      body: config == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                SectionCard(
                  title: l10n.internetBlockEnableTitle,
                  children: [
                    SwitchListTile(
                      title: Text(l10n.internetBlockEnableTitle),
                      subtitle: Text(
                        _running
                            ? l10n.internetBlockStatusRunning
                            : l10n.internetBlockEnableSub,
                      ),
                      value: config.enabled,
                      onChanged: (v) =>
                          _apply(config.copyWith(enabled: v)),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SectionCard(
                  title: l10n.internetBlockLevelTitle,
                  children: [
                    RadioGroup<InternetBlockLevel>(
                      groupValue: config.level,
                      onChanged: (v) {
                        if (v != null) _apply(config.copyWith(level: v));
                      },
                      child: Column(
                        children: [
                          RadioListTile<InternetBlockLevel>(
                            title: Text(l10n.internetBlockLevelDns),
                            subtitle: Text(l10n.internetBlockLevelDnsSub),
                            value: InternetBlockLevel.off,
                          ),
                          RadioListTile<InternetBlockLevel>(
                            title: Text(l10n.internetBlockLevelApps),
                            subtitle: Text(l10n.internetBlockLevelAppsSub),
                            value: InternetBlockLevel.apps,
                          ),
                          RadioListTile<InternetBlockLevel>(
                            title: Text(l10n.internetBlockLevelGroups),
                            subtitle: Text(l10n.internetBlockLevelGroupsSub),
                            value: InternetBlockLevel.groups,
                          ),
                          RadioListTile<InternetBlockLevel>(
                            title: Text(l10n.internetBlockLevelPhone),
                            subtitle: Text(l10n.internetBlockLevelPhoneSub),
                            value: InternetBlockLevel.phone,
                          ),
                        ],
                      ),
                    ),
                    if (config.level == InternetBlockLevel.apps)
                      ListTile(
                        leading: const Icon(Icons.apps_outlined),
                        title: Text(l10n.internetBlockPickApps),
                        subtitle: Text(
                          config.packages.isEmpty
                              ? l10n.internetBlockNoneSelected
                              : l10n.internetBlockAppsCount(
                                  config.packages.length,
                                ),
                        ),
                        trailing: const Icon(Icons.navigate_next_outlined),
                        onTap: _pickApps,
                      ),
                    if (config.level == InternetBlockLevel.groups)
                      ListTile(
                        leading: const Icon(Icons.group_outlined),
                        title: Text(l10n.internetBlockPickGroups),
                        subtitle: Text(
                          config.groupIds.isEmpty
                              ? l10n.internetBlockNoneSelected
                              : l10n.internetBlockGroupsCount(
                                  config.groupIds.length,
                                ),
                        ),
                        trailing: const Icon(Icons.navigate_next_outlined),
                        onTap: _pickGroups,
                      ),
                  ],
                ),
                if (config.level == InternetBlockLevel.off) ...[
                  const SizedBox(height: 12),
                  SectionCard(
                    title: l10n.internetBlockProviderTitle,
                    children: [
                      RadioGroup<DohProvider>(
                        groupValue: config.dohProvider,
                        onChanged: (v) {
                          if (v != null) {
                            _apply(config.copyWith(dohProvider: v));
                          }
                        },
                        child: Column(
                          children: [
                            for (final provider in DohProvider.values)
                              RadioListTile<DohProvider>(
                                title: Text(_providerLabel(l10n, provider)),
                                value: provider,
                              ),
                          ],
                        ),
                      ),
                      if (config.dohProvider == DohProvider.custom)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: TextField(
                            controller: _customUrlController,
                            keyboardType: TextInputType.url,
                            decoration: InputDecoration(
                              labelText: l10n.internetBlockCustomUrl,
                            ),
                            onSubmitted: (v) => _apply(
                              config.copyWith(customDohUrl: v.trim()),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                Text(
                  l10n.internetBlockNote,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
    );
  }
}

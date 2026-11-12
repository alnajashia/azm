/// Content inspection settings (F16/F17, v1.0.6 — Phase B): per-app
/// on-device image inspection. The settings live natively
/// (`VisualBlockingSettings` in Kotlin) and are read/written through
/// the privileged channel; the accessibility service does the actual
/// scanning and inference — never this UI layer.
///
/// Gate classification (standing rules): enabling inspection, adding
/// apps/categories, lowering the threshold, or strengthening the
/// escalation TIGHTENS (free). Switching inspection off, dropping an
/// app/category, raising the threshold, or weakening the escalation
/// LOOSENS and goes through the paper-code session
/// ([VisualBlockingConfig.loosenedBy] decides).
library;

import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../domain/visual_blocking.dart';
import '../l10n/l10n.dart';
import 'common.dart';
import 'recovery_ui.dart';

class VisualBlockingScreen extends StatefulWidget {
  const VisualBlockingScreen({super.key, required this.controller});
  final AppController controller;

  @override
  State<VisualBlockingScreen> createState() => _VisualBlockingScreenState();
}

class _VisualBlockingScreenState extends State<VisualBlockingScreen> {
  VisualBlockingConfig? _config;
  Object? _error;
  bool _saving = false;

  AppController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final m = await _c.channel.getVisualBlockingConfig();
      if (mounted) {
        setState(() => _config = VisualBlockingConfig.fromMap(m));
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _apply(VisualBlockingConfig next) async {
    final current = _config;
    if (current == null || next == current) return;
    Future<void> save() async {
      setState(() => _saving = true);
      try {
        final m = await _c.channel.setVisualBlockingConfig(next.toMap());
        if (mounted) {
          setState(() {
            _config = VisualBlockingConfig.fromMap(m);
            _saving = false;
          });
          showInfoSnackBar(context, context.l10n.visualSaved);
        }
      } catch (e) {
        if (mounted) {
          setState(() => _saving = false);
          await showErrorCard(context, e);
        }
      }
    }

    if (current.loosenedBy(next)) {
      await runLoosening(context, _c, save);
    } else {
      await save();
    }
  }

  String _categoryLabel(AppLocalizations l10n, String category) =>
      switch (category) {
        'drawings' => l10n.visualCategoryDrawings,
        'hentai' => l10n.visualCategoryHentai,
        'porn' => l10n.visualCategoryPorn,
        'sexy' => l10n.visualCategorySexy,
        _ => category,
      };

  Future<void> _pickApps(VisualBlockingConfig config) async {
    final result = await showAppPicker(
      context: context,
      channel: _c.channel,
      title: context.l10n.visualAppsSection,
      initialSelected: config.targetPackages,
    );
    if (result != null && mounted) {
      await _apply(config.copyWith(targetPackages: result));
    }
  }

  Future<void> _editNumber({
    required String title,
    required int initial,
    required int min,
    required int max,
    required ValueChanged<int> onValue,
  }) async {
    final l10n = context.l10n;
    final controller = TextEditingController(text: '$initial');
    final result = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(hintText: '$min–$max'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () {
              final v = int.tryParse(controller.text.trim());
              Navigator.pop(dialogContext, v?.clamp(min, max));
            },
            child: Text(l10n.save),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result != null) onValue(result);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final config = _config;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.visualBlockingTitle)),
      body: _error != null && config == null
          ? ErrorView(error: _error!, onRetry: _load)
          : config == null
          ? const LoadingView()
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                SectionCard(
                  title: l10n.visualBlockingTitle,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: Text(l10n.visualExplanation),
                    ),
                    SwitchListTile(
                      secondary: const Icon(Icons.image_search_outlined),
                      title: Text(l10n.visualEnable),
                      subtitle: Text(l10n.visualRequiresAccessibility),
                      value: config.enabled,
                      onChanged: _saving
                          ? null
                          : (v) => _apply(config.copyWith(enabled: v)),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SectionCard(
                  title: l10n.visualAppsSection,
                  children: [
                    ListTile(
                      leading: const Icon(Icons.apps_outlined),
                      title: Text(
                        l10n.visualAppsSelected(config.targetPackages.length),
                      ),
                      trailing: const Icon(Icons.navigate_next_outlined),
                      onTap: _saving ? null : () => _pickApps(config),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SectionCard(
                  title: l10n.visualCategoriesSection,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: Text(l10n.visualCategoriesDesc),
                    ),
                    for (final category in visualSelectableCategories)
                      CheckboxListTile(
                        title: Text(_categoryLabel(l10n, category)),
                        value: config.categories.contains(category),
                        onChanged: _saving
                            ? null
                            : (v) {
                                final next = {...config.categories};
                                if (v == true) {
                                  next.add(category);
                                } else {
                                  next.remove(category);
                                }
                                if (next.isEmpty) return;
                                _apply(config.copyWith(categories: next));
                              },
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                SectionCard(
                  title: l10n.visualThresholdSection,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: Text(l10n.visualThresholdDesc),
                    ),
                    Slider(
                      value: config.threshold,
                      min: 0.1,
                      max: 0.95,
                      divisions: 17,
                      label: config.threshold.toStringAsFixed(2),
                      onChanged: _saving
                          ? null
                          : (v) => setState(
                              () => _config = config.copyWith(threshold: v),
                            ),
                      onChangeEnd: _saving
                          ? null
                          : (v) => _apply(
                              _config!.copyWith(
                                threshold: (v * 20).round() / 20,
                              ),
                            ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SectionCard(
                  title: l10n.visualSuspend,
                  children: [
                    SwitchListTile(
                      secondary: const Icon(Icons.block_outlined),
                      title: Text(l10n.visualSuspend),
                      subtitle: Text(l10n.visualSuspendDesc),
                      value: config.suspendEnabled,
                      onChanged: _saving
                          ? null
                          : (v) =>
                                _apply(config.copyWith(suspendEnabled: v)),
                    ),
                    ListTile(
                      leading: const Icon(Icons.repeat_outlined),
                      title: Text(l10n.visualSuspendCount),
                      trailing: Text('${config.suspendBlockCount}'),
                      onTap: _saving
                          ? null
                          : () => _editNumber(
                              title: l10n.visualSuspendCount,
                              initial: config.suspendBlockCount,
                              min: 1,
                              max: 100,
                              onValue: (v) => _apply(
                                config.copyWith(suspendBlockCount: v),
                              ),
                            ),
                    ),
                    ListTile(
                      leading: const Icon(Icons.schedule_outlined),
                      title: Text(l10n.visualSuspendWindow),
                      trailing: Text('${config.suspendWindowMinutes}'),
                      onTap: _saving
                          ? null
                          : () => _editNumber(
                              title: l10n.visualSuspendWindow,
                              initial: config.suspendWindowMinutes,
                              min: 1,
                              max: 1440,
                              onValue: (v) => _apply(
                                config.copyWith(suspendWindowMinutes: v),
                              ),
                            ),
                    ),
                    ListTile(
                      leading: const Icon(Icons.timer_outlined),
                      title: Text(l10n.visualSuspendDuration),
                      trailing: Text('${config.suspendDurationMinutes}'),
                      onTap: _saving
                          ? null
                          : () => _editNumber(
                              title: l10n.visualSuspendDuration,
                              initial: config.suspendDurationMinutes,
                              min: 1,
                              max: 10080,
                              onValue: (v) => _apply(
                                config.copyWith(suspendDurationMinutes: v),
                              ),
                            ),
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}

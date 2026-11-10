/// Entry password UI (v1.0.4): the lock-screen password prompt and the
/// Config tab's "App entry" section.
///
/// Security posture, mirroring the rest of the app:
/// * the prompt verifies against the stored PBKDF2 hash only — a correct
///   password calls the same app-entry unlock as a successful biometric
///   prompt, and deliberately does NOT open a recovery session;
/// * wrong attempts are visibly rejected and throttled by an in-memory
///   anti-guess delay (2 s × consecutive failures, capped at 30 s) —
///   in-memory only, like the recovery session itself;
/// * setting, changing or removing the password are loosening-class
///   changes to the entry posture, so the Config section routes them
///   through the recovery gate (`runLoosening`) — the paper recovery
///   code is required, exactly as for every other sensitive change.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../domain/entry_password.dart';
import '../l10n/l10n.dart';
import 'common.dart';
import 'recovery_ui.dart';

/// Shows the lock-screen password prompt. Returns true when the entered
/// password verified; the caller then unlocks app entry (and nothing
/// else — no recovery session is started here).
Future<bool> showEntryPasswordPrompt(
  BuildContext context,
  AppController controller,
) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (_) => _EntryPasswordPromptDialog(controller: controller),
  );
  return result ?? false;
}

class _EntryPasswordPromptDialog extends StatefulWidget {
  const _EntryPasswordPromptDialog({required this.controller});
  final AppController controller;
  @override
  State<_EntryPasswordPromptDialog> createState() =>
      _EntryPasswordPromptDialogState();
}

class _EntryPasswordPromptDialogState
    extends State<_EntryPasswordPromptDialog> {
  final _input = TextEditingController();
  bool _obscured = true;
  bool _checking = false;
  String? _error;
  int _failures = 0;
  int _waitSeconds = 0;
  Timer? _waitTimer;

  @override
  void dispose() {
    _waitTimer?.cancel();
    _input.dispose();
    super.dispose();
  }

  /// Anti-guess delay after the [_failures]-th consecutive wrong
  /// attempt: 2 s × failures, capped at 30 s.
  int get _delaySeconds => math.min(2 * _failures, 30);

  void _startWait() {
    _waitTimer?.cancel();
    setState(() => _waitSeconds = _delaySeconds);
    _waitTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _waitSeconds--);
      if (_waitSeconds <= 0) timer.cancel();
    });
  }

  Future<void> _submit() async {
    if (_checking || _waitSeconds > 0) return;
    final l10n = context.l10n;
    setState(() {
      _checking = true;
      _error = null;
    });
    // Let the "Checking…" state paint before the (deliberately
    // expensive) KDF runs on this isolate.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    bool ok;
    try {
      ok = await widget.controller.config.verifyEntryPassword(_input.text);
    } catch (_) {
      ok = false;
    }
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _checking = false;
      _failures++;
      _error = l10n.passwordWrong;
      _input.clear();
    });
    _startWait();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final waiting = _waitSeconds > 0;
    return AlertDialog(
      title: Text(l10n.passwordPromptTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _input,
            obscureText: _obscured,
            autocorrect: false,
            enableSuggestions: false,
            autofocus: true,
            enabled: !_checking && !waiting,
            decoration: InputDecoration(
              labelText: l10n.passwordFieldLabel,
              border: const OutlineInputBorder(),
              errorText: _error,
              suffixIcon: IconButton(
                icon: Icon(
                  _obscured
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
                tooltip: _obscured ? l10n.passwordShow : l10n.passwordHide,
                onPressed: () => setState(() => _obscured = !_obscured),
              ),
            ),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _checking ? null : () => Navigator.of(context).pop(false),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: (_checking || waiting) ? null : _submit,
          child: Text(
            _checking
                ? l10n.passwordChecking
                : waiting
                ? l10n.passwordRetryIn(_waitSeconds)
                : l10n.passwordUnlock,
          ),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------- Config section

/// The Config tab's "App entry" section: explains the password's exact
/// scope and offers set / change / remove, each routed through the
/// recovery gate.
class AppEntrySection extends StatefulWidget {
  const AppEntrySection({super.key, required this.controller});
  final AppController controller;
  @override
  State<AppEntrySection> createState() => _AppEntrySectionState();
}

class _AppEntrySectionState extends State<AppEntrySection> {
  bool? _isSet;

  AppController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final isSet = await _c.config.isEntryPasswordSet();
      if (mounted) setState(() => _isSet = isSet);
    } catch (_) {
      if (mounted) setState(() => _isSet = false);
    }
  }

  Future<void> _setOrChange() async {
    await runLoosening(context, _c, () async {
      if (!mounted) return;
      final password = await showDialog<String>(
        context: context,
        builder: (_) => const _EntryPasswordSetDialog(),
      );
      if (password == null) return;
      await _c.config.setEntryPassword(password);
      await _load();
      if (mounted) {
        showInfoSnackBar(context, context.l10n.passwordSetDone);
      }
    });
  }

  Future<void> _remove() async {
    await runLoosening(context, _c, () async {
      if (!mounted) return;
      final l10n = context.l10n;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(l10n.passwordRemoveTitle),
          content: Text(l10n.passwordRemoveBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(l10n.passwordRemoveConfirm),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      await _c.config.removeEntryPassword();
      await _load();
      if (mounted) {
        showInfoSnackBar(context, context.l10n.passwordRemovedDone);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isSet = _isSet;
    // A titled card group like every other Config section (v1.0.5).
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              l10n.appEntrySection,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Text(
              l10n.appEntryExplanation,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.password_outlined),
            title: Text(
              isSet == null
                  ? l10n.checking
                  : isSet
                  ? l10n.appEntryStatusSet
                  : l10n.appEntryStatusUnset,
            ),
            subtitle: Text(
              isSet == true ? l10n.appEntryChange : l10n.appEntrySet,
            ),
            trailing: const Icon(Icons.navigate_next),
            onTap: isSet == null ? null : _setOrChange,
          ),
          if (isSet == true)
            ListTile(
              leading: const Icon(Icons.password_outlined),
              title: Text(l10n.appEntryRemove),
              trailing: const Icon(Icons.navigate_next),
              onTap: _remove,
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

/// New-password entry with confirmation and the minimum-length rule,
/// validated inline. Returns the chosen password, or null on cancel.
class _EntryPasswordSetDialog extends StatefulWidget {
  const _EntryPasswordSetDialog();
  @override
  State<_EntryPasswordSetDialog> createState() =>
      _EntryPasswordSetDialogState();
}

class _EntryPasswordSetDialogState extends State<_EntryPasswordSetDialog> {
  final _first = TextEditingController();
  final _second = TextEditingController();
  bool _obscured = true;
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _first.dispose();
    _second.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l10n = context.l10n;
    final password = _first.text;
    if (password.length < entryPasswordMinLength) {
      setState(() => _error = l10n.passwordMinLength(entryPasswordMinLength));
      return;
    }
    if (password != _second.text) {
      setState(() => _error = l10n.passwordMismatch);
      return;
    }
    // The KDF runs when the section stores the password (after this
    // dialog closes); the brief pause here is only the pop animation.
    setState(() {
      _saving = true;
      _error = null;
    });
    Navigator.of(context).pop(password);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.appEntrySection),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _first,
            obscureText: _obscured,
            autocorrect: false,
            enableSuggestions: false,
            autofocus: true,
            decoration: InputDecoration(
              labelText: l10n.passwordNewLabel,
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscured
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
                tooltip: _obscured ? l10n.passwordShow : l10n.passwordHide,
                onPressed: () => setState(() => _obscured = !_obscured),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _second,
            obscureText: _obscured,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: l10n.passwordConfirmLabel,
              border: const OutlineInputBorder(),
              errorText: _error,
            ),
            onSubmitted: (_) => _save(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(onPressed: _saving ? null : _save, child: Text(l10n.save)),
      ],
    );
  }
}

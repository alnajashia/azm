/// Entry password UI (v1.0.4): the lock-screen password prompt and the
/// Config tab's "App entry" section.
///
/// Security posture, mirroring the rest of the app:
/// * the prompt verifies against the stored PBKDF2 hash only — a correct
///   password calls the same app-entry unlock as a successful biometric
///   prompt, and deliberately does NOT open a recovery session;
/// * wrong attempts are visibly rejected and throttled by an anti-guess
///   delay (2 s × consecutive failures, capped at 30 s) whose failure
///   count is PERSISTED in the config store — dismissing the prompt or
///   killing the app does not reset it (v1.0.5 audit B-3). A
///   verification ERROR (as opposed to a wrong password) is surfaced
///   distinctly and never counts as a failed attempt (audit C-M2);
/// * setting, changing or removing the password are loosening-class
///   changes to the entry posture, so the Config section routes them
///   through the recovery gate (`runLoosening`) — the paper recovery
///   code is required, exactly as for every other sensitive change.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../domain/entry_grace.dart';
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
  int _waitSeconds = 0;
  Timer? _waitTimer;

  @override
  void initState() {
    super.initState();
    _resumePersistedWait();
  }

  @override
  void dispose() {
    _waitTimer?.cancel();
    _input.dispose();
    super.dispose();
  }

  /// A prompt (re)opened inside the persisted anti-guess window waits
  /// out the remainder of the delay — the throttle lives in the config
  /// store, not in this State (v1.0.5 audit B-3).
  Future<void> _resumePersistedWait() async {
    try {
      final remaining =
          await widget.controller.config.entryPasswordWaitRemaining();
      if (!mounted || remaining <= Duration.zero) return;
      _startWait(remaining.inSeconds + (remaining.inMilliseconds % 1000 == 0 ? 0 : 1));
    } catch (_) {
      // A throttle read failure must not block entry attempts; the KDF
      // cost per guess still applies.
    }
  }

  void _startWait(int seconds) {
    _waitTimer?.cancel();
    setState(() => _waitSeconds = seconds);
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
      // Verification ERROR, not a wrong password (v1.0.5 audit C-M2):
      // surface it distinctly and do NOT count it as a failed attempt —
      // the user is not throttled for an infrastructure failure.
      if (!mounted) return;
      setState(() {
        _checking = false;
        _error = l10n.passwordVerifyError;
      });
      return;
    }
    if (!mounted) return;
    if (ok) {
      // Success clears the persisted failure count.
      try {
        await widget.controller.config.resetEntryPasswordThrottle();
      } catch (_) {
        // Clearing the throttle is bookkeeping; entry itself succeeded.
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
      return;
    }
    // A genuine wrong password: persist the failure FIRST (the returned
    // count includes this attempt), then wait out its delay.
    var failures = 1;
    try {
      failures =
          await widget.controller.config.recordEntryPasswordFailure();
    } catch (_) {
      // If persistence itself fails, still throttle this dialog.
    }
    if (!mounted) return;
    setState(() {
      _checking = false;
      _error = l10n.passwordWrong;
      _input.clear();
    });
    _startWait(entryPasswordDelaySeconds(failures));
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
  bool _corrupt = false;
  bool _loadFailed = false;

  AppController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // A load failure is its own visible state with a retry — never a
    // silent "not set" (v1.0.5 audit C-L4). A corrupt stored record is
    // likewise surfaced as corrupt, not as unset (audit B-9); setting a
    // new password replaces it.
    try {
      final state = await _c.config.getEntryPasswordRecordState();
      if (mounted) {
        setState(() {
          _isSet = state == EntryPasswordRecordState.set;
          _corrupt = state == EntryPasswordRecordState.corrupt;
          _loadFailed = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isSet = null;
          _corrupt = false;
          _loadFailed = true;
        });
      }
    }
  }

  String _graceLabel(AppLocalizations l10n, EntryGracePeriod period) =>
      switch (period) {
        EntryGracePeriod.immediately => l10n.entryGraceImmediately,
        EntryGracePeriod.oneMinute => l10n.entryGraceOneMinute,
        EntryGracePeriod.fifteenMinutes => l10n.entryGraceFifteenMinutes,
        EntryGracePeriod.oneHour => l10n.entryGraceOneHour,
      };

  Future<void> _pickGracePeriod() async {
    final l10n = context.l10n;
    final current = _c.entryGracePeriod;
    final choice = await showDialog<EntryGracePeriod>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(l10n.entryGraceTitle),
        children: [
          for (final period in EntryGracePeriod.values)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialogContext, period),
              child: Row(
                children: [
                  Icon(
                    period == current
                        ? Icons.radio_button_checked_outlined
                        : Icons.radio_button_unchecked_outlined,
                  ),
                  const SizedBox(width: 12),
                  Text(_graceLabel(l10n, period)),
                ],
              ),
            ),
        ],
      ),
    );
    if (choice == null || choice == current || !mounted) return;
    if (current.loosenedBy(choice)) {
      await runLoosening(context, _c, () async {
        await _c.setEntryGracePeriod(choice);
        if (mounted) setState(() {});
      });
    } else {
      await _c.setEntryGracePeriod(choice);
      if (mounted) setState(() {});
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
    final confirmed = await showDestructiveConfirmDialog(
      context,
      title: context.l10n.passwordRemoveTitle,
      message: context.l10n.passwordRemoveBody,
      confirmText: context.l10n.passwordRemoveConfirm,
    );
    if (!confirmed || !mounted) return;
    await runLoosening(context, _c, () async {
      if (!mounted) return;
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
          if (_loadFailed)
            ListTile(
              leading: const Icon(Icons.error_outline),
              title: Text(l10n.passwordVerifyError),
              trailing: TextButton(
                onPressed: _load,
                child: Text(l10n.retry),
              ),
            )
          else if (_corrupt)
            ListTile(
              leading: const Icon(Icons.password_outlined),
              title: Text(l10n.passwordRecordCorrupt),
              subtitle: Text(l10n.appEntrySet),
              trailing: const Icon(Icons.navigate_next_outlined),
              onTap: _setOrChange,
            )
          else
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
              trailing: const Icon(Icons.navigate_next_outlined),
              onTap: isSet == null ? null : _setOrChange,
            ),
          if (isSet == true)
            ListTile(
              leading: const Icon(Icons.password_outlined),
              title: Text(l10n.appEntryRemove),
              trailing: const Icon(Icons.navigate_next_outlined),
              onTap: _remove,
            ),
          // App-lock timing (v1.0.6 Phase C): how long the app stays
          // open after a successful entry. Lengthening the grace
          // loosens entry security → paper-code session; shortening
          // is free. This governs ONLY the entry gate — never the
          // recovery session or any sensitive-action gate.
          ListTile(
            leading: const Icon(Icons.lock_clock_outlined),
            title: Text(l10n.entryGraceTitle),
            subtitle: Text(l10n.entryGraceSub),
            trailing: Text(_graceLabel(l10n, _c.entryGracePeriod)),
            onTap: _pickGracePeriod,
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
  // Each field has its own show/hide state (v1.0.5 audit C-C2): a
  // shared flag revealed both fields at once.
  bool _obscuredFirst = true;
  bool _obscuredSecond = true;
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
            obscureText: _obscuredFirst,
            autocorrect: false,
            enableSuggestions: false,
            autofocus: true,
            decoration: InputDecoration(
              labelText: l10n.passwordNewLabel,
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscuredFirst
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
                tooltip: _obscuredFirst ? l10n.passwordShow : l10n.passwordHide,
                onPressed: () =>
                    setState(() => _obscuredFirst = !_obscuredFirst),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _second,
            obscureText: _obscuredSecond,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: l10n.passwordConfirmLabel,
              border: const OutlineInputBorder(),
              errorText: _error,
              suffixIcon: IconButton(
                icon: Icon(
                  _obscuredSecond
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
                tooltip:
                    _obscuredSecond ? l10n.passwordShow : l10n.passwordHide,
                onPressed: () =>
                    setState(() => _obscuredSecond = !_obscuredSecond),
              ),
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

/// Recovery code wizard (F24/F31) and recovery gate (F23).
///
/// The code itself is generated natively (`generateRecoveryCode`), shown
/// once for the paper copy, and sent back once via `setRecoveryCode` —
/// Kotlin stores only a salted PBKDF2 hash (ARCH §7.1). Dart never persists
/// the code. Because only the hash is stored, the code can never be
/// displayed again after setup; the wizard says so plainly.
library;

import 'dart:math';

import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../data/privileged_channel.dart';
import '../domain/challenges.dart';
import '../domain/recovery.dart';
import 'challenges_ui.dart';
import 'common.dart';

String normalizeCode(String raw) => raw.replaceAll(' ', '').toUpperCase();

bool isValidCodeFormat(String raw) {
  final n = normalizeCode(raw);
  return n.length == 16 && n.codeUnits.every((c) => c >= 65 && c <= 90);
}

String groupCode(String code) {
  final n = normalizeCode(code);
  final parts = <String>[];
  for (var i = 0; i < n.length; i += 4) {
    parts.add(n.substring(i, min(i + 4, n.length)));
  }
  return parts.join(' ');
}

/// A–Z entry with an optional shuffled keypad (F24 option), so the code
/// cannot be learned from finger positions.
class CodeEntry extends StatefulWidget {
  const CodeEntry({
    super.key,
    required this.controller,
    this.shuffled = false,
    this.label = 'Recovery code',
  });

  final TextEditingController controller;
  final bool shuffled;
  final String label;

  @override
  State<CodeEntry> createState() => _CodeEntryState();
}

class _CodeEntryState extends State<CodeEntry> {
  late final List<String> _letters;

  @override
  void initState() {
    super.initState();
    _letters = List.generate(26, (i) => String.fromCharCode(65 + i));
    if (widget.shuffled) _letters.shuffle(Random.secure());
  }

  void _append(String ch) {
    final next = normalizeCode(widget.controller.text) + ch;
    if (next.length > 16) return;
    widget.controller.text = groupCode(next);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: widget.controller,
          textCapitalization: TextCapitalization.characters,
          autocorrect: false,
          readOnly: widget.shuffled,
          style: Theme.of(context).textTheme.titleLarge,
          textAlign: TextAlign.center,
          decoration: InputDecoration(
            labelText: widget.label,
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              icon: const Icon(Icons.backspace_outlined),
              onPressed: () {
                final n = normalizeCode(widget.controller.text);
                if (n.isNotEmpty) {
                  widget.controller.text = groupCode(
                    n.substring(0, n.length - 1),
                  );
                  setState(() {});
                }
              },
            ),
          ),
        ),
        if (widget.shuffled) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            alignment: WrapAlignment.center,
            children: [
              for (final letter in _letters)
                SizedBox(
                  width: 44,
                  height: 44,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(padding: EdgeInsets.zero),
                    onPressed: () => _append(letter),
                    child: Text(letter),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

// ------------------------------------------------------------------- Wizard

class RecoveryWizard extends StatefulWidget {
  const RecoveryWizard({
    super.key,
    required this.controller,
    required this.onDone,
    this.isRegeneration = false,
  });

  final AppController controller;
  final VoidCallback onDone;

  /// True when replacing an existing code (Config → change recovery code).
  final bool isRegeneration;

  @override
  State<RecoveryWizard> createState() => _RecoveryWizardState();
}

class _RecoveryWizardState extends State<RecoveryWizard> {
  int _step = 0;
  String? _generated;
  Object? _generateError;
  bool _writtenOnPaper = false;
  final _confirm = TextEditingController();
  bool _saving = false;
  String? _saveError;

  @override
  void initState() {
    super.initState();
    _generate();
  }

  @override
  void dispose() {
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    setState(() {
      _generateError = null;
      _generated = null;
    });
    try {
      final code = await widget.controller.channel.generateRecoveryCode();
      if (mounted) setState(() => _generated = code);
    } catch (e) {
      if (mounted) setState(() => _generateError = e);
    }
  }

  Future<void> _save() async {
    final typed = normalizeCode(_confirm.text);
    if (typed != normalizeCode(_generated!)) {
      setState(
        () => _saveError =
            'That does not match the code shown. Check your paper copy and try again.',
      );
      return;
    }
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      final ok = await widget.controller.channel.setRecoveryCode(typed);
      if (!mounted) return;
      if (ok) {
        widget.onDone();
      } else {
        setState(() {
          _saving = false;
          _saveError = 'The code was not stored. Nothing was changed.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _saveError = e is PrivilegedException
              ? friendlyError(e)
              : e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          widget.isRegeneration
              ? 'Change recovery code'
              : 'Set up your recovery code',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        const Text(
          'This 16-letter code is the only ordinary way to loosen any '
          'restriction in Dominanter. It is stored only as a salted hash on '
          'this device — it cannot be shown again after this step, and '
          'there is no account or cloud copy.',
        ),
        const SizedBox(height: 24),
        if (_step == 0) ...[
          if (_generateError != null)
            ErrorView(error: _generateError!, onRetry: _generate)
          else if (_generated == null)
            const LoadingView(message: 'Generating your code…')
          else ...[
            GradientCard(
              padding: const EdgeInsets.all(20),
              child: Text(
                groupCode(_generated!),
                style: Theme.of(context).textTheme.headlineMedium,
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 16),
            CheckboxListTile(
              value: _writtenOnPaper,
              onChanged: (v) => setState(() => _writtenOnPaper = v ?? false),
              title: const Text(
                'I have written this code on paper and stored the paper '
                'somewhere away from this phone.',
              ),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _writtenOnPaper
                  ? () => setState(() => _step = 1)
                  : null,
              child: const Text('Continue'),
            ),
          ],
        ] else ...[
          const Text(
            'Now type the code back from your paper copy, exactly as written.',
          ),
          const SizedBox(height: 16),
          CodeEntry(controller: _confirm),
          if (_saveError != null) ...[
            const SizedBox(height: 12),
            Text(
              _saveError!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Store recovery code'),
          ),
          TextButton(
            onPressed: _saving ? null : () => setState(() => _step = 0),
            child: const Text('Back to the code'),
          ),
        ],
      ],
    );
  }
}

/// First-run gate screen (F31): nothing else is reachable until a code exists.
class SetupRecoveryScreen extends StatelessWidget {
  const SetupRecoveryScreen({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dominanter — first run')),
      body: RecoveryWizard(
        controller: controller,
        onDone: controller.onRecoverySetupComplete,
      ),
    );
  }
}

// --------------------------------------------------------------------- Gate

/// Opens a recovery session: challenges first (F22), then code entry (F23).
/// Returns true when a session is active afterwards.
Future<bool> ensureRecoverySession(
  BuildContext context,
  AppController controller,
) async {
  if (controller.session.isActive) return true;
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _RecoveryGateDialog(controller: controller),
  );
  return result ?? false;
}

class _RecoveryGateDialog extends StatefulWidget {
  const _RecoveryGateDialog({required this.controller});
  final AppController controller;
  @override
  State<_RecoveryGateDialog> createState() => _RecoveryGateDialogState();
}

class _RecoveryGateDialogState extends State<_RecoveryGateDialog> {
  bool _loading = true;
  Object? _loadError;
  List<ChallengeType> _challenges = const [];
  List<String> _customPhrases = const [];
  bool _challengesDone = false;
  final _code = TextEditingController();
  bool _shuffle = false;
  bool _verifying = false;
  String? _verifyError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final challenges = await widget.controller.config.getChallengeSelection();
      final phrases = await widget.controller.config.getCustomReadingPhrases();
      final shuffle = await widget.controller.config.getShuffleKeyboard();
      if (mounted) {
        setState(() {
          _challenges = challenges;
          _customPhrases = phrases;
          _shuffle = shuffle;
          _loading = false;
          // No available challenge selected -> straight to the code.
          if (!challenges.any((t) => t.isAvailableInV1)) _challengesDone = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadError = e;
          _loading = false;
        });
      }
    }
  }

  Future<void> _verify() async {
    if (!isValidCodeFormat(_code.text)) {
      setState(
        () => _verifyError = 'Enter the 16-letter code from your paper copy.',
      );
      return;
    }
    setState(() {
      _verifying = true;
      _verifyError = null;
    });
    try {
      final matches = await widget.controller.channel.verifyRecoveryCode(
        normalizeCode(_code.text),
      );
      if (!mounted) return;
      if (matches) {
        widget.controller.session.start();
        Navigator.of(context).pop(true);
      } else {
        setState(() {
          _verifying = false;
          _verifyError = 'That code does not match. Nothing was unlocked.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _verifying = false;
          _verifyError = e is PrivilegedException
              ? friendlyError(e)
              : e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Recovery session'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: _loading
              ? const LoadingView(message: 'Preparing challenges…')
              : _loadError != null
              ? ErrorView(error: _loadError!, onRetry: _load)
              : !_challengesDone
              ? ChallengeRunnerView(
                  types: _challenges,
                  customPhrases: _customPhrases,
                  onAllComplete: () => setState(() => _challengesDone = true),
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Challenges complete. Enter your recovery code '
                      'to open a 10-minute session.',
                    ),
                    const SizedBox(height: 16),
                    CodeEntry(controller: _code, shuffled: _shuffle),
                    if (_verifyError != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _verifyError!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _verifying ? null : _verify,
                      child: _verifying
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Open session'),
                    ),
                  ],
                ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

/// Guards a loosening action (F23): runs it only with an active session.
Future<bool> runLoosening(
  BuildContext context,
  AppController controller,
  Future<void> Function() action,
) async {
  if (!await ensureRecoverySession(context, controller)) return false;
  try {
    await action();
    return true;
  } catch (e) {
    await showErrorSnackBar(context, e);
    return false;
  }
}

/// Runs a tightening change immediately and offers the original's 5-second
/// undo (F23 PendingChange model).
Future<void> runTighteningWithUndo(
  BuildContext context,
  PendingChange change,
) async {
  try {
    await change.run();
  } catch (e) {
    await showErrorSnackBar(context, e);
    return;
  }
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(change.description),
      duration: change.undoWindow,
      action: SnackBarAction(
        label: 'Undo',
        onPressed: () async {
          final undone = await change.undo();
          if (!undone && context.mounted) {
            showInfoSnackBar(
              context,
              'The undo window has passed; the change stands.',
            );
          }
        },
      ),
    ),
  );
}

/// Session countdown chip for the app bar (mirrors the original's top-bar
/// session countdown with renew / end actions).
class SessionChip extends StatelessWidget {
  const SessionChip({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller.session,
      builder: (context, _) {
        if (!controller.session.isActive) return const SizedBox.shrink();
        final strings = AppStrings(controller.language);
        return Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Chip(
                avatar: const Icon(Icons.lock_open, size: 18),
                label: Text(
                  '${strings.sessionRemaining}: ${formatDuration(controller.session.remaining)}',
                ),
              ),
              TextButton(
                onPressed: controller.session.renew,
                child: Text(strings.renewSession),
              ),
              TextButton(
                onPressed: controller.session.end,
                child: Text(strings.endSession),
              ),
            ],
          ),
        );
      },
    );
  }
}

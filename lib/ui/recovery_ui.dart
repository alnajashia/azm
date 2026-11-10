/// Recovery code wizard (F24/F31) and recovery gate (F23).
///
/// The code itself is generated natively (`generateRecoveryCode`), shown
/// once for the paper copy, and sent back once via `setRecoveryCode` —
/// Kotlin stores only a salted PBKDF2 hash (ARCH §7.1). Dart never persists
/// the code. Because only the hash is stored, the code can never be
/// displayed again after setup; the wizard says so plainly.
///
/// The wizard mirrors the original's four steps (Intro → Write → Confirm →
/// Store, `RecoveryCodeWizard.kt`): the freshly generated code is held in
/// memory only for the duration of the wizard, exactly long enough to be
/// written on paper, typed back, and stored.
///
/// The gate's order (v1.0.5, user directive superseding the original
/// `RecoveryGate.kt` behaviour): the recovery **code is validated**, and
/// a correct code opens the session immediately — no access challenges
/// run after the code, anywhere. Challenges belong to Impulse Lock only
/// (their selection lives on the Impulse Lock screen).
library;

import 'dart:math';

import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../data/privileged_channel.dart';
import '../domain/recovery.dart';
import '../l10n/l10n.dart';
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
///
/// Note: the original's shuffle entry (`RecoveryConfirmDialog.kt`) is a
/// 4×4 grid that puts the *correct* next letter in one random cell and
/// reshuffles after every tap. That design reads the stored code back one
/// letter at a time — impossible here, because Dominanter stores only a
/// salted PBKDF2 hash of the code and can never recover its letters. The
/// shuffled full-alphabet keypad below is the closest equivalent that
/// works against a hash: it still defeats finger-position learning, but
/// every letter remains tappable.
class CodeEntry extends StatefulWidget {
  const CodeEntry({
    super.key,
    required this.controller,
    this.shuffled = false,
    this.label,
  });

  final TextEditingController controller;
  final bool shuffled;

  /// Field label; defaults to the localized "Recovery code".
  final String? label;

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
            labelText: widget.label ?? context.l10n.recoveryCodeLabel,
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

/// The four wizard steps, in the original's order
/// (`RecoveryCodeWizard.kt`: STEP_INTRO, STEP_WRITE, STEP_CONFIRM,
/// STEP_STORE).
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
  static const _stepIntro = 0;
  static const _stepWrite = 1;
  static const _stepConfirm = 2;
  static const _stepStore = 3;
  static const _stepCount = 4;

  int _step = _stepIntro;

  /// The freshly generated code. Held in memory only, only until the
  /// wizard finishes — it is never persisted in Dart, and once stored
  /// natively (as a salted PBKDF2 hash) it can never be shown again.
  String? _generated;
  Object? _generateError;

  bool _revealed = false;
  bool _writtenOnPaper = false;
  final _confirm = TextEditingController();
  bool _storedOnPaper = false;
  bool _saving = false;
  String? _saveError;

  @override
  void initState() {
    super.initState();
    _confirm.addListener(_onConfirmChanged);
    _generate();
  }

  @override
  void dispose() {
    _confirm.removeListener(_onConfirmChanged);
    _confirm.dispose();
    super.dispose();
  }

  void _onConfirmChanged() {
    if (mounted && _step == _stepConfirm) setState(() {});
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

  bool get _confirmMatches =>
      _generated != null &&
      normalizeCode(_confirm.text) == normalizeCode(_generated!);

  bool get _canAdvance => switch (_step) {
    _stepWrite => _revealed && _writtenOnPaper,
    _stepConfirm => _confirmMatches,
    _stepStore => _storedOnPaper,
    _ => true, // Intro is always advanceable, as in the original.
  };

  Future<void> _save() async {
    // The Confirm step already guaranteed typed == generated; re-check
    // defensively so a code is never stored that the user did not prove
    // they copied correctly.
    if (!_confirmMatches) {
      setState(() {
        _step = _stepConfirm;
        _saveError = context.l10n.codeMismatchStore;
      });
      return;
    }
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      final ok = await widget.controller.channel.setRecoveryCode(
        normalizeCode(_generated!),
      );
      if (!mounted) return;
      if (ok) {
        widget.onDone();
      } else {
        setState(() {
          _saving = false;
          _saveError = context.l10n.codeNotStored;
        });
      }
    } catch (e) {
      if (mounted) {
        final l10n = context.l10n;
        setState(() {
          _saving = false;
          _saveError = e is PrivilegedException
              ? friendlyError(e, l10n)
              : e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
          child: Text(
            widget.isRegeneration
                ? l10n.wizardChangeTitle
                : l10n.wizardSetupTitle,
            style: Theme.of(context).textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: _StepIndicator(current: _step, total: _stepCount),
        ),
        const SizedBox(height: 8),
        Text(
          l10n.stepOf(_step + 1, _stepCount),
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              switch (_step) {
                _stepIntro => _introStep(context),
                _stepWrite => _writeStep(context),
                _stepConfirm => _confirmStep(context),
                _ => _storeStep(context),
              },
            ],
          ),
        ),
        if (_step == _stepIntro)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
            child: Text(
              l10n.grabPaper,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: Theme.of(context).colorScheme.primary,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_step > _stepIntro) ...[
                OutlinedButton(
                  onPressed: _saving ? null : () => setState(() => _step--),
                  child: Text(l10n.back),
                ),
                const SizedBox(width: 12),
              ],
              FilledButton(
                onPressed: !_canAdvance || _saving
                    ? null
                    : _step == _stepStore
                    ? _save
                    : () => setState(() => _step++),
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(_step == _stepStore ? l10n.finish : l10n.next),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _introStep(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StepHeader(icon: Icons.key_outlined, title: l10n.wizardIntroTitle),
        const SizedBox(height: 20),
        _InfoCard(
          children: [
            _InfoCardTitle(l10n.howItWorks),
            _TipRow(icon: Icons.key_outlined, text: l10n.tipGenerates),
            _TipRow(icon: Icons.edit_note_outlined, text: l10n.tipWrite),
            _TipRow(icon: Icons.keyboard_outlined, text: l10n.tipTypeBack),
            _TipRow(icon: Icons.lock_outlined, text: l10n.tipStorePaper),
          ],
        ),
        const SizedBox(height: 16),
        Text(l10n.wizardIntroBody, textAlign: TextAlign.center),
      ],
    );
  }

  Widget _writeStep(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StepHeader(
          icon: Icons.edit_note_outlined,
          title: l10n.writeTitle,
          text: l10n.writeBody,
        ),
        const SizedBox(height: 24),
        if (_generateError != null)
          ErrorView(error: _generateError!, onRetry: _generate)
        else if (_generated == null)
          LoadingView(message: l10n.generatingCode)
        else if (!_revealed)
          FilledButton.tonalIcon(
            onPressed: () => setState(() => _revealed = true),
            icon: const Icon(Icons.visibility_outlined),
            label: Text(l10n.showCode),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
          )
        else
          HeroCard(
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
          onChanged: !_revealed
              ? null
              : (v) => setState(() => _writtenOnPaper = v ?? false),
          title: Text(l10n.wroteOnPaper),
        ),
      ],
    );
  }

  Widget _confirmStep(BuildContext context) {
    final l10n = context.l10n;
    final typed = normalizeCode(_confirm.text);
    final complete = _generated != null && typed.length == 16;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StepHeader(
          icon: Icons.password_outlined,
          title: l10n.confirmTitle,
          text: l10n.confirmBody,
        ),
        const SizedBox(height: 24),
        CodeEntry(controller: _confirm),
        const SizedBox(height: 12),
        if (_confirmMatches)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.check_circle,
                size: 18,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 6),
              Text(
                l10n.codeCorrect,
                style: TextStyle(color: Theme.of(context).colorScheme.primary),
              ),
            ],
          )
        else if (complete)
          Text(
            l10n.codeMismatchBack,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
            textAlign: TextAlign.center,
          )
        else
          Text(
            l10n.codeCountOf(typed.length),
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        if (_saveError != null) ...[
          const SizedBox(height: 12),
          Text(
            _saveError!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }

  Widget _storeStep(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StepHeader(
          icon: Icons.inventory_2_outlined,
          title: l10n.storeTitle,
          text: l10n.storeBody,
        ),
        const SizedBox(height: 24),
        _InfoCard(
          children: [
            _TipRow(icon: Icons.phonelink_erase_outlined, text: l10n.tipAway),
            _TipRow(icon: Icons.search_outlined, text: l10n.tipEasyFind),
            _TipRow(
              icon: Icons.no_photography_outlined,
              text: l10n.tipNoPhotos,
            ),
            if (widget.isRegeneration)
              _TipRow(icon: Icons.delete_outline, text: l10n.tipThrowOld),
          ],
        ),
        const SizedBox(height: 16),
        CheckboxListTile(
          value: _storedOnPaper,
          onChanged: (v) => setState(() => _storedOnPaper = v ?? false),
          title: Text(l10n.storedPaperCheckbox),
        ),
        if (_saveError != null) ...[
          const SizedBox(height: 12),
          Text(
            _saveError!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }
}

/// Numbered step circles with connectors, as in the original wizard.
class _StepIndicator extends StatelessWidget {
  const _StepIndicator({required this.current, required this.total});
  final int current;
  final int total;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        for (var i = 0; i < total; i++) ...[
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i <= current
                  ? scheme.primary
                  : scheme.surfaceContainerHighest,
            ),
            alignment: Alignment.center,
            child: i < current
                ? Icon(Icons.check, size: 18, color: scheme.onPrimary)
                : Text(
                    '${i + 1}',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: i <= current
                          ? scheme.onPrimary
                          : scheme.onSurfaceVariant,
                    ),
                  ),
          ),
          if (i < total - 1)
            Expanded(
              child: Container(
                height: 2,
                margin: const EdgeInsets.symmetric(horizontal: 6),
                color: i < current ? scheme.primary : scheme.outlineVariant,
              ),
            ),
        ],
      ],
    );
  }
}

class _StepHeader extends StatelessWidget {
  const _StepHeader({required this.icon, required this.title, this.text});
  final IconData icon;
  final String title;
  final String? text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: scheme.primaryContainer,
          ),
          child: Icon(icon, size: 40, color: scheme.onPrimaryContainer),
        ),
        const SizedBox(height: 20),
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        if (text != null) ...[
          const SizedBox(height: 12),
          Text(
            text!,
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const SizedBox(height: 12),
              children[i],
            ],
          ],
        ),
      ),
    );
  }
}

class _InfoCardTitle extends StatelessWidget {
  const _InfoCardTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(
        context,
      ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
    );
  }
}

class _TipRow extends StatelessWidget {
  const _TipRow({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 24, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
        ),
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
      appBar: AppBar(title: Text(context.l10n.firstRunTitle)),
      body: RecoveryWizard(
        controller: controller,
        onDone: controller.onRecoverySetupComplete,
      ),
    );
  }
}

// --------------------------------------------------------------------- Gate

/// Opens a recovery session: the recovery **code is asked for and
/// validated**, and a correct code starts the session at once — since
/// v1.0.5 (user directive) no challenges follow the code. Returns true
/// when a session is active afterwards.
///
/// Pass-throughs, mirroring `RecoveryGate.run()`: an already-active
/// session skips the gate, and so does the state where no recovery code
/// has been set yet (first run, before the setup wizard has run).
Future<bool> ensureRecoverySession(
  BuildContext context,
  AppController controller,
) async {
  if (controller.session.isActive) return true;
  try {
    if (!await controller.channel.isRecoveryCodeSet()) return true;
  } catch (_) {
    // If the check itself fails, fall through to the gate dialog, where
    // the failure surfaces while verifying instead of silently passing.
  }
  if (!context.mounted) return false;
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

/// Gate stages: a brief load (keypad preference), then the code itself.
/// There is deliberately no challenges stage (v1.0.5 user directive).
enum _GateStage { loading, code }

class _RecoveryGateDialogState extends State<_RecoveryGateDialog> {
  _GateStage _stage = _GateStage.loading;
  Object? _loadError;
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
    setState(() {
      _loadError = null;
      _stage = _GateStage.loading;
    });
    try {
      final shuffle = await widget.controller.config.getShuffleKeyboard();
      if (mounted) {
        setState(() {
          _shuffle = shuffle;
          _stage = _GateStage.code;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadError = e;
          _stage = _GateStage.loading;
        });
      }
    }
  }

  /// Validates the code: a correct code opens the session immediately
  /// (v1.0.5 user directive — the original ran the configured access
  /// challenges at this point; they now belong to Impulse Lock only and
  /// never follow the code).
  Future<void> _verify() async {
    if (!isValidCodeFormat(_code.text)) {
      setState(() => _verifyError = context.l10n.gateEnterCodeError);
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
      if (!matches) {
        setState(() {
          _verifying = false;
          _verifyError = context.l10n.gateWrongCode;
        });
        return;
      }
      // Code proven — the session opens right away, with no challenge
      // step of any kind (v1.0.5 user directive).
      _startSession();
    } catch (e) {
      if (mounted) {
        final l10n = context.l10n;
        setState(() {
          _verifying = false;
          _verifyError = e is PrivilegedException
              ? friendlyError(e, l10n)
              : e.toString();
        });
      }
    }
  }

  /// Final step: start the session, then let the guarded action run.
  void _startSession() {
    widget.controller.session.start();
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.gateCodeTitle),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: switch (_stage) {
            _GateStage.loading =>
              _loadError != null
                  ? ErrorView(error: _loadError!, onRetry: _load)
                  : LoadingView(message: l10n.preparingGate),
            _GateStage.code => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(l10n.gateBody),
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
                AnimatedBuilder(
                  animation: _code,
                  builder: (context, _) => FilledButton(
                    onPressed: _verifying || !isValidCodeFormat(_code.text)
                        ? null
                        : _verify,
                    child: _verifying
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(l10n.confirm),
                  ),
                ),
              ],
            ),
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.cancel),
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
    if (!context.mounted) return false;
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
    if (!context.mounted) return;
    await showErrorSnackBar(context, e);
    return;
  }
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(change.description),
      duration: change.undoWindow,
      action: SnackBarAction(
        label: context.l10n.undo,
        onPressed: () async {
          final undone = await change.undo();
          if (!undone && context.mounted) {
            showInfoSnackBar(context, context.l10n.undoWindowPassed);
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
        final l10n = context.l10n;
        return Padding(
          padding: const EdgeInsetsDirectional.only(end: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Chip(
                avatar: const Icon(Icons.lock_open, size: 18),
                label: Text(
                  '${l10n.sessionRemaining}: '
                  '${formatDuration(controller.session.remaining, l10n)}',
                ),
              ),
              TextButton(
                onPressed: controller.session.renew,
                child: Text(l10n.renewSession),
              ),
              TextButton(
                onPressed: controller.session.end,
                child: Text(l10n.endSession),
              ),
            ],
          ),
        );
      },
    );
  }
}

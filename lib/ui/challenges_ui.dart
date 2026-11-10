/// Challenge screens (F22, v1 subset): Math, Words, Reading. Tetris is
/// v1.1 and is never presented as playable — see the selection UI in the
/// Impulse Lock screen, which labels it unavailable.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../domain/challenges.dart';
import '../l10n/l10n.dart';

class MathChallengeView extends StatefulWidget {
  const MathChallengeView({super.key, required this.onComplete});
  final VoidCallback onComplete;
  @override
  State<MathChallengeView> createState() => _MathChallengeViewState();
}

class _MathChallengeViewState extends State<MathChallengeView> {
  final _challenge = MathChallenge();
  final _input = TextEditingController();
  String? _feedback;

  @override
  void initState() {
    super.initState();
    _challenge.start();
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _submit() {
    final value = int.tryParse(_input.text.trim());
    setState(() {
      if (_challenge.submit(value)) {
        _feedback = null;
        _input.clear();
        if (_challenge.isComplete) widget.onComplete();
      } else {
        _feedback = context.l10n.mathNotQuite;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_challenge.isComplete) {
      return const Center(child: Icon(Icons.check_circle, size: 48));
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(context.l10n.mathSolveTitle(MathChallenge.requiredProblems),
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        LinearProgressIndicator(
            value: _challenge.solved / MathChallenge.requiredProblems),
        const SizedBox(height: 16),
        Text(
          _challenge.current.prompt,
          style: Theme.of(context).textTheme.headlineMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _input,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          decoration: InputDecoration(
            labelText: context.l10n.answerLabel,
            errorText: _feedback,
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (_) => _submit(),
        ),
        const SizedBox(height: 12),
        FilledButton(onPressed: _submit, child: Text(context.l10n.check)),
      ],
    );
  }
}

class WordsChallengeView extends StatefulWidget {
  const WordsChallengeView({super.key, required this.onComplete, this.requiredWords = 32});
  final VoidCallback onComplete;
  final int requiredWords;
  @override
  State<WordsChallengeView> createState() => _WordsChallengeViewState();
}

class _WordsChallengeViewState extends State<WordsChallengeView> {
  late final WordsChallenge _challenge;
  final _input = TextEditingController();

  @override
  void initState() {
    super.initState();
    _challenge = WordsChallenge(requiredWords: widget.requiredWords)..start();
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  /// Per-keystroke checking, mirroring the original's `WordChallenge`
  /// (`ChallengeScreens.kt`): every keystroke is coloured against the
  /// target word as it is typed, and the word advances the moment the
  /// input matches it exactly — there is no submit button and no failure
  /// state; a wrong letter simply stays red until it is corrected. All of
  /// that logic lives in the domain model's `typeInput`; this view only
  /// mirrors the field to the model's input and paints `charStates`.
  void _onChanged(String value) {
    if (_challenge.isComplete) return;
    _challenge.typeInput(value);
    if (_input.text != _challenge.input) {
      _input.value = TextEditingValue(
        text: _challenge.input,
        selection: TextSelection.collapsed(offset: _challenge.input.length),
      );
    }
    setState(() {});
    if (_challenge.isComplete) widget.onComplete();
  }

  @override
  Widget build(BuildContext context) {
    if (_challenge.isComplete) {
      return const Center(child: Icon(Icons.check_circle, size: 48));
    }
    final scheme = Theme.of(context).colorScheme;
    final target = _challenge.currentWord;
    final states = _challenge.charStates;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(context.l10n.wordsTypeTitle,
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(
          '${_challenge.index + 1} / ${widget.requiredWords}',
          style: Theme.of(context).textTheme.bodyLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(value: _challenge.index / widget.requiredWords),
        const SizedBox(height: 16),
        Text.rich(
          TextSpan(
            children: [
              for (var i = 0; i < target.length; i++)
                TextSpan(
                  text: target[i],
                  style: TextStyle(
                    color: switch (states[i]) {
                      WordCharState.correct => scheme.primary,
                      WordCharState.wrong => scheme.error,
                      WordCharState.untyped => scheme.onSurface,
                    },
                  ),
                ),
            ],
          ),
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _input,
          textAlign: TextAlign.center,
          autocorrect: false,
          decoration: InputDecoration(
            labelText: context.l10n.typeWordLabel,
            border: const OutlineInputBorder(),
          ),
          onChanged: _onChanged,
        ),
      ],
    );
  }
}

class ReadingChallengeView extends StatefulWidget {
  const ReadingChallengeView({
    super.key,
    required this.onComplete,
    required this.customPhrases,
    this.requiredPassages = 5,
  });
  final VoidCallback onComplete;
  final List<String> customPhrases;
  final int requiredPassages;

  @override
  State<ReadingChallengeView> createState() => _ReadingChallengeViewState();
}

class _ReadingChallengeViewState extends State<ReadingChallengeView> {
  late final ReadingChallenge _challenge;
  Timer? _timer;
  DateTime? _lastTick;

  @override
  void initState() {
    super.initState();
    final passages = <ReadingPassage>[
      ...samplePassages,
      for (final p in widget.customPhrases)
        if (p.trim().isNotEmpty)
          // Title marker for a user-supplied phrase; the view maps it
          // (and the sample titles) to localized strings at build time.
          ReadingPassage('Your phrase', p.trim()),
    ];
    _challenge = ReadingChallenge(
      passages: passages,
      requiredPassages: widget.requiredPassages,
    );
    // The domain model runs on an elapsed clock (the original animates a
    // linear tween over each passage's timeline); this timer is that
    // clock. It only advances time — moving to the next passage is the
    // reader's explicit action, locked until the timeline has elapsed.
    _lastTick = DateTime.now();
    _timer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (!mounted) return;
      final now = DateTime.now();
      final delta = now.difference(_lastTick!);
      _lastTick = now;
      if (_challenge.isPassageComplete || _challenge.isComplete) return;
      setState(() => _challenge.advance(delta));
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _next() {
    if (!_challenge.next()) return;
    _lastTick = DateTime.now();
    if (_challenge.isComplete) {
      _timer?.cancel();
      widget.onComplete();
    } else {
      setState(() {});
    }
  }

  /// Localized display title for a passage: the sample set's titles and
  /// the custom-phrase marker are chrome; passage TEXT stays the
  /// authored English content (users' own phrases are shown verbatim).
  String _passageTitle(BuildContext context, String title) {
    final l10n = context.l10n;
    return switch (title) {
      'On waiting' => l10n.passageOnWaiting,
      'On the future self' => l10n.passageOnFutureSelf,
      'On attention' => l10n.passageOnAttention,
      'On beginning again' => l10n.passageOnBeginningAgain,
      'On patience' => l10n.passageOnPatience,
      'Your phrase' => l10n.yourPhrase,
      _ => title,
    };
  }

  @override
  Widget build(BuildContext context) {
    if (_challenge.isComplete) {
      return const Center(child: Icon(Icons.check_circle, size: 48));
    }
    final passage = _challenge.currentPassage;
    final totalMs = _challenge.totalDuration.inMilliseconds;
    final passageDone = _challenge.isPassageComplete;
    final isLast = _challenge.passageIndex + 1 >= widget.requiredPassages;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
            context.l10n.readingTitle(_challenge.passageIndex + 1,
                widget.requiredPassages, _passageTitle(context, passage.title)),
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        LinearProgressIndicator(
            value: _challenge.passageIndex / widget.requiredPassages),
        const SizedBox(height: 8),
        LinearProgressIndicator(
          value: totalMs == 0
              ? 0
              : _challenge.elapsed.inMilliseconds / totalMs,
        ),
        const SizedBox(height: 16),
        Text(
          _challenge.revealedWords.join(' '),
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: passageDone ? _next : null,
          child: Text(isLast
              ? context.l10n.readingFinish
              : context.l10n.readingNextPassage),
        ),
      ],
    );
  }
}

/// Runs the selected challenges one after another (enum order, as in the
/// original's ChallengeRunner) and calls [onAllComplete] at the end.
/// Unavailable types (Tetris, v1.1) are skipped with an honest notice.
class ChallengeRunnerView extends StatefulWidget {
  const ChallengeRunnerView({
    super.key,
    required this.types,
    required this.customPhrases,
    required this.onAllComplete,
  });

  final List<ChallengeType> types;
  final List<String> customPhrases;
  final VoidCallback onAllComplete;

  @override
  State<ChallengeRunnerView> createState() => _ChallengeRunnerViewState();
}

class _ChallengeRunnerViewState extends State<ChallengeRunnerView> {
  late final List<ChallengeType> _queue;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    final sorted = [...widget.types]..sort((a, b) => a.index.compareTo(b.index));
    _queue = sorted.where((t) => t.isAvailableInV1).toList();
  }

  bool get _skippedTetris => widget.types.contains(ChallengeType.tetris);

  void _next() {
    setState(() => _index++);
    if (_index >= _queue.length) widget.onAllComplete();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_skippedTetris)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(context.l10n.tetrisSkippedNote),
          ),
        if (_queue.isEmpty)
          FilledButton(
            onPressed: widget.onAllComplete,
            child: Text(context.l10n.continueAction),
          )
        else if (_index < _queue.length)
          switch (_queue[_index]) {
            ChallengeType.math => MathChallengeView(onComplete: _next),
            ChallengeType.words => WordsChallengeView(onComplete: _next),
            ChallengeType.reading => ReadingChallengeView(
                onComplete: _next,
                customPhrases: widget.customPhrases,
              ),
            ChallengeType.tetris => const SizedBox.shrink(), // filtered above
          },
      ],
    );
  }
}

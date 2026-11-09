/// Challenge screens (F22, v1 subset): Math, Words, Reading. Tetris is
/// v1.1 and is never presented as playable — see the selection UI in the
/// Impulse Lock screen, which labels it unavailable.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../domain/challenges.dart';

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
        _feedback = 'Not quite — try again.';
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
        Text('Solve ${MathChallenge.requiredProblems} problems',
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
            labelText: 'Answer',
            errorText: _feedback,
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (_) => _submit(),
        ),
        const SizedBox(height: 12),
        FilledButton(onPressed: _submit, child: const Text('Check')),
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
  String? _feedback;

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

  void _submit() {
    final ok = _challenge.submit(_input.text);
    setState(() {
      _input.clear();
      _feedback = ok
          ? null
          : 'Wrong word — the streak restarts, as designed. This friction is the point.';
      if (_challenge.isComplete) widget.onComplete();
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
        Text('Type ${widget.requiredWords} words correctly in a row',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        LinearProgressIndicator(value: _challenge.index / widget.requiredWords),
        const SizedBox(height: 16),
        Text(
          _challenge.currentWord,
          style: Theme.of(context).textTheme.headlineMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _input,
          textAlign: TextAlign.center,
          autocorrect: false,
          decoration: InputDecoration(
            labelText: 'Type the word',
            errorText: _feedback,
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (_) => _submit(),
        ),
        const SizedBox(height: 12),
        FilledButton(onPressed: _submit, child: const Text('Check')),
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

  @override
  void initState() {
    super.initState();
    final passages = <ReadingPassage>[
      ...samplePassages,
      for (final p in widget.customPhrases)
        if (p.trim().isNotEmpty) ReadingPassage('Your phrase', p.trim()),
    ];
    _challenge = ReadingChallenge(
      passages: passages,
      requiredPassages: widget.requiredPassages,
    );
    _timer = Timer.periodic(_challenge.wordInterval, (_) {
      if (!mounted) return;
      setState(() {
        _challenge.tick();
        if (_challenge.isComplete) {
          _timer?.cancel();
          widget.onComplete();
        }
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_challenge.isComplete) {
      return const Center(child: Icon(Icons.check_circle, size: 48));
    }
    final passage = _challenge.currentPassage;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Read slowly — passage ${_challenge.passageIndex + 1} of '
            '${widget.requiredPassages}: ${passage.title}',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        LinearProgressIndicator(
            value: _challenge.passageIndex / widget.requiredPassages),
        const SizedBox(height: 16),
        Text(
          _challenge.revealedWords.join(' '),
          style: Theme.of(context).textTheme.bodyLarge,
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
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Text(
              'Note: the Tetris challenge is not available in this version '
              '(v1.1) and was skipped — it was not simulated.',
            ),
          ),
        if (_queue.isEmpty)
          FilledButton(
            onPressed: widget.onAllComplete,
            child: const Text('Continue to recovery code'),
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

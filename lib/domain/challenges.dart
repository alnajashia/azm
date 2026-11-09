/// Access challenges (F22) — pure Dart logic.
///
/// v1 ships Math, Words and Reading. **Tetris is v1.1** (ARCH §6.2): the enum
/// value exists so stored configs round-trip, but the runner treats it as
/// unavailable and the selection UI labels it as such — never as playable.
///
/// Reading passages below are a small ORIGINAL sample set written for this
/// rebuild plus user-supplied custom phrases. The original app bundles a
/// 423-line corpus of Bible/Quran/quote texts; that corpus is not copied.
library;

import 'dart:math';

enum ChallengeType { math, words, tetris, reading }

extension ChallengeTypeInfo on ChallengeType {
  String get label => switch (this) {
        ChallengeType.math => 'Math problems',
        ChallengeType.words => 'Typing words',
        ChallengeType.tetris => 'Tetris',
        ChallengeType.reading => 'Reflective reading',
      };

  /// Tetris has no v1 implementation (full game engine, ARCH §6.2).
  bool get isAvailableInV1 => this != ChallengeType.tetris;
}

// --------------------------------------------------------------------- Math

class MathProblem {
  const MathProblem(this.prompt, this.answer);
  final String prompt;
  final int answer;
  bool check(int? value) => value != null && value == answer;
}

class MathChallenge {
  MathChallenge({Random? random, this.count = requiredProblems})
      : _random = random ?? Random();

  static const requiredProblems = 5;

  final Random _random;
  final int count;
  final List<MathProblem> _problems = [];
  int _solved = 0;

  List<MathProblem> get problems => List.unmodifiable(_problems);
  int get solved => _solved;
  bool get isComplete => _solved >= count;
  MathProblem get current => _problems[_solved];

  void start() {
    _problems
      ..clear()
      ..addAll(List.generate(count, (_) => _generate()));
    _solved = 0;
  }

  MathProblem _generate() {
    switch (_random.nextInt(4)) {
      case 0:
        final a = 12 + _random.nextInt(88), b = 12 + _random.nextInt(88);
        return MathProblem('$a + $b', a + b);
      case 1:
        final a = 30 + _random.nextInt(90), b = 5 + _random.nextInt(a - 5);
        return MathProblem('$a − $b', a - b);
      case 2:
        final a = 3 + _random.nextInt(10), b = 3 + _random.nextInt(10);
        return MathProblem('$a × $b', a * b);
      default:
        final b = 3 + _random.nextInt(9), q = 3 + _random.nextInt(11);
        return MathProblem('${b * q} ÷ $b', q);
    }
  }

  /// Returns true when the answer is right and advances. A wrong answer
  /// does not advance (the original requires the full set solved in a row).
  bool submit(int? value) {
    if (isComplete) return false;
    if (!current.check(value)) return false;
    _solved++;
    return true;
  }
}

// -------------------------------------------------------------------- Words

class WordsChallenge {
  WordsChallenge({Random? random, List<String>? wordPool, this.requiredWords = 32})
      : _random = random ?? Random(),
        _wordPool = wordPool ?? defaultWordPool;

  /// The original requires typing 32 words correctly in a row.
  final int requiredWords;
  final Random _random;
  final List<String> _wordPool;
  final List<String> _sequence = [];
  int _index = 0;

  static const defaultWordPool = [
    'patience', 'freedom', 'discipline', 'future', 'strength', 'calm',
    'focus', 'purpose', 'honest', 'steady', 'breathe', 'control',
    'choice', 'habit', 'resolve', 'clarity', 'courage', 'simple',
    'present', 'growth', 'mindful', 'gentle', 'firm', 'awake',
  ];

  List<String> get sequence => List.unmodifiable(_sequence);
  int get index => _index;
  bool get isComplete => _index >= requiredWords;
  String get currentWord => _sequence[_index];

  void start() {
    _sequence
      ..clear()
      ..addAll(List.generate(
          requiredWords, (_) => _wordPool[_random.nextInt(_wordPool.length)]));
    _index = 0;
  }

  /// Exact match advances; a mistake restarts the streak from zero, as in
  /// the original ("correctly in a row").
  bool submit(String typed) {
    if (isComplete) return false;
    if (typed.trim() == currentWord) {
      _index++;
      return true;
    }
    _index = 0;
    return false;
  }
}

// ------------------------------------------------------------------ Reading

class ReadingPassage {
  const ReadingPassage(this.title, this.text);
  final String title;
  final String text;
  List<String> get words => text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
}

/// Small original sample set written for this rebuild (public-domain-style
/// reflective prose composed for the app — NOT the original's bundled
/// Bible/Quran/quotes corpus). Users can add custom phrases in settings.
const samplePassages = <ReadingPassage>[
  ReadingPassage(
    'On waiting',
    'An urge is a wave. It rises, it peaks, and it falls whether you act on '
        'it or not. You do not have to obey a feeling to respect it. Sit '
        'still, breathe slowly, and let the wave pass through you and out '
        'the other side. What remains after it passes is your own clear mind.',
  ),
  ReadingPassage(
    'On the future self',
    'Every choice is a letter to the person you will be tomorrow. Write '
        'letters you will be glad to receive. The small act of restraint '
        'today becomes the quiet confidence of next week, and the habit of '
        'a lifetime is built from single, ordinary, unglamorous moments '
        'exactly like this one.',
  ),
  ReadingPassage(
    'On attention',
    'Attention is the rarest thing you own. Whatever you feed it grows, '
        'and whatever you starve fades. Guard the gates of your eyes and '
        'your time as you would guard the door of your house, because what '
        'enters shapes the rooms inside it.',
  ),
  ReadingPassage(
    'On beginning again',
    'A lapse is information, not a verdict. Notice what happened, name '
        'the trigger honestly, and begin again at the very next moment — '
        'not next week, not next year. The chain is repaired link by link, '
        'and the next link is always the one in your hand right now.',
  ),
  ReadingPassage(
    'On patience',
    'Slow is not the same as stopped. A tree does not strain to grow; it '
        'simply keeps its place in the sun and the rain, season after '
        'season. Keep your place. The work that lasts is almost never the '
        'work that hurries.',
  ),
];

/// Timed word-by-word reveal model for the reading challenge. The challenge
/// completes only after every word of the required number of passages has
/// been revealed (default 5 passages, as in the original).
class ReadingChallenge {
  ReadingChallenge({
    required List<ReadingPassage> passages,
    this.requiredPassages = 5,
    this.wordInterval = const Duration(milliseconds: 450),
  }) : passages = passages.isEmpty ? samplePassages : passages;

  final List<ReadingPassage> passages;
  final int requiredPassages;
  final Duration wordInterval;

  int _passageIndex = 0;
  int _wordIndex = 0; // words revealed so far in the current passage

  int get passageIndex => _passageIndex;
  int get wordIndex => _wordIndex;
  ReadingPassage get currentPassage => passages[_passageIndex % passages.length];
  bool get isComplete => _passageIndex >= requiredPassages;

  List<String> get revealedWords =>
      currentPassage.words.take(_wordIndex).toList();

  /// Advances the reveal by one word (or finishes the passage / challenge).
  /// Returns false when already complete.
  bool tick() {
    if (isComplete) return false;
    if (_wordIndex < currentPassage.words.length) {
      _wordIndex++;
      return true;
    }
    _passageIndex++;
    _wordIndex = 0;
    return true;
  }

  void reset() {
    _passageIndex = 0;
    _wordIndex = 0;
  }
}

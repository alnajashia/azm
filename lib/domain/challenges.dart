/// Access challenges (F22) — pure Dart logic, ported line-by-line from the
/// original `screens/challenges/ChallengeScreens.kt` (math + words) and
/// `screens/challenges/ReadingChallenge.kt` (reading pace).
///
/// v1 ships Math, Words and Reading. **Tetris is v1.1** (ARCH §6.2): the enum
/// value exists so stored configs round-trip, but the runner treats it as
/// unavailable and the selection UI labels it as such — never as playable.
///
/// UPDATE (Batch I-C, item 2): Tetris IS implemented now — the engine
/// below (`TetrisGame`) and the UI in `lib/ui/tetris_challenge.dart`.
/// `isAvailableInV1` returns true for every type; the v1.1 comment above
/// is kept as history only.
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
  ///
  /// UPDATE (Batch I-C): implemented — see `TetrisGame` below.
  bool get isAvailableInV1 => true;
}

// --------------------------------------------------------------------- Math

class MathProblem {
  const MathProblem(this.prompt, this.answer);
  final String prompt;
  final int answer;
  bool check(int? value) => value != null && value == answer;
}

/// Port of the original `MathChallenge` composable: **addition only**, both
/// operands drawn from `Random.nextInt(10, 99)` (i.e. 10..98), 5 problems,
/// one problem at a time. A correct answer advances to a freshly generated
/// problem; a **wrong answer resets progress to zero** and also generates a
/// fresh problem (the original's `else` branch in the confirm handler).
class MathChallenge {
  MathChallenge({Random? random, this.count = requiredProblems})
      : _random = random ?? Random();

  static const requiredProblems = 5;

  final Random _random;
  final int count;
  int _solved = 0;
  MathProblem? _currentProblem;

  int get solved => _solved;
  bool get isComplete => _solved >= count;
  MathProblem get current => _currentProblem ??= _generate();

  void start() {
    _solved = 0;
    _currentProblem = _generate();
  }

  MathProblem _generate() {
    final a = 10 + _random.nextInt(89); // Kotlin nextInt(10, 99): 10..98
    final b = 10 + _random.nextInt(89);
    return MathProblem('$a + $b', a + b);
  }

  /// Submits an answer for the current problem. Correct: advances (and
  /// generates the next problem). Wrong — including an unparseable/empty
  /// answer, which the original treats the same way (`toIntOrNull()` !=
  /// result): **progress resets to zero** and a fresh problem is generated.
  /// Returns true only when the answer was correct.
  bool submit(int? value) {
    if (isComplete) return false;
    if (current.check(value)) {
      _solved++;
      if (!isComplete) _currentProblem = _generate();
      return true;
    }
    _solved = 0;
    _currentProblem = _generate();
    return false;
  }
}

// -------------------------------------------------------------------- Words

/// One character of the target word as the original colours it: [correct]
/// when the typed character matches, [wrong] when it doesn't, [untyped]
/// when nothing has been typed at that position yet.
enum WordCharState { untyped, correct, wrong }

/// Port of the original `WordChallenge` composable: type **32 words**, one
/// at a time, from the 200-word pool in [defaultWordPool]. Checking is
/// **per-keystroke**: the input is lowercased and truncated to the target
/// word's length, mismatched characters are simply shown as wrong, and the
/// moment the input equals the target word the challenge advances and the
/// input clears. There is no failure state and no streak reset — a mistyped
/// word just sits there until it is fixed or erased.
class WordsChallenge {
  WordsChallenge({Random? random, List<String>? wordPool, this.requiredWords = defaultRequiredWords})
      : _random = random ?? Random(),
        _wordPool = wordPool ?? defaultWordPool;

  /// The original requires typing 32 words (`currentIndex + 1 >= 32`).
  static const defaultRequiredWords = 32;

  /// The original pre-selects 48 words (`List(48) { … }`) even though only
  /// 32 are needed to finish.
  static const selectedWords = 48;

  final int requiredWords;
  final Random _random;
  final List<String> _wordPool;
  final List<String> _sequence = [];
  int _index = 0;
  String _input = '';

  /// The original's `COMMON_WORDS` pool (200 five-letter words), verbatim.
  static const defaultWordPool = [
    'about', 'after', 'agent', 'ahead', 'album', 'alike', 'allow', 'along', 'among', 'anger',
    'angry', 'apple', 'arena', 'arise', 'armor', 'asked', 'avoid', 'aware', 'baker', 'basis',
    'began', 'being', 'bench', 'black', 'blame', 'blast', 'block', 'board', 'booth', 'brain',
    'brave', 'break', 'brief', 'broad', 'brown', 'built', 'buyer', 'candy', 'catch', 'chain',
    'chart', 'cheap', 'chest', 'child', 'chose', 'claim', 'clean', 'clerk', 'cliff', 'clock',
    'cloud', 'coast', 'court', 'craft', 'crazy', 'crime', 'crowd', 'crude', 'cycle', 'dance',
    'death', 'delay', 'doubt', 'draft', 'dream', 'drill', 'drive', 'eager', 'earth', 'elite',
    'enemy', 'enter', 'equal', 'event', 'exact', 'extra', 'false', 'fiber', 'fifth', 'fight',
    'first', 'flash', 'floor', 'focus', 'forth', 'forum', 'frame', 'fraud', 'front', 'fully',
    'giant', 'glass', 'grace', 'grand', 'grass', 'great', 'gross', 'guard', 'guest', 'happy',
    'heart', 'horse', 'house', 'image', 'inner', 'japan', 'judge', 'known', 'labor', 'laser',
    'laugh', 'learn', 'leave', 'level', 'limit', 'lives', 'logic', 'lower', 'lunch', 'major',
    'march', 'maybe', 'meant', 'metal', 'minor', 'mixed', 'money', 'moral', 'mount', 'mouth',
    'music', 'nerve', 'newly', 'north', 'novel', 'occur', 'offer', 'order', 'ought', 'panel',
    'party', 'phase', 'photo', 'pilot', 'place', 'plane', 'plate', 'pound', 'press', 'pride',
    'print', 'prize', 'proud', 'queen', 'quick', 'quite', 'radio', 'range', 'ratio', 'ready',
    'rebel', 'relax', 'right', 'river', 'rough', 'route', 'rural', 'scene', 'score', 'serve',
    'shade', 'shall', 'share', 'sheet', 'shell', 'shine', 'shock', 'shore', 'shown', 'since',
    'skill', 'slide', 'smart', 'smoke', 'solve', 'sound', 'space', 'speak', 'spend', 'split',
    'staff', 'stake', 'stark', 'state', 'steel', 'stick', 'stock', 'store', 'story', 'strip',
  ];

  List<String> get sequence => List.unmodifiable(_sequence);
  int get index => _index;
  bool get isComplete => _index >= requiredWords;

  /// The word currently being typed. Empty before [start] has populated
  /// the sequence (and after completion): reading it early is a display
  /// no-op, never a range error (v1.0.5 audit B-14).
  String get currentWord =>
      _index < _sequence.length ? _sequence[_index] : '';

  /// What has been typed toward [currentWord] so far (lowercased, at most
  /// the word's length). The UI mirrors its text field to this value: after
  /// a word completes, the input resets to empty for the next word.
  String get input => _input;

  /// Per-character state of the current word for colouring, exactly as the
  /// original's annotated string: untyped past the input length, correct
  /// where the characters match, wrong where they don't.
  List<WordCharState> get charStates => [
        for (var i = 0; i < currentWord.length; i++)
          if (i >= _input.length)
            WordCharState.untyped
          else if (_input[i] == currentWord[i])
            WordCharState.correct
          else
            WordCharState.wrong,
      ];

  void start() {
    final picks = max(selectedWords, requiredWords);
    _sequence
      ..clear()
      ..addAll(List.generate(
          picks, (_) => _wordPool[_random.nextInt(_wordPool.length)]));
    _index = 0;
    _input = '';
  }

  /// Feeds the text field's new value, mirroring the original's
  /// `onValueChange`: lowercase it, truncate it to the target word's
  /// length, and if it now equals the target word, clear the input and
  /// advance. Wrong characters change nothing else — there is no penalty
  /// state to reset.
  void typeInput(String value) {
    if (isComplete) return;
    final lowered = value.toLowerCase();
    _input = lowered.length > currentWord.length
        ? lowered.substring(0, currentWord.length)
        : lowered;
    if (_input == currentWord) {
      _input = '';
      _index++;
    }
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

/// One word of a passage with its character span in the source text and its
/// place on the reading timeline — the original's `TimedWord`.
class TimedWord {
  const TimedWord({
    required this.text,
    required this.start,
    required this.end,
    required this.startTime,
    required this.endTime,
  });

  final String text;

  /// Character offsets in the passage text: `[start, end)`.
  final int start;
  final int end;

  /// When this word's turn begins / ends on the reading timeline.
  final Duration startTime;
  final Duration endTime;
}

/// The original's reading pace (`ReadingChallenge.kt`): a slow, attentive
/// read — a fixed cost per word plus a bit per letter, so long words take
/// longer, and pauses where the punctuation asks for one.
abstract final class ReadingTiming {
  /// Fixed cost per word (ms).
  static const wordBaseMs = 300;

  /// Additional cost per letter/digit in the word (ms).
  static const letterMs = 45;

  /// Pause after a word ending in `, ; : — -` (ms).
  static const shortPauseMs = 250;

  /// Pause after a word ending in `. ! ?` (ms).
  static const longPauseMs = 500;

  /// Silence before the first word starts (ms).
  static const leadInMs = 600;

  /// How long a word takes to fade from "being read" to "read" after its
  /// turn ends (ms) — for the UI's colour transition.
  static const settleMs = 350;

  static final _letterOrDigit = RegExp(r'[\p{L}\p{N}]', unicode: true);

  /// Lays [text] out on the reading timeline exactly as the original's
  /// `timeWords()`: tokens are maximal non-whitespace runs; a token's
  /// duration is [wordBaseMs] + (letter/digit count × [letterMs]); the next
  /// token starts after a punctuation pause taken from the token's last
  /// character. The total includes the lead-in and the final token's pause.
  static ({List<TimedWord> words, Duration total}) timeWords(String text) {
    var cursor = leadInMs;
    final words = <TimedWord>[];
    for (final match in RegExp(r'\S+').allMatches(text)) {
      final token = match.group(0)!;
      final letters = _letterOrDigit.allMatches(token).length;
      final startMs = cursor;
      final endMs = startMs + wordBaseMs + letters * letterMs;
      cursor = endMs +
          switch (token[token.length - 1]) {
            '.' || '!' || '?' => longPauseMs,
            ',' || ';' || ':' || '—' || '-' => shortPauseMs,
            _ => 0,
          };
      words.add(TimedWord(
        text: token,
        start: match.start,
        end: match.end,
        startTime: Duration(milliseconds: startMs),
        endTime: Duration(milliseconds: endMs),
      ));
    }
    return (words: words, total: Duration(milliseconds: cursor));
  }
}

/// Timed reading model for the reading challenge. Each passage is laid out
/// with [ReadingTiming] and read against an elapsed clock the UI drives
/// (the original animates a linear tween over the passage's total time);
/// the "next" action stays locked until the current passage's timeline has
/// fully elapsed. Completes after the required number of passages (default
/// 5, as in the original's passage set size).
class ReadingChallenge {
  ReadingChallenge({
    required List<ReadingPassage> passages,
    this.requiredPassages = 5,
  }) : passages = passages.isEmpty ? samplePassages : passages {
    _loadPassage();
  }

  final List<ReadingPassage> passages;
  final int requiredPassages;

  int _passageIndex = 0;
  Duration _elapsed = Duration.zero;
  List<TimedWord> _timedWords = const [];
  Duration _totalDuration = Duration.zero;

  int get passageIndex => _passageIndex;
  ReadingPassage get currentPassage => passages[_passageIndex % passages.length];
  bool get isComplete => _passageIndex >= requiredPassages;

  /// The current passage laid out on the reading timeline.
  List<TimedWord> get timedWords => List.unmodifiable(_timedWords);

  /// Total timeline length of the current passage.
  Duration get totalDuration => _totalDuration;

  /// How far the reading clock has advanced in the current passage.
  Duration get elapsed => _elapsed;

  /// The UI may only move on once the whole timeline has elapsed — the
  /// original enables its Next/Finish button exactly at `totalMs`.
  bool get isPassageComplete => _elapsed >= _totalDuration;

  /// Words whose turn has begun at the current elapsed time.
  List<String> get revealedWords => [
        for (final w in _timedWords)
          if (w.startTime <= _elapsed) w.text,
      ];

  /// How many words' turns have begun so far in the current passage.
  int get wordIndex => revealedWords.length;

  void _loadPassage() {
    final timing = ReadingTiming.timeWords(currentPassage.text);
    _timedWords = timing.words;
    _totalDuration = timing.total;
  }

  /// Advances the reading clock by [delta], clamped at the passage's total
  /// duration (the original's animation stops at `totalMs`).
  void advance(Duration delta) {
    if (isComplete || delta.isNegative) return;
    final next = _elapsed + delta;
    _elapsed = next > _totalDuration ? _totalDuration : next;
  }

  /// Moves to the next passage once the current one has been fully read.
  /// Returns false while the passage is unfinished or the challenge is
  /// already complete.
  bool next() {
    if (isComplete || !isPassageComplete) return false;
    _passageIndex++;
    _elapsed = Duration.zero;
    if (!isComplete) _loadPassage();
    return true;
  }

  void reset() {
    _passageIndex = 0;
    _elapsed = Duration.zero;
    _loadPassage();
  }
}

// --------------------------------------------------------------------- Tetris

/// Tetris (Batch I-C, item 2): a line-by-line port of Dechainer's
/// `TetrisGame` (`screens/challenges/TetrisChallenge.kt`, Apache-2.0).
/// Pure Dart, no Flutter dependency — the UI lives in
/// `lib/ui/tetris_challenge.dart`.
///
/// Board 8 columns × 20 rows (narrower than classic 10-wide —
/// deliberate: faster play, fits a phone in portrait). 7 tetrominoes,
/// 7-bag randomiser, wall kicks (0, −1, +1, −2, +2), gravity
/// `1000ms − (level−1)×50ms` (floor 200ms), lock delay 500ms (max 15
/// resets), ghost piece, line-clear animation (320ms), top-out
/// animation (520ms).
///
/// No game over: topping out just clears the board and respawns.
/// No score or lines requirement — the challenge is TIME ONLY (the
/// widget counts active play; see `TetrisChallengeView`).
///
/// Colours: the engine stores the tetromino ordinal in the board
/// (like the original); the UI maps ordinals to colours. `lines` is
/// a plain public field (the original keeps it private-set) so tests
/// can set up a level directly; the UI only reads it.
enum TetrisGameEvent { move, rotate, lock, hardDrop, linesCleared, levelUp, topOut }

/// `(event, count)` — `count` is the lines cleared for
/// [TetrisGameEvent.linesCleared] and the new level for
/// [TetrisGameEvent.levelUp]; 0 for the rest.
typedef TetrisGameEventHandler = void Function(TetrisGameEvent event, int count);

enum Tetromino {
  i(4, [(0, 1), (1, 1), (2, 1), (3, 1)]),
  o(2, [(0, 0), (1, 0), (0, 1), (1, 1)]),
  t(3, [(1, 0), (0, 1), (1, 1), (2, 1)]),
  s(3, [(1, 0), (2, 0), (0, 1), (1, 1)]),
  z(3, [(0, 0), (1, 0), (1, 1), (2, 1)]),
  j(3, [(0, 0), (0, 1), (1, 1), (2, 1)]),
  l(3, [(2, 0), (0, 1), (1, 1), (2, 1)]);

  const Tetromino(this.boxSize, this.cells);
  final int boxSize;
  final List<(int, int)> cells;

  /// The cells for a rotation (0..3), rotated clockwise like the
  /// original: `(x, y) -> (boxSize - 1 - y, x)`, applied `rotation` times.
  List<(int, int)> rotatedCells(int rotation) {
    var result = cells;
    for (var i = 0; i < rotation % 4; i++) {
      result = [for (final (x, y) in result) (boxSize - 1 - y, x)];
    }
    return result;
  }
}

class TetrisPiece {
  const TetrisPiece(this.type, this.rotation, this.x, this.y);
  final Tetromino type;
  final int rotation;
  final int x;
  final int y;

  List<(int, int)> cells() => [
        for (final (cx, cy) in type.rotatedCells(rotation)) (x + cx, y + cy),
      ];

  TetrisPiece copyWith({Tetromino? type, int? rotation, int? x, int? y}) =>
      TetrisPiece(
        type ?? this.type,
        rotation ?? this.rotation,
        x ?? this.x,
        y ?? this.y,
      );
}

/// One drop-trail column: the piece's lowest cell in the column fell
/// from [fromY] to [toY]; [colorIndex] is the tetromino ordinal.
class TetrisDropTrail {
  const TetrisDropTrail(this.x, this.fromY, this.toY, this.colorIndex);
  final int x;
  final int fromY;
  final int toY;
  final int colorIndex;
}

class TetrisGame {
  TetrisGame({Random? random, TetrisGameEventHandler? onEvent})
      : _random = random ?? Random(),
        _onEvent = onEvent {
    _next = _nextFromBag();
    _spawnNext();
  }

  static const cols = 8;
  static const rows = 20;
  static const empty = -1;
  static const linesPerLevel = 10;
  static const lockDelayMs = 500;
  static const maxLockResets = 15;
  static const clearAnimationMs = 320;
  static const topOutAnimationMs = 520;
  static const lockFlashMs = 180;
  static const dropTrailMs = 220;
  static const levelBannerMs = 1300;

  /// The original's `Long.MIN_VALUE / 2` sentinel for "never happened".
  static const _longAgo = -1 << 62;

  final Random _random;
  final TetrisGameEventHandler? _onEvent;

  final List<int> board = List.filled(cols * rows, empty);
  final List<Tetromino> _bag = [];

  TetrisPiece? _current;
  TetrisPiece? get current => _current;

  late Tetromino _next;
  Tetromino get next => _next;

  int lines = 0;
  int get level => lines ~/ linesPerLevel + 1;

  int _clock = 0;
  int get clock => _clock;
  int _revision = 0;
  int get revision => _revision;

  List<int> _clearingRows = [];
  List<int> get clearingRows => _clearingRows;
  int _clearStartedAt = 0;
  int get clearStartedAt => _clearStartedAt;
  int? _topOutStartedAt;
  int? get topOutStartedAt => _topOutStartedAt;
  List<(int, int)> _lockFlashCells = [];
  List<(int, int)> get lockFlashCells => _lockFlashCells;
  int _lockFlashAt = _longAgo;
  int get lockFlashAt => _lockFlashAt;
  List<TetrisDropTrail> _dropTrails = [];
  List<TetrisDropTrail> get dropTrails => _dropTrails;
  int _dropTrailAt = _longAgo;
  int get dropTrailAt => _dropTrailAt;
  int _levelUpAt = _longAgo;
  int get levelUpAt => _levelUpAt;

  int _sinceGravity = 0;
  int _lockElapsed = 0;
  int _lockResets = 0;

  int get gravityIntervalMs => max(200, 1000 - (level - 1) * 50);

  Tetromino _nextFromBag() {
    if (_bag.isEmpty) {
      _bag.addAll([...Tetromino.values]..shuffle(_random));
    }
    return _bag.removeAt(0);
  }

  bool _fits(TetrisPiece piece) => piece.cells().every(
        (c) =>
            c.$1 >= 0 &&
            c.$1 < cols &&
            c.$2 >= 0 &&
            c.$2 < rows &&
            board[c.$2 * cols + c.$1] == empty,
      );

  bool _tryMove(TetrisPiece piece) {
    if (!_fits(piece)) return false;
    _current = piece;
    if (_lockElapsed > 0 && _lockResets < maxLockResets) {
      _lockElapsed = 0;
      _lockResets++;
    }
    _revision++;
    return true;
  }

  void update(int deltaMs) {
    _clock += deltaMs;
    if (_clearingRows.isNotEmpty) {
      if (_clock - _clearStartedAt >= clearAnimationMs) _finishClear();
      return;
    }
    final topOutAt = _topOutStartedAt;
    if (topOutAt != null) {
      if (_clock - topOutAt >= topOutAnimationMs) _finishTopOut();
      return;
    }
    final piece = _current;
    if (piece == null) return;
    final below = piece.copyWith(y: piece.y + 1);
    if (_fits(below)) {
      _lockElapsed = 0;
      _sinceGravity += deltaMs;
      if (_sinceGravity >= gravityIntervalMs) {
        _sinceGravity = 0;
        _tryMove(below);
      }
    } else {
      _lockElapsed += deltaMs;
      if (_lockElapsed >= lockDelayMs) _lock(hardDrop: false);
    }
  }

  void moveLeft() => _shift(-1);
  void moveRight() => _shift(1);

  void _shift(int dx) {
    final piece = _current;
    if (piece == null) return;
    if (_tryMove(piece.copyWith(x: piece.x + dx))) {
      _onEvent?.call(TetrisGameEvent.move, 0);
    }
  }

  void rotate() {
    final piece = _current;
    if (piece == null) return;
    final rotated = piece.copyWith(rotation: (piece.rotation + 1) % 4);
    for (final kick in [0, -1, 1, -2, 2]) {
      if (_tryMove(rotated.copyWith(x: rotated.x + kick))) {
        _onEvent?.call(TetrisGameEvent.rotate, 0);
        return;
      }
    }
  }

  void softDrop() {
    final piece = _current;
    if (piece == null) return;
    if (_tryMove(piece.copyWith(y: piece.y + 1))) _sinceGravity = 0;
  }

  void hardDrop() {
    final piece = _current;
    if (piece == null) return;
    final landing = ghost();
    if (landing == null) return;
    final trails = <TetrisDropTrail>[];
    final byColumn = <int, List<int>>{};
    for (final (x, y) in piece.cells()) {
      (byColumn[x] ??= []).add(y);
    }
    for (final entry in byColumn.entries) {
      final landingY = landing
          .cells()
          .where((c) => c.$1 == entry.key)
          .map((c) => c.$2)
          .reduce(min);
      final fromY = entry.value.reduce(min);
      if (landingY > fromY) {
        trails.add(TetrisDropTrail(entry.key, fromY, landingY, piece.type.index));
      }
    }
    _dropTrails = trails;
    _dropTrailAt = _clock;
    _current = landing;
    _lock(hardDrop: true);
  }

  TetrisPiece? ghost() {
    final start = _current;
    if (start == null) return null;
    var piece = start;
    while (_fits(piece.copyWith(y: piece.y + 1))) {
      piece = piece.copyWith(y: piece.y + 1);
    }
    return piece;
  }

  void _lock({required bool hardDrop}) {
    final piece = _current;
    if (piece == null) return;
    for (final (x, y) in piece.cells()) {
      board[y * cols + x] = piece.type.index;
    }
    _lockFlashCells = piece.cells();
    _lockFlashAt = _clock;
    _current = null;

    final full = [
      for (var row = 0; row < rows; row++)
        if (List.generate(cols, (col) => board[row * cols + col])
            .every((v) => v != empty))
          row,
    ];
    if (full.isNotEmpty) {
      _clearingRows = full;
      _clearStartedAt = _clock;
      _onEvent?.call(TetrisGameEvent.linesCleared, full.length);
    } else {
      _onEvent?.call(
        hardDrop ? TetrisGameEvent.hardDrop : TetrisGameEvent.lock,
        0,
      );
      _spawnNext();
    }
    _revision++;
  }

  void _finishClear() {
    final levelBefore = level;
    var writeRow = rows - 1;
    for (var row = rows - 1; row >= 0; row--) {
      if (_clearingRows.contains(row)) continue;
      if (writeRow != row) {
        for (var col = 0; col < cols; col++) {
          board[writeRow * cols + col] = board[row * cols + col];
        }
      }
      writeRow--;
    }
    for (var row = writeRow; row >= 0; row--) {
      for (var col = 0; col < cols; col++) {
        board[row * cols + col] = empty;
      }
    }
    lines += _clearingRows.length;
    _clearingRows = [];
    if (level > levelBefore) {
      _levelUpAt = _clock;
      _onEvent?.call(TetrisGameEvent.levelUp, level);
    }
    _spawnNext();
  }

  void _finishTopOut() {
    board.fillRange(0, board.length, empty);
    _topOutStartedAt = null;
    _spawnNext();
  }

  void _spawnNext() {
    final type = _next;
    _next = _nextFromBag();
    final spawned = TetrisPiece(type, 0, (cols - type.boxSize) ~/ 2, 0);
    _sinceGravity = 0;
    _lockElapsed = 0;
    _lockResets = 0;
    if (_fits(spawned)) {
      _current = spawned;
    } else {
      _topOutStartedAt = _clock;
      _onEvent?.call(TetrisGameEvent.topOut, 0);
    }
    _revision++;
  }
}

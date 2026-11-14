/// Tetris challenge view (Batch I-C, item 2) — a port of Dechainer's
/// `TetrisChallenge` composable (`screens/challenges/TetrisChallenge.kt`,
/// Apache-2.0) onto the `TetrisGame` engine in `lib/domain/challenges.dart`.
///
/// The unlock rule is TIME ONLY (Dechainer's rule, the evidence-based
/// dose): actively play for [minutes] (configurable 1–15, default 3);
/// the clock counts only while the user has given input in the last 8
/// seconds — idle longer and the game pauses (overlay) and both the
/// clock and the gravity stop. There is NO fail state: topping out
/// just clears the board. When the time is up, a Continue button
/// appears and calls [onComplete]. The only way out early is Give Up
/// (the surrounding dialog's Cancel button).
///
/// Deviations from Dechainer, documented:
/// - The drop trail is a SOLID translucent rectangle, not a vertical
///   gradient — the app has a standing no-gradient rule.
/// - Sounds are pre-generated WAV assets played with the native
///   SoundPool player (`TetrisSounds.kt`, a port of Dechainer's
///   `TetrisSounds`); the original synthesises them at runtime into
///   the cache dir. The ringer-mode check lives in the native
///   player's `play()`, like the original.
/// - The frame loop is a Flutter [Ticker] (no `withFrameMillis`);
///   frame deltas are capped at 100ms, like the original. When the app
///   is backgrounded the ticker stops firing, and the first frame back
///   is capped the same way — the idle rule then pauses the game.
/// - The board height is fixed (420 logical px) inside the scrollable
///   unlock dialog, so the game fits small phones.
library;

import 'dart:async';

import 'package:azm/data/tetris_sounds.dart';
import 'package:azm/domain/challenges.dart';
import 'package:azm/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

/// The 7 tetromino colours from Dechainer, indexed by ordinal
/// (I, O, T, S, Z, J, L). Four colours for seven pieces is the
/// original's palette — the pieces need distinguishable colours to be
/// readable as a game, so the app's red/black UI palette does not
/// apply inside the board.
const _pieceColors = <Color>[
  Color(0xFF2196F3), // I — blue
  Color(0xFFFFC107), // O — yellow
  Color(0xFFF44336), // T — red
  Color(0xFF4CAF50), // S — green
  Color(0xFFF44336), // Z — red
  Color(0xFF2196F3), // J — blue
  Color(0xFFFFC107), // L — yellow
];

enum _TetrisSound {
  move('move'),
  rotate('rotate'),
  lock('lock'),
  hardDrop('hard_drop'),
  clear('clear'),
  clearBig('clear_big'),
  levelUp('level_up'),
  topOut('top_out');

  const _TetrisSound(this.soundName);

  /// The name the native player expects (Dechainer's enum names,
  /// lowercased).
  final String soundName;
}

class TetrisChallengeView extends StatefulWidget {
  const TetrisChallengeView({
    super.key,
    required this.minutes,
    required this.soundOn,
    required this.onSoundChanged,
    required this.sounds,
    required this.onComplete,
  });

  final int minutes;
  final bool soundOn;
  final ValueChanged<bool> onSoundChanged;

  /// The native SoundPool player (created by the caller from the
  /// privileged channel); the view loads it on open and releases it
  /// on dispose.
  final TetrisSounds sounds;
  final VoidCallback onComplete;

  @override
  State<TetrisChallengeView> createState() => _TetrisChallengeViewState();
}

class _TetrisChallengeViewState extends State<TetrisChallengeView>
    with SingleTickerProviderStateMixin {
  static const _idleTimeout = Duration(milliseconds: 8000);
  static const _maxFrameDeltaMs = 100;
  static const _boardHeight = 420.0;
  static const _sidePanelWidth = 88.0;

  late final TetrisGame _game;
  late final Ticker _ticker;
  late final int _requiredMillis;
  late bool _soundOn;

  final GlobalKey _boardKey = GlobalKey();

  Duration? _lastFrame;
  Duration _lastInputAt = -_idleTimeout;
  double _dragX = 0;
  double _dragY = 0;
  int _playedMillis = 0;
  bool _isPlaying = false;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _requiredMillis = widget.minutes * 60000;
    _soundOn = widget.soundOn;
    _game = TetrisGame(onEvent: _onGameEvent);
    unawaited(widget.sounds.load());
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    unawaited(widget.sounds.release());
    super.dispose();
  }

  void _onGameEvent(TetrisGameEvent event, int count) {
    final (sound, haptic) = switch (event) {
      TetrisGameEvent.move => (_TetrisSound.move, null),
      TetrisGameEvent.rotate => (_TetrisSound.rotate, null),
      // Dechainer: SegmentTick / VirtualKey / Confirm / LongPress /
      // Reject — Flutter has no exact equivalents; the mapping below
      // keeps the same relative strength.
      TetrisGameEvent.lock => (
          _TetrisSound.lock,
          HapticFeedback.selectionClick,
        ),
      TetrisGameEvent.hardDrop => (
          _TetrisSound.hardDrop,
          HapticFeedback.lightImpact,
        ),
      TetrisGameEvent.linesCleared => (
          count >= 3 ? _TetrisSound.clearBig : _TetrisSound.clear,
          count >= 3
              ? HapticFeedback.heavyImpact
              : HapticFeedback.mediumImpact,
        ),
      TetrisGameEvent.levelUp => (
          _TetrisSound.levelUp,
          HapticFeedback.mediumImpact,
        ),
      TetrisGameEvent.topOut => (
          _TetrisSound.topOut,
          HapticFeedback.heavyImpact,
        ),
    };
    if (_soundOn) unawaited(_playSound(sound));
    haptic?.call();
  }

  Future<void> _playSound(_TetrisSound sound) async {
    // The wrapper swallows audio failures (no channel in tests, a
    // missing sound on device) — audio must never break the game.
    await widget.sounds.play(sound.soundName);
  }

  void _onTick(Duration elapsed) {
    final deltaMs = _lastFrame == null
        ? 0
        : (elapsed - _lastFrame!).inMilliseconds.clamp(0, _maxFrameDeltaMs);
    _lastFrame = elapsed;
    final playing = elapsed - _lastInputAt < _idleTimeout;
    if (!playing) {
      if (_isPlaying) setState(() => _isPlaying = false);
      return;
    }
    if (!_isPlaying) setState(() => _isPlaying = true);
    if (!_finished) {
      _playedMillis += deltaMs;
      if (_playedMillis >= _requiredMillis) {
        _finished = true;
        HapticFeedback.mediumImpact();
      }
    }
    _game.update(deltaMs);
    setState(() {});
  }

  /// Any input resets the 8-second idle window, then runs the action.
  void _input(void Function() action) {
    _lastInputAt = _lastFrame ?? Duration.zero;
    action();
  }

  void _applyDrag() {
    final box =
        _boardKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final cell = box.size.width / TetrisGame.cols;
    while (_dragX.abs() >= cell) {
      if (_dragX > 0) {
        _input(_game.moveRight);
      } else {
        _input(_game.moveLeft);
      }
      _dragX -= _dragX > 0 ? cell : -cell;
    }
    while (_dragY >= cell) {
      _input(_game.softDrop);
      _dragY -= cell;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final remainingSeconds =
        ((_requiredMillis - _playedMillis).clamp(0, _requiredMillis) + 999) ~/
            1000;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: _boardHeight,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Center(
                  child: AspectRatio(
                    aspectRatio: TetrisGame.cols / TetrisGame.rows,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        GestureDetector(
                          key: _boardKey,
                          onTap: () => _input(_game.rotate),
                          onPanStart: (_) {
                            _dragX = 0;
                            _dragY = 0;
                          },
                          onPanUpdate: (details) {
                            _dragX += details.delta.dx;
                            _dragY += details.delta.dy;
                            _applyDrag();
                          },
                          child: CustomPaint(
                            painter: _TetrisBoardPainter(
                              _game,
                              boardColor: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHighest,
                              gridColor: Theme.of(context)
                                  .colorScheme
                                  .outlineVariant,
                              ghostColor: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                              flashColor: Colors.white,
                            ),
                          ),
                        ),
                        if (!_isPlaying)
                          GestureDetector(
                            onTap: () => _input(() {}),
                            child: _PausedOverlay(),
                          ),
                        _LevelBanner(_game),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: _sidePanelWidth,
                child: _sidePanel(context, l10n, remainingSeconds),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _controlButton(
              icon: Icons.keyboard_arrow_left_outlined,
              tooltip: l10n.tetrisMoveLeft,
              repeatMs: 50,
              onPress: () => _input(_game.moveLeft),
            ),
            _controlButton(
              icon: Icons.rotate_right_outlined,
              tooltip: l10n.tetrisRotate,
              onPress: () => _input(_game.rotate),
            ),
            _controlButton(
              icon: Icons.keyboard_arrow_right_outlined,
              tooltip: l10n.tetrisMoveRight,
              repeatMs: 50,
              onPress: () => _input(_game.moveRight),
            ),
            _controlButton(
              icon: Icons.keyboard_arrow_down_outlined,
              tooltip: l10n.tetrisSoftDrop,
              repeatMs: 35,
              onPress: () => _input(_game.softDrop),
            ),
            _controlButton(
              icon: Icons.keyboard_double_arrow_down_outlined,
              tooltip: l10n.tetrisHardDrop,
              onPress: () => _input(_game.hardDrop),
            ),
          ],
        ),
      ],
    );
  }

  Widget _sidePanel(
    BuildContext context,
    AppLocalizations l10n,
    int remainingSeconds,
  ) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (_finished)
          FilledButton(
            onPressed: widget.onComplete,
            child: Text(l10n.tetrisContinue, maxLines: 1),
          )
        else ...[
          Text(
            '${(remainingSeconds ~/ 60).toString().padLeft(2, '0')}:${(remainingSeconds % 60).toString().padLeft(2, '0')}',
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: LinearProgressIndicator(
              value: (_playedMillis / _requiredMillis).clamp(0.0, 1.0),
            ),
          ),
        ],
        const SizedBox(height: 16),
        Text(l10n.tetrisNext, style: theme.textTheme.labelLarge),
        const SizedBox(height: 4),
        SizedBox(
          width: 56,
          height: 56,
          child: CustomPaint(painter: _TetrisNextPainter(_game.next)),
        ),
        const SizedBox(height: 16),
        Text(
          l10n.tetrisLines(_game.lines),
          style: theme.textTheme.bodyMedium,
        ),
        Text(
          l10n.tetrisLevel(_game.level),
          style: theme.textTheme.bodyMedium,
        ),
        const Spacer(),
        IconButton(
          onPressed: () {
            setState(() => _soundOn = !_soundOn);
            widget.onSoundChanged(_soundOn);
          },
          icon: Icon(
            _soundOn
                ? Icons.volume_up_outlined
                : Icons.volume_off_outlined,
          ),
          tooltip: _soundOn ? l10n.tetrisSoundOn : l10n.tetrisSoundOff,
        ),
      ],
    );
  }

  Widget _controlButton({
    required IconData icon,
    required String tooltip,
    int? repeatMs,
    required VoidCallback onPress,
  }) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: _HoldButton(
          icon: icon,
          tooltip: tooltip,
          repeatMs: repeatMs,
          onPress: onPress,
        ),
      ),
    );
  }
}

/// A press-and-hold button: fires once on press, then (when
/// [repeatMs] is set) repeats after a 170ms delay every [repeatMs]
/// — Dechainer's `ControlButton` (press-interaction) logic, ported
/// to a `Listener` because Flutter buttons have no hold repeat.
class _HoldButton extends StatefulWidget {
  const _HoldButton({
    required this.icon,
    required this.tooltip,
    this.repeatMs,
    required this.onPress,
  });

  final IconData icon;
  final String tooltip;
  final int? repeatMs;
  final VoidCallback onPress;

  @override
  State<_HoldButton> createState() => _HoldButtonState();
}

class _HoldButtonState extends State<_HoldButton> {
  Timer? _repeatTimer;

  void _start() {
    widget.onPress();
    if (widget.repeatMs == null) return;
    _repeatTimer = Timer(const Duration(milliseconds: 170), () {
      _repeatTimer = Timer.periodic(
        Duration(milliseconds: widget.repeatMs!),
        (_) => widget.onPress(),
      );
    });
  }

  void _stop() {
    _repeatTimer?.cancel();
    _repeatTimer = null;
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Tooltip(
      message: widget.tooltip,
      child: SizedBox(
        height: 56,
        child: Listener(
          onPointerDown: (_) => _start(),
          onPointerUp: (_) => _stop(),
          onPointerCancel: (_) => _stop(),
          child: Material(
            color: colors.primaryContainer,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () {},
              child: Icon(
                widget.icon,
                size: 32,
                color: colors.onPrimaryContainer,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PausedOverlay extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color:
            Theme.of(context).colorScheme.surface.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(16),
      alignment: Alignment.center,
      child: Text(
        context.l10n.tetrisPaused,
        style: Theme.of(context).textTheme.titleMedium,
        textAlign: TextAlign.center,
      ),
    );
  }
}

class _LevelBanner extends StatelessWidget {
  const _LevelBanner(this.game);
  final TetrisGame game;

  @override
  Widget build(BuildContext context) {
    final progress =
        (game.clock - game.levelUpAt) / TetrisGame.levelBannerMs;
    if (progress < 0 || progress > 1) return const SizedBox.shrink();
    final pop = (progress / 0.2).clamp(0.0, 1.0);
    final scale = 1.4 - 0.4 * pop;
    final alpha = progress < 0.75 ? pop : (1 - progress) / 0.25;
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: Opacity(
        opacity: alpha,
        child: Transform.scale(
          scale: scale,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              color: colors.primaryContainer,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Text(
              context.l10n.tetrisLevel(game.level),
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colors.onPrimaryContainer,
                  ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TetrisBoardPainter extends CustomPainter {
  _TetrisBoardPainter(
    this.game, {
    required this.boardColor,
    required this.gridColor,
    required this.ghostColor,
    required this.flashColor,
  }) : revision = game.revision;

  final TetrisGame game;

  /// Captured at construction: the delegate holds the same game
  /// instance across builds, so reading `game.revision` on the old
  /// delegate would always give the CURRENT revision.
  final int revision;
  final Color boardColor;
  final Color gridColor;
  final Color ghostColor;
  final Color flashColor;

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / TetrisGame.cols;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Offset.zero & size,
        const Radius.circular(8),
      ),
      Paint()..color = boardColor,
    );
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var col = 1; col < TetrisGame.cols; col++) {
      canvas.drawLine(
        Offset(col * cell, 0),
        Offset(col * cell, size.height),
        gridPaint,
      );
    }
    for (var row = 1; row < TetrisGame.rows; row++) {
      canvas.drawLine(
        Offset(0, row * cell),
        Offset(size.width, row * cell),
        gridPaint,
      );
    }

    final clock = game.clock;
    final topOutAt = game.topOutStartedAt;
    final topOutProgress = topOutAt == null
        ? null
        : ((clock - topOutAt) / TetrisGame.topOutAnimationMs)
            .clamp(0.0, 1.0);
    final clearProgress =
        ((clock - game.clearStartedAt) / TetrisGame.clearAnimationMs)
            .clamp(0.0, 1.0);

    for (var row = 0; row < TetrisGame.rows; row++) {
      final clearing = game.clearingRows.contains(row);
      for (var col = 0; col < TetrisGame.cols; col++) {
        final value = game.board[row * TetrisGame.cols + col];
        if (value == TetrisGame.empty) continue;
        final color = _pieceColors[value];
        if (topOutProgress != null) {
          final rowDelay =
              (TetrisGame.rows - 1 - row) / TetrisGame.rows * 0.5;
          final local =
              ((topOutProgress - rowDelay) / 0.5).clamp(0.0, 1.0);
          _drawCell(
            canvas,
            col,
            row,
            cell,
            color.withValues(alpha: 1 - local),
            scale: 1 - local * 0.6,
          );
        } else if (clearing && clearProgress < 0.4) {
          _drawCell(canvas, col, row, cell, color);
          final pulse =
              ((clearProgress / 0.1).floor() % 2 == 0) ? 0.85 : 0.35;
          _drawCell(
            canvas,
            col,
            row,
            cell,
            flashColor.withValues(alpha: pulse),
          );
        } else if (clearing) {
          final shrink = (clearProgress - 0.4) / 0.6;
          _drawCell(
            canvas,
            col,
            row,
            cell,
            flashColor.withValues(alpha: 1 - shrink),
            scale: 1 - shrink,
          );
        } else {
          _drawCell(canvas, col, row, cell, color);
        }
      }
    }

    // Drop trail — SOLID translucent (the no-gradient rule), fading
    // with the animation progress, like the original's gradient did.
    final trailProgress =
        (clock - game.dropTrailAt) / TetrisGame.dropTrailMs;
    if (trailProgress >= 0 && trailProgress <= 1) {
      for (final trail in game.dropTrails) {
        canvas.drawRect(
          Rect.fromLTWH(
            trail.x * cell + cell * 0.15,
            trail.fromY * cell,
            cell * 0.7,
            (trail.toY - trail.fromY) * cell,
          ),
          Paint()
            ..color = _pieceColors[trail.colorIndex]
                .withValues(alpha: 0.45 * (1 - trailProgress)),
        );
      }
    }

    final flashProgress =
        (clock - game.lockFlashAt) / TetrisGame.lockFlashMs;
    if (flashProgress >= 0 &&
        flashProgress <= 1 &&
        game.clearingRows.isEmpty) {
      for (final (x, y) in game.lockFlashCells) {
        _drawCell(
          canvas,
          x,
          y,
          cell,
          flashColor.withValues(alpha: 0.55 * (1 - flashProgress)),
        );
      }
    }

    final ghost = game.ghost();
    if (ghost != null) {
      for (final (x, y) in ghost.cells()) {
        _drawCell(canvas, x, y, cell, ghostColor, outline: true);
      }
    }
    final current = game.current;
    if (current != null) {
      for (final (x, y) in current.cells()) {
        _drawCell(canvas, x, y, cell, _pieceColors[current.type.index]);
      }
    }
  }

  void _drawCell(
    Canvas canvas,
    int col,
    int row,
    double cell,
    Color color, {
    bool outline = false,
    double scale = 1,
  }) {
    final inset = 1.5 + (cell / 2 - 1.5) * (1 - scale);
    final rect = Rect.fromLTWH(
      col * cell + inset,
      row * cell + inset,
      cell - inset * 2,
      cell - inset * 2,
    );
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(3));
    if (outline) {
      canvas.drawRRect(
        rrect,
        Paint()
          ..color = color.withValues(alpha: 0.5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    } else {
      canvas.drawRRect(rrect, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(covariant _TetrisBoardPainter oldDelegate) =>
      oldDelegate.revision != revision;
}

/// The next-piece preview: the piece drawn in a 4×4 grid, like the
/// original's 56dp canvas.
class _TetrisNextPainter extends CustomPainter {
  const _TetrisNextPainter(this.next);
  final Tetromino next;

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / 4;
    final offset = (4 - next.boxSize) / 2;
    for (final (x, y) in next.cells) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            (x + offset) * cell + 1,
            (y + offset) * cell + 1,
            cell - 2,
            cell - 2,
          ),
          const Radius.circular(3),
        ),
        Paint()..color = _pieceColors[next.index],
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TetrisNextPainter oldDelegate) =>
      oldDelegate.next != next;
}

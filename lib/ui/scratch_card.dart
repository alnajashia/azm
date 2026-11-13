/// Scratch-to-reveal card for the recovery code (Batch B / Audit Item 13).
///
/// Features:
/// - Opaque FLAT cover (#0B0B0C in dark mode, #D90429 in light mode, no gradients).
/// - CustomPainter + drag erase via BlendMode.dstOut on an offscreen canvas.
/// - Checkpoint grid tracks erase coverage: ~20% erased fades cover and triggers onRevealed.
///   (Batch F, item 2: the old 60% threshold made scratching feel slow —
///   the user had to scrub most of the card. One swipe now reveals.)
/// - TalkBack / screen-reader "show code" accessibility alternative.
/// - Constrains repaints with RepaintBoundary.
/// - The code/hint TextPainters are laid out ONCE per card size in the
///   state and handed to the painter ready-made: laying them out on
///   every paint frame was the other half of the slowness (a full
///   saveLayer redraw plus two text layouts per finger-move event).
library;

import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../theme.dart';

class ScratchCard extends StatefulWidget {
  const ScratchCard({
    super.key,
    required this.child,
    required this.onRevealed,
    this.text,
    this.textStyle,
    this.revealed = false,
    this.threshold = 0.20,
    this.coverColor,
    this.scratchRadius = 30.0,
  });

  final Widget child;
  final VoidCallback onRevealed;
  final String? text;
  final TextStyle? textStyle;
  final bool revealed;
  final double threshold;
  final Color? coverColor;
  final double scratchRadius;

  @override
  State<ScratchCard> createState() => _ScratchCardState();
}

class _ScratchCardState extends State<ScratchCard>
    with SingleTickerProviderStateMixin {
  final Path _scratchPath = Path();
  final Set<int> _erasedCheckpoints = <int>{};
  static const int _gridCols = 20;
  static const int _gridRows = 10;
  static const int _totalCheckpoints = _gridCols * _gridRows;

  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  bool _thresholdReached = false;

  // Laid-out text painters, cached per card size (Batch F, item 2).
  // The painter used to call TextPainter.layout() on EVERY paint frame;
  // now the state lays them out once and the painter only paints.
  // The cache key is size + code text + hint text, so a regenerated
  // code or a locale change re-lays out exactly once.
  Size? _painterSize;
  String? _painterText;
  String? _painterHint;
  TextPainter? _codePainter;
  TextPainter? _hintPainter;

  void _ensurePainters(Size size, TextStyle? codeStyle, String hintText) {
    if (_painterSize == size &&
        _painterText == widget.text &&
        _painterHint == hintText) {
      return;
    }
    _painterSize = size;
    _painterText = widget.text;
    _painterHint = hintText;
    _codePainter = widget.text == null
        ? null
        : (TextPainter(
              text: TextSpan(
                text: widget.text,
                style: widget.textStyle ??
                    codeStyle ??
                    const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 24,
                      letterSpacing: 2.0,
                    ),
              ),
              textAlign: TextAlign.center,
              textDirection: TextDirection.ltr,
            )..layout(maxWidth: size.width - 32));
    _hintPainter = TextPainter(
      text: TextSpan(
        text: hintText,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 16,
          letterSpacing: 0.5,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: size.width - 32);
  }

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _fadeAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeOut),
    );
    _fadeController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        widget.onRevealed();
      }
    });
    if (widget.revealed) {
      _thresholdReached = true;
      _fadeController.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(ScratchCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.revealed && !oldWidget.revealed && !_thresholdReached) {
      _thresholdReached = true;
      _fadeController.value = 1.0;
    }
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  void _onPanStart(DragStartDetails details, Size size) {
    if (_thresholdReached || widget.revealed) return;
    final pos = details.localPosition;
    _scratchPath.moveTo(pos.dx, pos.dy);
    _checkPointErase(pos, size);
    setState(() {});
  }

  void _onPanUpdate(DragUpdateDetails details, Size size) {
    if (_thresholdReached || widget.revealed) return;
    final pos = details.localPosition;
    _scratchPath.lineTo(pos.dx, pos.dy);
    _checkPointErase(pos, size);
    setState(() {});
  }

  void _checkPointErase(Offset pos, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final radius = widget.scratchRadius;
    final r2 = radius * radius;

    for (var r = 0; r < _gridRows; r++) {
      final cy = (r + 0.5) * (size.height / _gridRows);
      for (var c = 0; c < _gridCols; c++) {
        final idx = r * _gridCols + c;
        if (_erasedCheckpoints.contains(idx)) continue;
        final cx = (c + 0.5) * (size.width / _gridCols);
        final dx = pos.dx - cx;
        final dy = pos.dy - cy;
        if (dx * dx + dy * dy <= r2) {
          _erasedCheckpoints.add(idx);
        }
      }
    }

    final ratio = _erasedCheckpoints.length / _totalCheckpoints;
    if (ratio >= widget.threshold && !_thresholdReached) {
      _thresholdReached = true;
      _fadeController.forward();
      widget.onRevealed();
    }
  }

  void _revealDirectly() {
    if (_thresholdReached || widget.revealed) return;
    _thresholdReached = true;
    _fadeController.value = 1.0;
    widget.onRevealed();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final brightness = Theme.of(context).brightness;
    final dark = brightness == Brightness.dark;
    final defaultCover = dark ? const Color(0xFF0B0B0C) : const Color(0xFFD90429);
    final cover = widget.coverColor ?? defaultCover;
    final cardBg = heroSurface(brightness);
    final cardBorder = dark
        ? AzmColors.red.withValues(alpha: 0.28)
        : Colors.black.withValues(alpha: 0.08);
    final defaultTextStyle = Theme.of(context).textTheme.headlineMedium;

    if (widget.revealed && _fadeController.isCompleted) {
      return widget.child;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          button: true,
          enabled: !_thresholdReached && !widget.revealed,
          label: l10n.showCode,
          hint: l10n.scratchToReveal,
          onTap: _revealDirectly,
          child: RepaintBoundary(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final size = Size(constraints.maxWidth, 140);
                _ensurePainters(
                  size,
                  defaultTextStyle,
                  l10n.scratchToReveal,
                );
                return SizedBox(
                  width: size.width,
                  height: size.height,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Underlying content: mounted only if generic (no text)
                      // or while fading after explicit reveal.
                      if (widget.text == null ||
                          (widget.revealed && !_fadeController.isCompleted))
                        RepaintBoundary(child: widget.child),
                      // Scratchable flat cover overlay
                      if (!_fadeController.isCompleted)
                        AnimatedBuilder(
                          animation: _fadeAnimation,
                          builder: (context, _) {
                            final opacity = _fadeAnimation.value;
                            if (opacity <= 0.0) {
                              return const SizedBox.shrink();
                            }
                            return GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onPanStart: (d) => _onPanStart(d, size),
                              onPanUpdate: (d) => _onPanUpdate(d, size),
                              child: RepaintBoundary(
                                child: CustomPaint(
                                  size: size,
                                  painter: _ScratchPainter(
                                    scratchPath: _scratchPath,
                                    coverColor: cover,
                                    opacity: opacity,
                                    showHint: _erasedCheckpoints.length < (_totalCheckpoints * 0.25),
                                    scratchRadius: widget.scratchRadius,
                                    cardColor: cardBg,
                                    borderColor: cardBorder,
                                    codePainter: _codePainter,
                                    hintPainter: _hintPainter,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
        if (!_thresholdReached && !widget.revealed)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Center(
              child: TextButton.icon(
                onPressed: _revealDirectly,
                icon: const Icon(Icons.visibility_outlined),
                label: Text(l10n.showCode),
              ),
            ),
          ),
      ],
    );
  }
}

class _ScratchPainter extends CustomPainter {
  _ScratchPainter({
    required this.scratchPath,
    required this.coverColor,
    required this.opacity,
    required this.showHint,
    required this.scratchRadius,
    this.cardColor,
    this.borderColor,
    this.codePainter,
    this.hintPainter,
  });

  final Path scratchPath;
  final Color coverColor;
  final double opacity;
  final bool showHint;
  final double scratchRadius;
  final Color? cardColor;
  final Color? borderColor;

  /// Already laid out by the state (see _ensurePainters) — the painter
  /// only paints them, never lays out text mid-frame.
  final TextPainter? codePainter;
  final TextPainter? hintPainter;

  @override
  void paint(Canvas canvas, Size size) {
    if (opacity <= 0.0 || size.isEmpty) return;

    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(
      rect,
      const Radius.circular(AzmRadius.large),
    );

    // If a code painter is provided, paint card background and the code
    // underneath directly on the canvas so it isn't inspected in the
    // widget tree. The painter is pre-laid-out; no layout happens here.
    if (codePainter != null && cardColor != null) {
      final bgPaint = Paint()
        ..color = cardColor!
        ..style = PaintingStyle.fill;
      canvas.drawRRect(rrect, bgPaint);

      if (borderColor != null) {
        final borderPaint = Paint()
          ..color = borderColor!
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0;
        canvas.drawRRect(rrect, borderPaint);
      }

      final textOffset = Offset(
        (size.width - codePainter!.width) / 2,
        (size.height - codePainter!.height) / 2,
      );
      codePainter!.paint(canvas, textOffset);
    }

    // Save offscreen layer for dstOut blending
    final layerPaint = Paint()..color = Colors.white.withValues(alpha: opacity);
    canvas.saveLayer(rect, layerPaint);

    // 1. Draw solid opaque flat cover (no gradients)
    final coverPaint = Paint()
      ..color = coverColor
      ..style = PaintingStyle.fill;
    canvas.drawRRect(rrect, coverPaint);

    // Border line matching HeroCard
    final borderPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.20)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawRRect(rrect, borderPaint);

    // 2. Draw hint text in the centre before heavy scratching
    if (showHint && opacity > 0.3 && hintPainter != null) {
      final hintOffset = Offset(
        (size.width - hintPainter!.width) / 2,
        (size.height - hintPainter!.height) / 2,
      );
      hintPainter!.paint(canvas, hintOffset);
    }

    // 3. Erase scratched areas via BlendMode.dstOut
    final erasePaint = Paint()
      ..blendMode = BlendMode.dstOut
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = scratchRadius * 2
      ..style = PaintingStyle.stroke;
    canvas.drawPath(scratchPath, erasePaint);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ScratchPainter oldDelegate) {
    return oldDelegate.scratchPath != scratchPath ||
        oldDelegate.opacity != opacity ||
        oldDelegate.showHint != showHint ||
        oldDelegate.coverColor != coverColor ||
        oldDelegate.codePainter != codePainter ||
        oldDelegate.hintPainter != hintPainter;
  }
}

/// Tetris challenge sounds (Batch I-C, item 2) — a thin Dart wrapper
/// over the native SoundPool player (`TetrisSounds.kt`, a port of
/// Dechainer's `TetrisSounds`).
///
/// Audio failures are swallowed: a missing sound must never break the
/// game — and in widget tests there is no platform channel at all, so
/// every call here is failure-tolerant by design.
library;

import 'privileged_channel.dart';

class TetrisSounds {
  TetrisSounds(this._channel);

  final PrivilegedChannel _channel;

  Future<void> load() async {
    try {
      await _channel.loadTetrisSounds();
    } catch (_) {}
  }

  Future<void> play(String name) async {
    try {
      await _channel.playTetrisSound(name);
    } catch (_) {}
  }

  Future<void> release() async {
    try {
      await _channel.releaseTetrisSounds();
    } catch (_) {}
  }
}

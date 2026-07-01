/// Replays a [GenUiFixture] as a stream of text chunks, without depending on
/// `package:genui` at all.
library;

import 'dart:async';

import 'fixture.dart';

/// Controls how quickly a recorded turn is replayed.
enum PlaybackMode {
  /// Emit every chunk back-to-back with no delay. Fastest, and what you want
  /// for the vast majority of widget/unit tests.
  instant,

  /// Wait out each chunk's recorded delay before emitting it, scaled by
  /// [GenUiFixturePlayer.speedMultiplier]. Use this to test loading spinners,
  /// skeleton states, or incremental-rendering behavior against the same
  /// pacing the model actually produced.
  paced,
}

/// Replays a single [RecordedTurn] as a `Stream<String>`.
///
/// This is the low-level primitive; most callers will use
/// [GenUiFixturePlayer] instead, which sequences multiple turns to mirror
/// repeated `sendRequest` calls in a real session.
Stream<String> replayTurn(
  RecordedTurn turn, {
  PlaybackMode mode = PlaybackMode.instant,
  double speedMultiplier = 1.0,
}) async* {
  assert(speedMultiplier > 0, 'speedMultiplier must be positive.');
  for (final chunk in turn.chunks) {
    if (mode == PlaybackMode.paced && chunk.delay > Duration.zero) {
      final scaledMicros = chunk.delay.inMicroseconds / speedMultiplier;
      await Future<void>.delayed(Duration(microseconds: scaledMicros.round()));
    }
    yield chunk.text;
  }
}

/// Replays the turns of a [GenUiFixture] in order, one per call to
/// [playNextTurn] — mirroring how a real GenUI `Transport` gets one
/// `sendRequest` call per user turn and streams back one response per call.
class GenUiFixturePlayer {
  /// Creates a [GenUiFixturePlayer] over [fixture].
  GenUiFixturePlayer(
    this.fixture, {
    this.mode = PlaybackMode.instant,
    this.speedMultiplier = 1.0,
  });

  /// The fixture being replayed.
  final GenUiFixture fixture;

  /// How quickly to replay each turn.
  final PlaybackMode mode;

  /// Scales the recorded delays when [mode] is [PlaybackMode.paced].
  /// Values greater than 1 replay faster than real time; less than 1, slower.
  final double speedMultiplier;

  int _nextTurnIndex = 0;

  /// The index of the next turn that [playNextTurn] will play.
  int get nextTurnIndex => _nextTurnIndex;

  /// Whether there is at least one more recorded turn left to play.
  bool get hasMoreTurns => _nextTurnIndex < fixture.turns.length;

  /// Replays the next unplayed turn in the fixture and advances past it.
  ///
  /// Throws a [StateError] if every recorded turn has already been played —
  /// this usually means your code under test sent more requests than were
  /// recorded, which is worth surfacing loudly rather than replaying stale
  /// data or hanging.
  Stream<String> playNextTurn() {
    if (!hasMoreTurns) {
      throw StateError(
        'GenUiFixturePlayer: fixture "${fixture.name}" has no more recorded '
        'turns (all ${fixture.turns.length} already played). Was sendRequest '
        'called more times than were recorded in this fixture?',
      );
    }
    final turn = fixture.turns[_nextTurnIndex++];
    return replayTurn(turn, mode: mode, speedMultiplier: speedMultiplier);
  }

  /// Resets playback so [playNextTurn] starts again from the first turn.
  void reset() => _nextTurnIndex = 0;
}

import 'package:flutter_test/flutter_test.dart';
import 'package:genui_mock/genui_mock.dart';

GenUiFixture _twoTurnFixture() => GenUiFixture(
  name: 'test',
  recordedAt: DateTime.utc(2026),
  turns: [
    RecordedTurn(
      chunks: [
        const RecordedChunk(text: 'Hello ', delay: Duration.zero),
        const RecordedChunk(text: 'world', delay: Duration(milliseconds: 200)),
      ],
    ),
    RecordedTurn(
      chunks: [const RecordedChunk(text: 'second turn', delay: Duration.zero)],
    ),
  ],
);

void main() {
  group('replayTurn', () {
    test('instant mode emits chunks with no delay', () async {
      final turn = _twoTurnFixture().turns.first;

      final stopwatch = Stopwatch()..start();
      final chunks = await replayTurn(turn).toList();
      stopwatch.stop();

      expect(chunks, ['Hello ', 'world']);
      expect(stopwatch.elapsedMilliseconds, lessThan(100));
    });

    test('paced mode waits out recorded delays', () async {
      final turn = _twoTurnFixture().turns.first;

      final stopwatch = Stopwatch()..start();
      final chunks = await replayTurn(turn, mode: PlaybackMode.paced).toList();
      stopwatch.stop();

      expect(chunks, ['Hello ', 'world']);
      expect(stopwatch.elapsedMilliseconds, greaterThanOrEqualTo(180));
    });

    test('paced mode honors speedMultiplier', () async {
      final turn = _twoTurnFixture().turns.first;

      final stopwatch = Stopwatch()..start();
      await replayTurn(
        turn,
        mode: PlaybackMode.paced,
        speedMultiplier: 10,
      ).drain<void>();
      stopwatch.stop();

      expect(stopwatch.elapsedMilliseconds, lessThan(100));
    });
  });

  group('GenUiFixturePlayer', () {
    test('plays turns in order, one per playNextTurn call', () async {
      final player = GenUiFixturePlayer(_twoTurnFixture());

      expect(player.hasMoreTurns, isTrue);
      expect(await player.playNextTurn().toList(), ['Hello ', 'world']);
      expect(player.hasMoreTurns, isTrue);
      expect(await player.playNextTurn().toList(), ['second turn']);
      expect(player.hasMoreTurns, isFalse);
    });

    test('throws once every recorded turn has been played', () async {
      final player = GenUiFixturePlayer(_twoTurnFixture());
      await player.playNextTurn().drain<void>();
      await player.playNextTurn().drain<void>();

      expect(player.playNextTurn, throwsStateError);
    });

    test('reset() allows replaying from the first turn again', () async {
      final player = GenUiFixturePlayer(_twoTurnFixture());
      await player.playNextTurn().drain<void>();
      await player.playNextTurn().drain<void>();

      player.reset();

      expect(player.hasMoreTurns, isTrue);
      expect(await player.playNextTurn().toList(), ['Hello ', 'world']);
    });
  });
}

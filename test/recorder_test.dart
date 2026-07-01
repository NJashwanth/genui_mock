import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:genui_mock/genui_mock.dart';

void main() {
  group('GenUiSessionRecorder', () {
    test('forwards every chunk through unchanged', () async {
      final recorder = GenUiSessionRecorder(name: 'test');
      final source = Stream<String>.fromIterable(['a', 'b', 'c']);

      final forwarded = await recorder.recordTurn(source).toList();

      expect(forwarded, ['a', 'b', 'c']);
    });

    test('records chunk text and timing gaps into a turn', () async {
      final recorder = GenUiSessionRecorder(name: 'test');
      final controller = StreamController<String>();

      final done = recorder
          .recordTurn(controller.stream, label: 'turn 1')
          .toList();

      controller.add('first');
      await Future<void>.delayed(const Duration(milliseconds: 30));
      controller.add('second');
      await controller.close();
      await done;

      expect(recorder.turns, hasLength(1));
      final turn = recorder.turns.single;
      expect(turn.label, 'turn 1');
      expect(turn.chunks, hasLength(2));
      expect(turn.chunks[0].text, 'first');
      expect(turn.chunks[1].text, 'second');
      expect(turn.chunks[1].delay.inMilliseconds, greaterThanOrEqualTo(25));
    });

    test(
      'accumulates multiple turns across separate recordTurn calls',
      () async {
        final recorder = GenUiSessionRecorder(
          name: 'session',
          description: 'multi-turn session',
        );

        await recorder
            .recordTurn(Stream<String>.fromIterable(['hi']))
            .drain<void>();
        await recorder
            .recordTurn(Stream<String>.fromIterable(['there']))
            .drain<void>();

        final fixture = recorder.toFixture();
        expect(fixture.name, 'session');
        expect(fixture.description, 'multi-turn session');
        expect(fixture.turns, hasLength(2));
        expect(fixture.turns[0].chunks.single.text, 'hi');
        expect(fixture.turns[1].chunks.single.text, 'there');
      },
    );

    test('propagates errors from the source stream', () async {
      final recorder = GenUiSessionRecorder(name: 'test');
      final source = Stream<String>.fromFuture(
        Future.error(StateError('boom')),
      );

      await expectLater(recorder.recordTurn(source), emitsError(isStateError));
    });
  });
}

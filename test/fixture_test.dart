import 'package:flutter_test/flutter_test.dart';
import 'package:genui_mock/genui_mock.dart';

void main() {
  group('GenUiFixture', () {
    test('round-trips through JSON', () {
      final original = GenUiFixture(
        name: 'weather_forecast',
        description: 'user asks for a 3-day forecast',
        recordedAt: DateTime.utc(2026, 1, 15, 12, 30),
        turns: [
          RecordedTurn(
            label: 'first question',
            chunks: [
              const RecordedChunk(
                text: 'Hello ',
                delay: Duration(milliseconds: 0),
              ),
              const RecordedChunk(
                text: 'world',
                delay: Duration(milliseconds: 120),
              ),
            ],
          ),
          RecordedTurn(
            chunks: [
              const RecordedChunk(
                text: '```json\n{}\n```',
                delay: Duration(milliseconds: 40),
              ),
            ],
          ),
        ],
      );

      final decoded = GenUiFixture.decode(original.encode());

      expect(decoded.name, original.name);
      expect(decoded.description, original.description);
      expect(decoded.recordedAt, original.recordedAt);
      expect(decoded.turns.length, 2);
      expect(decoded.turns[0].label, 'first question');
      expect(decoded.turns[0].chunks, original.turns[0].chunks);
      expect(decoded.turns[1].label, isNull);
      expect(decoded.turns[1].chunks, original.turns[1].chunks);
    });

    test('encode() produces stable, git-diffable pretty JSON', () {
      final fixture = GenUiFixture(
        name: 'stable',
        recordedAt: DateTime.utc(2026, 1, 1),
        turns: [
          RecordedTurn(
            chunks: [const RecordedChunk(text: 'hi', delay: Duration.zero)],
          ),
        ],
      );

      expect(fixture.encode(), contains('\n'));
      expect(fixture.encode(), fixture.encode());
    });

    test('omits null description and turn label from JSON', () {
      final fixture = GenUiFixture(
        name: 'no_description',
        recordedAt: DateTime.utc(2026, 1, 1),
        turns: [
          RecordedTurn(
            chunks: [const RecordedChunk(text: 'hi', delay: Duration.zero)],
          ),
        ],
      );

      final json = fixture.toJson();
      expect(json.containsKey('description'), isFalse);
      final turnJson = (json['turns'] as List)[0] as Map<String, dynamic>;
      expect(turnJson.containsKey('label'), isFalse);
    });

    test(
      'rejects fixtures written by a newer, incompatible format version',
      () {
        final json = {
          'formatVersion': genUiFixtureFormatVersion + 1,
          'name': 'from_the_future',
          'recordedAt': DateTime.utc(2026).toIso8601String(),
          'turns': <dynamic>[],
        };

        expect(() => GenUiFixture.fromJson(json), throwsFormatException);
      },
    );

    test(
      'defaults formatVersion to 1 for fixtures written before the field existed',
      () {
        final json = {
          'name': 'legacy',
          'recordedAt': DateTime.utc(2026).toIso8601String(),
          'turns': <dynamic>[],
        };

        expect(() => GenUiFixture.fromJson(json), returnsNormally);
      },
    );
  });

  group('RecordedChunk', () {
    test('equality is based on text and delay', () {
      const a = RecordedChunk(text: 'x', delay: Duration(milliseconds: 5));
      const b = RecordedChunk(text: 'x', delay: Duration(milliseconds: 5));
      const c = RecordedChunk(text: 'x', delay: Duration(milliseconds: 6));

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
    });
  });
}

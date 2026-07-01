import 'package:flutter_test/flutter_test.dart';
import 'package:genui/genui.dart';
import 'package:genui_mock/genui_mock.dart';

GenUiFixture _fixtureWithSurface() => GenUiFixture(
  name: 'creates_a_surface',
  recordedAt: DateTime.utc(2026),
  turns: [
    RecordedTurn(
      chunks: [
        const RecordedChunk(text: 'Sure, here you go.\n', delay: Duration.zero),
        const RecordedChunk(
          text:
              '```json\n'
              '{"version": "v0.9", "createSurface": '
              '{"surfaceId": "s1", "catalogId": "core"}}\n'
              '```',
          delay: Duration(milliseconds: 10),
        ),
      ],
    ),
    RecordedTurn(
      chunks: [const RecordedChunk(text: 'second reply', delay: Duration.zero)],
    ),
  ],
);

void main() {
  group('GenUiMockTransport', () {
    test('streams recorded text through incomingText', () async {
      final transport = GenUiMockTransport(_fixtureWithSurface());
      addTearDown(transport.dispose);

      final textFuture = transport.incomingText.first;
      await transport.sendRequest(ChatMessage.user('hi'));

      expect(await textFuture, 'Sure, here you go.');
    });

    test('parses recorded JSON chunks into real A2uiMessage objects via '
        "genui's own adapter", () async {
      final transport = GenUiMockTransport(_fixtureWithSurface());
      addTearDown(transport.dispose);

      final messageFuture = transport.incomingMessages.first;
      await transport.sendRequest(ChatMessage.user('hi'));
      final message = await messageFuture;

      expect(message, isA<CreateSurface>());
      expect((message as CreateSurface).surfaceId, 's1');
      expect(message.catalogId, 'core');
    });

    test('each sendRequest call replays the next recorded turn', () async {
      final transport = GenUiMockTransport(_fixtureWithSurface());
      addTearDown(transport.dispose);

      final firstText = transport.incomingText.first;
      await transport.sendRequest(ChatMessage.user('first question'));
      expect(await firstText, 'Sure, here you go.');

      final secondText = transport.incomingText.first;
      await transport.sendRequest(ChatMessage.user('second question'));
      expect(await secondText, 'second reply');
    });

    test('records every sent message', () async {
      final transport = GenUiMockTransport(_fixtureWithSurface());
      addTearDown(transport.dispose);

      await transport.sendRequest(ChatMessage.user('first question'));
      await transport.sendRequest(ChatMessage.user('second question'));

      expect(transport.sentMessages, hasLength(2));
    });

    test(
      'throws once more requests are sent than turns were recorded',
      () async {
        final fixture = GenUiFixture(
          name: 'single_turn',
          recordedAt: DateTime.utc(2026),
          turns: [
            RecordedTurn(
              chunks: [
                const RecordedChunk(text: 'only reply', delay: Duration.zero),
              ],
            ),
          ],
        );
        final transport = GenUiMockTransport(fixture);
        addTearDown(transport.dispose);

        await transport.sendRequest(ChatMessage.user('first'));

        expect(
          () => transport.sendRequest(ChatMessage.user('second')),
          throwsStateError,
        );
      },
    );
  });
}

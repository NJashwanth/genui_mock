import 'package:a2ui_core/a2ui_core.dart';
import 'package:a2ui_flutter/a2ui_flutter.dart';
import 'package:a2ui_flutter/v0_9/basic_catalog.dart' as v0_9;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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

/// A fixture of one turn made of [chunks], each arriving without delay.
GenUiFixture _singleTurn(List<String> chunks) => GenUiFixture(
  name: 'single_turn',
  recordedAt: DateTime.utc(2026),
  turns: [
    RecordedTurn(
      chunks: [
        for (final chunk in chunks)
          RecordedChunk(text: chunk, delay: Duration.zero),
      ],
    ),
  ],
);

void main() {
  group('GenUiMockTransport', () {
    test('streams recorded text through incomingText', () async {
      final transport = GenUiMockTransport(_fixtureWithSurface());
      addTearDown(transport.dispose);

      final textFuture = transport.incomingText.first;
      await transport.sendRequest('hi');

      expect(await textFuture, 'Sure, here you go.\n');
    });

    test('parses recorded JSON chunks into real a2ui_core '
        'AgentToRendererMessage objects', () async {
      final transport = GenUiMockTransport(_fixtureWithSurface());
      addTearDown(transport.dispose);

      final messageFuture = transport.incomingMessages.first;
      await transport.sendRequest('hi');
      final message = await messageFuture;

      expect(message, isA<CreateSurfaceMessage>());
      expect((message as CreateSurfaceMessage).surfaceId, 's1');
      expect(message.catalogId, 'core');
    });

    test('each sendRequest call replays the next recorded turn', () async {
      final transport = GenUiMockTransport(_fixtureWithSurface());
      addTearDown(transport.dispose);

      final firstText = transport.incomingText.first;
      await transport.sendRequest('first question');
      expect(await firstText, 'Sure, here you go.\n');

      final secondText = transport.incomingText.first;
      await transport.sendRequest('second question');
      expect(await secondText, 'second reply');
    });

    test('records every sent message', () async {
      final transport = GenUiMockTransport(_fixtureWithSurface());
      addTearDown(transport.dispose);

      await transport.sendRequest('first question');
      await transport.sendRequest('second question');

      expect(transport.sentMessages, ['first question', 'second question']);
    });

    test('replays text chunks verbatim, so a sentence split across chunks '
        'concatenates back byte for byte', () async {
      // Regression guard for the chunk-trimming bug fixed in genui 0.10.2:
      // the adapter used to trim every chunk, which turned the two chunks
      // below into 'the quickbrown fox'. Byte-for-byte replay is the whole
      // point of a fixture, so assert on it directly.
      final fixture = GenUiFixture(
        name: 'split_sentence',
        recordedAt: DateTime.utc(2026),
        turns: [
          RecordedTurn(
            chunks: [
              const RecordedChunk(text: 'the quick ', delay: Duration.zero),
              const RecordedChunk(text: 'brown fox', delay: Duration.zero),
            ],
          ),
        ],
      );
      final transport = GenUiMockTransport(fixture);
      addTearDown(transport.dispose);

      final textFuture = transport.incomingText.take(2).join();
      await transport.sendRequest('hi');

      expect(await textFuture, 'the quick brown fox');
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

        await transport.sendRequest('first');

        expect(() => transport.sendRequest('second'), throwsStateError);
      },
    );
  });

  group('reading recorded replies', () {
    test('reads A2UI JSON in markdown fences and as bare JSON objects, '
        'and everything else as text', () async {
      final transport = GenUiMockTransport(
        _singleTurn([
          'Here you go:\n',
          '```json\n['
              '{"version": "v0.9", "createSurface": '
              '{"surfaceId": "s1", "catalogId": "core"}},'
              '{"version": "v0.9", "deleteSurface": {"surfaceId": "s1"}}'
              ']\n```',
          '\nAnd one more: ',
          '{"version": "v0.9", "deleteSurface": ',
          '{"surfaceId": "s2"}}',
          '\nDone.',
        ]),
      );
      addTearDown(transport.dispose);

      final messages = <AgentToRendererMessage>[];
      final text = <String>[];
      final messageSub = transport.incomingMessages.listen(messages.add);
      final textSub = transport.incomingText.listen(text.add);
      await transport.sendRequest('hi');
      await messageSub.cancel();
      await textSub.cancel();

      expect(messages, [
        isA<CreateSurfaceMessage>(),
        isA<DeleteSurfaceMessage>().having((m) => m.surfaceId, 'id', 's1'),
        isA<DeleteSurfaceMessage>().having((m) => m.surfaceId, 'id', 's2'),
      ]);
      expect(text.join(), 'Here you go:\n\nAnd one more: \nDone.');
    });

    test('adds recorded A2UI JSON that is not a valid message to '
        'incomingMessages as an error, and replays the rest', () async {
      final transport = GenUiMockTransport(
        _singleTurn([
          '{"version": "v0.9", "createSurface": {}}',
          ' Still here. ',
          '{"version": "v0.9", "deleteSurface": {"surfaceId": "s1"}}',
        ]),
      );
      addTearDown(transport.dispose);

      final messages = <AgentToRendererMessage>[];
      final errors = <Object>[];
      final text = <String>[];
      final messageSub = transport.incomingMessages.listen(
        messages.add,
        onError: errors.add,
      );
      final textSub = transport.incomingText.listen(text.add);
      await transport.sendRequest('hi');
      await messageSub.cancel();
      await textSub.cancel();

      expect(errors, [isA<A2uiValidationError>()]);
      expect(messages, [isA<DeleteSurfaceMessage>()]);
      expect(text.join(), ' Still here. ');
    });

    test('delivers text held back for an unfinished JSON object at the end '
        'of its turn', () async {
      final fixture = GenUiFixture(
        name: 'unfinished_json',
        recordedAt: DateTime.utc(2026),
        turns: [
          RecordedTurn(
            chunks: [
              const RecordedChunk(
                text: 'Incomplete { json',
                delay: Duration.zero,
              ),
            ],
          ),
          RecordedTurn(
            chunks: [
              const RecordedChunk(text: 'second reply', delay: Duration.zero),
            ],
          ),
        ],
      );
      final transport = GenUiMockTransport(fixture);
      addTearDown(transport.dispose);

      final text = <String>[];
      final textSub = transport.incomingText.listen(text.add);
      await transport.sendRequest('first');
      await pumpEventQueue();
      expect(text, ['Incomplete ', '{ json']);

      await transport.sendRequest('second');
      await pumpEventQueue();
      await textSub.cancel();
      expect(text, ['Incomplete ', '{ json', 'second reply']);
    });
  });

  group('rendering through the basic catalog', () {
    // genui 0.10.3 moved basicCatalogId to a new canonical URL and kept the
    // old one as an alias. Fixtures recorded before then carry the old URL
    // baked into their chunks. a2ui_flutter's basicCatalog() registers only
    // the canonical id, so the processor registers the old one too.
    const catalogIds = {
      'legacy': 'https://a2ui.org/specification/v0_9/basic_catalog.json',
      'canonical':
          'https://a2ui.org/specification/v0_9/catalogs/basic/catalog.json',
    };

    for (final MapEntry(key: label, value: catalogId) in catalogIds.entries) {
      testWidgets('a fixture recorded with the $label catalog id renders', (
        tester,
      ) async {
        final fixture = GenUiFixture(
          name: 'greeting_$label',
          recordedAt: DateTime.utc(2026),
          turns: [
            RecordedTurn(
              chunks: [
                RecordedChunk(
                  text:
                      '```json\n'
                      '{"version": "v0.9", "createSurface": '
                      '{"surfaceId": "greeting", "catalogId": "$catalogId"}}\n'
                      '```',
                  delay: Duration.zero,
                ),
                const RecordedChunk(
                  text:
                      '```json\n'
                      '{"version": "v0.9", "updateComponents": '
                      '{"surfaceId": "greeting", "components": ['
                      '{"id": "root", "component": "Text", "text": "Hello!"}'
                      ']}}\n'
                      '```',
                  delay: Duration.zero,
                ),
              ],
            ),
          ],
        );
        final transport = GenUiMockTransport(fixture);
        final processor = MessageProcessor<ComponentImplementation>(
          catalogs: [
            v0_9.basicCatalog(),
            v0_9.basicCatalog().derive(
              catalogId: catalogIds['legacy']!,
              instructions: v0_9.BasicComponents.api.instructions,
            ),
          ],
          validationConfig: ValidationConfig.strict,
        );
        final errors = <A2uiRendererError>[];
        processor.model.onError.subscribe(errors.add);
        final messages = transport.incomingMessages.listen(
          (message) => processor.processMessages(
            AgentToRendererMessagePayload.of(message),
          ),
        );
        addTearDown(() async {
          await messages.cancel();
          processor.dispose();
          transport.dispose();
        });

        await transport.sendRequest('say hello');
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: A2uiSurface(
                surface: processor.model.getSurface('greeting')!,
              ),
            ),
          ),
        );

        expect(find.text('Hello!'), findsOneWidget);
        expect(errors, isEmpty);
      });
    }
  });
}

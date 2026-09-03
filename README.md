# genui_mock

[![pub package](https://img.shields.io/pub/v/genui_mock.svg)](https://pub.dev/packages/genui_mock)

Test your [GenUI](https://pub.dev/packages/genui) widgets against real model
output — without the network.

Record a live streaming session once, save it as a small JSON fixture, and
replay it in your tests as many times as you like: no API key, no latency, no
flaky non-determinism.

> **Unofficial.** An independent, community-built testing utility. Not
> published, endorsed, or supported by Google or the Flutter team — the name
> just describes what the package is for.

## What a test looks like

```dart
testWidgets('renders the recorded greeting', (tester) async {
  final fixture = GenUiFixture.decode(
    await File('test/fixtures/greeting.json').readAsString(),
  );

  final transport = GenUiMockTransport(fixture);
  final controller = SurfaceController(catalogs: [BasicCatalogItems.asCatalog()]);
  final conversation = Conversation(transport: transport, controller: controller);

  await conversation.sendRequest(ChatMessage.user('say hello'));

  await tester.pumpWidget(MaterialApp(
    home: Surface(surfaceContext: controller.contextFor('greeting')),
  ));

  expect(find.text('Hello!'), findsOneWidget);
});
```

That's a real GenUI `Conversation`, a real `SurfaceController`, and real
catalog widgets. The only thing swapped out is where the bytes come from.

## Why

`genui` is alpha and its API moves fast. Every time you tweak a `Catalog`
widget, checking that it still renders usually means burning an API call and
waiting on the network — and the model's output isn't stable enough to assert
against anyway.

Record what the model actually said once, then replay those exact bytes
forever.

## Install

```yaml
dev_dependencies:
  genui_mock: ^0.1.2
```

`genui_mock` depends on `genui` directly (not just as a dev dependency),
because `GenUiMockTransport` implements `genui`'s real `Transport` interface.

## Recording a fixture

You already pipe a `Stream<String>` of model chunks into `genui`. Wrap that
stream with a `GenUiSessionRecorder` and use the stream it returns instead.

```dart
final recorder = GenUiSessionRecorder(
  name: 'weather_forecast',
  description: 'user asks for a 3-day forecast',
);

// Per user turn — pass the recorded stream where you passed the raw one:
await for (final chunk in recorder.recordTurn(rawChunksFromYourModel())) {
  transportAdapter.addChunk(chunk);
}

// When the session is done:
await File('test/fixtures/weather_forecast.json')
    .writeAsString(recorder.toFixture().encode());
```

Recording is transparent: every chunk is forwarded through untouched, so your
app behaves exactly as it did before. The recorder just notes each chunk's
text and how long it took to arrive.

Call `recordTurn` once per request/response cycle. Each call appends one turn,
and you can label them (`recordTurn(chunks, label: 'asks for tomorrow')`) to
keep a multi-turn fixture readable.

## The fixture file

Plain, pretty-printed JSON — reviewable in a pull request, so you can see
exactly what changed when you re-record:

```json
{
  "formatVersion": 1,
  "name": "weather_forecast",
  "description": "user asks for a 3-day forecast",
  "recordedAt": "2026-07-02T10:15:00.000Z",
  "turns": [
    {
      "chunks": [
        { "text": "Here's your forecast:\n", "delayMs": 412 },
        { "text": "```json\n{\"version\": \"v0.9\", \"createSurface\": ...", "delayMs": 96 }
      ]
    }
  ]
}
```

A turn is the ordered list of raw text chunks that arrived after one
`sendRequest`, captured *before* any A2UI parsing. Recording at that layer
means the fixture holds precisely what the model said, with no lossy
intermediate representation — and replay re-emits those chunks verbatim,
whitespace included, so concatenating them reproduces the original text byte
for byte.

## Replaying

Each `sendRequest` call plays the fixture's next turn, so a multi-turn fixture
drives a multi-turn conversation in the order it was recorded. Sending more
requests than you recorded throws a `StateError` rather than hanging or
replaying stale data.

**Pacing.** By default chunks arrive back-to-back, which is what you want for
fast tests. Replay the original timing instead to exercise loading and
skeleton states:

```dart
GenUiMockTransport(fixture);                              // instant (default)
GenUiMockTransport(fixture, mode: PlaybackMode.paced);    // original timing
GenUiMockTransport(fixture, mode: PlaybackMode.paced, speedMultiplier: 5); // 5x
```

**Asserting on what you sent.** `transport.sentMessages` holds every
`ChatMessage` passed to `sendRequest`, in order.

**Without `genui`.** `GenUiFixturePlayer` replays a fixture as a plain
`Stream<String>`, with `hasMoreTurns` and `reset()`, if you want the chunks
without a `Transport` at all.

See [example/](example/) for a complete runnable app.

## How it works

`genui`'s API has shifted a lot between releases — compare the `0.5.x` line,
which wired rendering straight to a `ContentGenerator`, to `0.8.0`+, which
introduced `Transport`: a four-method interface (`incomingText`,
`incomingMessages`, `sendRequest`, `dispose`) that exists specifically to
decouple rendering from any particular network client.

That's the most stable seam in the published API, so it's the *only* thing
this package touches. The result is a deliberate split:

| Part | Depends on `genui`? |
| --- | --- |
| `GenUiFixture`, `GenUiSessionRecorder`, `GenUiFixturePlayer` | No — plain Dart, just chunks and timings |
| `GenUiMockTransport` | Yes — the single file that imports it |

Everything except `GenUiMockTransport` is immune to a `genui` API change. And
`GenUiMockTransport` parses nothing itself: it feeds chunks to `genui`'s own
`A2uiTransportAdapter`, so this package never has to track the A2UI wire
format. If a future release changes `Transport`, one file needs updating.

## Compatibility

Built against `genui` `0.10.2`. The `Transport` interface it targets has kept
the same shape since `0.8.0`.

Two `genui` releases affected this package:

- **`0.10.0`** moved the A2UI message types (`A2uiMessage`,
  `CreateSurfaceMessage`, …) into `package:a2ui_core`, so `genui_mock` depends
  on `a2ui_core` directly too.
- **`0.10.2`** stopped `A2uiTransportAdapter` trimming every streamed chunk.
  Before that fix a sentence recorded across two chunks (`"the quick "` +
  `"brown fox"`) replayed as `"the quickbrown fox"`. Byte-for-byte replay is
  the entire point of a fixture, so `0.10.2` is the minimum.

## License

MIT — see [LICENSE](LICENSE).

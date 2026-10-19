# genui_mock

[![pub package](https://img.shields.io/pub/v/genui_mock.svg)](https://pub.dev/packages/genui_mock)
[![pub points](https://img.shields.io/pub/points/genui_mock)](https://pub.dev/packages/genui_mock/score)
[![license: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

Test your [GenUI](https://pub.dev/packages/genui) widgets against real model
output, without the network.

Record a live streaming session once, save it as a small JSON fixture, and
replay it in your tests as often as you like.

- **No network, no API key.** Tests run offline and in CI.
- **Deterministic.** The same bytes arrive in the same order every run, so you
  can assert on what renders.
- **Real rendering.** Fixtures play through GenUI's own `Conversation`,
  `SurfaceController`, and catalog widgets. Only the source of the bytes is
  swapped out.
- **Reviewable.** Fixtures are pretty-printed JSON, so re-recording shows up as
  a readable diff in your pull request.

## Quick start

### 1. Install

```yaml
dev_dependencies:
  genui_mock: ^0.1.3
```

### 2. Record a session

You already pipe a `Stream<String>` of model chunks into GenUI. Wrap that
stream with a `GenUiSessionRecorder` and use the stream it returns instead:

```dart
final recorder = GenUiSessionRecorder(
  name: 'greeting',
  description: 'user asks for a friendly greeting',
);

// Once per user turn, pass the recorded stream where you passed the raw one:
await for (final chunk in recorder.recordTurn(rawChunksFromYourModel())) {
  transportAdapter.addChunk(chunk);
}

// When the session is done:
await File('test/fixtures/greeting.json')
    .writeAsString(recorder.toFixture().encode());
```

Every chunk is forwarded unchanged, so your app behaves exactly as before. The
recorder only notes each chunk's text and how long it took to arrive.

### 3. Replay it in a test

```dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genui/genui.dart';
import 'package:genui_mock/genui_mock.dart';

void main() {
  testWidgets('renders the recorded greeting', (tester) async {
    final fixture = GenUiFixture.decode(
      File('test/fixtures/greeting.json').readAsStringSync(),
    );

    final transport = GenUiMockTransport(fixture);
    final controller = SurfaceController(
      catalogs: [BasicCatalogItems.asCatalog()],
    );
    final conversation = Conversation(
      transport: transport,
      controller: controller,
    );
    addTearDown(conversation.dispose);

    await conversation.sendRequest(ChatMessage.user('say hello'));

    await tester.pumpWidget(MaterialApp(
      home: Surface(surfaceContext: controller.contextFor('greeting')),
    ));

    expect(find.text('Hello!'), findsOneWidget);
  });
}
```

Use `readAsStringSync` to load fixtures inside `testWidgets`. Real async file
I/O can hang there because the test body runs in a fake-async zone.

For a complete runnable app, see [example/](example/).

## The fixture file

```json
{
  "formatVersion": 1,
  "name": "greeting",
  "description": "user asks for a friendly greeting",
  "recordedAt": "2026-07-02T10:15:00.000Z",
  "turns": [
    {
      "label": "asks for a greeting",
      "chunks": [
        { "text": "Here you go:\n", "delayMs": 0 },
        { "text": "```json\n{\"version\": \"v0.9\", \"createSurface\": {\"surfaceId\": \"greeting\", \"catalogId\": \"https://a2ui.org/specification/v0_9/catalogs/basic/catalog.json\"}}\n```", "delayMs": 300 },
        { "text": "```json\n{\"version\": \"v0.9\", \"updateComponents\": {\"surfaceId\": \"greeting\", \"components\": [{\"id\": \"root\", \"component\": \"Text\", \"text\": \"Hello!\"}]}}\n```", "delayMs": 400 }
      ]
    }
  ]
}
```

A **turn** is the ordered list of raw text chunks that arrived after one
`sendRequest`. Each chunk records its text and the delay since the previous
chunk.

Chunks are captured *before* any A2UI parsing, so a fixture holds exactly what
the model said. Replay re-emits them verbatim, whitespace included, so
concatenating the chunks reproduces the original text byte for byte.

`description` and `label` are optional. Label turns
(`recordTurn(chunks, label: 'asks for tomorrow')`) to keep multi-turn fixtures
readable.

## Replaying

### Multi-turn conversations

Each `sendRequest` plays the fixture's next turn, so a multi-turn fixture
drives a multi-turn conversation in the order it was recorded. Sending more
requests than were recorded throws a `StateError`, so a test fails loudly
instead of hanging or replaying stale data.

### Pacing

By default chunks arrive back to back, which keeps tests fast. Use paced mode
to replay the original timing:

```dart
GenUiMockTransport(fixture);                                               // instant (default)
GenUiMockTransport(fixture, mode: PlaybackMode.paced);                     // original timing
GenUiMockTransport(fixture, mode: PlaybackMode.paced, speedMultiplier: 5); // 5x faster
```

### Testing loading states

Paced replay runs on timers, so inside `testWidgets` you can step through a
stream with `tester.pump` and assert on what is visible at each point:

```dart
final transport = GenUiMockTransport(fixture, mode: PlaybackMode.paced);
// ...controller and conversation as above...

final reply = conversation.sendRequest(ChatMessage.user('say hello'));
await tester.pumpWidget(MaterialApp(
  home: Surface(surfaceContext: controller.contextFor('greeting')),
));

expect(find.text('Hello!'), findsNothing);   // still streaming

await tester.pump(const Duration(milliseconds: 700));
await tester.pump();

expect(find.text('Hello!'), findsOneWidget); // fully rendered
await reply;
```

### Asserting on what you sent

`transport.sentMessages` holds every `ChatMessage` passed to `sendRequest`, in
order. Use it to check that your UI sent the right prompt or action.

### Without GenUI

`GenUiFixturePlayer` replays a fixture as a plain `Stream<String>` with no
`Transport` involved. That's useful for testing your own chunk handling.

```dart
final player = GenUiFixturePlayer(fixture);
while (player.hasMoreTurns) {
  await for (final chunk in player.playNextTurn()) {
    // ...
  }
}
player.reset(); // back to the first turn
```

## Tips

- **Keep fixtures next to tests**, in `test/fixtures/`, and commit them. Name
  them after the scenario, not the date.
- **Re-record when your prompt, model, or catalog changes.** A fixture captures
  one moment of model behavior, and the PR diff shows what changed.
- **Edit fixtures by hand** to cover cases a model rarely produces, such as a
  malformed component or an empty surface. The format is plain JSON.
- **Build fixtures in code** with `GenUiFixture`, `RecordedTurn`, and
  `RecordedChunk` for small, focused tests. The [example](example/lib/main.dart)
  does this.

## API at a glance

| Type | What it does | Needs `genui`? |
| --- | --- | --- |
| `GenUiSessionRecorder` | Wraps a live chunk stream and records it into a fixture | No |
| `GenUiFixture` | The fixture: `encode()` / `decode()` to and from JSON | No |
| `RecordedTurn`, `RecordedChunk` | One request/response cycle, and one chunk with its delay | No |
| `GenUiFixturePlayer`, `replayTurn` | Replay turns as a plain `Stream<String>` | No |
| `PlaybackMode` | `instant` or `paced` | No |
| `GenUiMockTransport` | A GenUI `Transport` that replays a fixture | Yes |

## How it works

GenUI's `Transport` is a four-method interface (`incomingText`,
`incomingMessages`, `sendRequest`, `dispose`) that separates rendering from any
particular network client. It has kept the same shape since `genui` `0.8.0`,
which makes it the most stable seam in the API, so it's the only one this
package touches.

`GenUiMockTransport` is the only file that imports `genui`. Everything else is
plain Dart and unaffected by GenUI API changes. The transport doesn't parse
anything itself: it feeds recorded chunks to GenUI's own
`A2uiTransportAdapter`, so this package never has to track the A2UI wire
format.

## Compatibility

Built against `genui` `0.10.4`. Requires `genui` `^0.10.4`.

| `genui_mock` | `genui` | Notes |
| --- | --- | --- |
| `0.1.3` | `^0.10.4` | `0.10.3` renamed the basic catalog id to `…/v0_9/catalogs/basic/catalog.json` and kept the old `…/v0_9/basic_catalog.json` as an alias. Older fixtures still render. |
| `0.1.2` | `^0.10.2` | `0.10.2` stopped trimming every streamed chunk, which is what makes byte-for-byte replay possible. |
| `0.1.1` | `^0.10.1` | `0.10.0` moved the A2UI message types into `package:a2ui_core`. |
| `0.1.0` | `^0.9.2` | Initial release. |

None of these required re-recording fixtures. See the
[CHANGELOG](CHANGELOG.md) for details.

## Contributing

Bug reports and pull requests are welcome on
[GitHub](https://github.com/NJashwanth/genui_mock/issues). If GenUI ships a
release that breaks replay, an issue with the failing fixture is the most
useful thing you can send.

## License

MIT. See [LICENSE](LICENSE).

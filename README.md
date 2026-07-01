# genui_mock

Record a real [GenUI](https://pub.dev/packages/genui) streaming session once,
save it as a small git-diffable JSON fixture, and replay it later with **zero
network calls, no API key, and fully deterministic output**.

> **Unofficial, not affiliated with Google.** `genui_mock` is an independent,
> community-built testing utility. It is not published, endorsed, or
> supported by Google or the Flutter team, and it has no special access to
> the `genui` package beyond what's publicly published. The name references
> `genui`'s namespace purely to describe what this package is for.

## Why

`genui` is alpha, and its API moves often. Every time you tweak a widget in
your `Catalog`, checking whether it renders correctly usually means burning a
real API call and waiting on network latency — and even then, the model's
output isn't deterministic enough to assert against directly.

`genui_mock` lets you record what the model actually streamed back once, and
replay that exact byte-for-byte output as many times as you want, instantly,
in CI, with no API key required.

## What genui version was this built against?

`genui` `0.9.2` (the latest published version as of writing). The one
integration point this package depends on — the `Transport` interface — was
introduced in `genui` `0.8.0` and has not changed since; see [Design](#design)
below for why that's the seam this package is built on.

## Install

```yaml
dev_dependencies:
  genui_mock: ^0.1.0
```

`genui_mock` depends on `genui` directly (not just as a dev dependency),
since `GenUiMockTransport` implements `genui`'s real `Transport` interface.

## Usage

### 1. Record a real session, once

Wrap whatever `Stream<String>` you already feed into `genui` (e.g. the raw
chunks from your model API call, before `A2uiTransportAdapter.addChunk`) with
a `GenUiSessionRecorder`. It forwards every chunk through unchanged — your
app behaves exactly as it does today — while timing and collecting them.

```dart
import 'dart:io';
import 'package:genui_mock/genui_mock.dart';

final recorder = GenUiSessionRecorder(
  name: 'weather_forecast',
  description: 'user asks for a 3-day forecast',
);

// For each user turn, replace the stream you hand to your transport with
// the recorded version — recording is transparent to the rest of your app:
final chunks = recorder.recordTurn(rawChunksFromYourModelCall());
await for (final chunk in chunks) {
  transportAdapter.addChunk(chunk); // unchanged
}

// Once the session is over, save it:
final fixture = recorder.toFixture();
await File('test/fixtures/weather_forecast.json').writeAsString(fixture.encode());
```

The saved fixture is plain, pretty-printed JSON — readable and diffable in
code review, so you can see exactly what changed when you re-record it.

### 2. Replay the fixture in a test

```dart
import 'dart:io';
import 'package:genui/genui.dart';
import 'package:genui_mock/genui_mock.dart';

final fixture = GenUiFixture.decode(
  await File('test/fixtures/weather_forecast.json').readAsString(),
);
final transport = GenUiMockTransport(fixture);

final conversation = Conversation(controller: myController, transport: transport);
await conversation.sendRequest(ChatMessage.user('what is the weather?'));
// `myController`'s surfaces now update exactly as they did in the real,
// recorded session — no network access, no API key, fully deterministic.
```

Each call to `sendRequest` replays the fixture's next recorded turn, so a
multi-turn fixture drives a multi-turn conversation the same way it was
recorded.

### 3. Choose how fast to replay

```dart
// Instant (default) — for fast unit/widget tests:
GenUiMockTransport(fixture);

// Paced to the original timing — for testing loading/skeleton states:
GenUiMockTransport(fixture, mode: PlaybackMode.paced);

// Paced, but 5x faster than real time:
GenUiMockTransport(fixture, mode: PlaybackMode.paced, speedMultiplier: 5);
```

## Design

`genui`'s API has shifted a lot between versions — compare the `0.5.x`
line (which coupled UI rendering directly to a `ContentGenerator`/model
client) to `0.8.0`+, which introduced `Transport`: a small, four-method
interface (`incomingText`, `incomingMessages`, `sendRequest`, `dispose`)
that explicitly exists to decouple `genui`'s rendering engine from any
particular network client. That's the most stable point of contact
available in the currently published API, so it's the *only* thing this
package integrates against.

Concretely, `genui_mock` is split in two:

- **Fixture / recorder / player** (`GenUiFixture`, `GenUiSessionRecorder`,
  `GenUiFixturePlayer`) — plain Dart, zero dependency on `package:genui`.
  These only know about `Stream<String>` chunks and their timing, so they
  can't be broken by a `genui` API change and are fully unit-testable
  without a `genui` dependency at all.
- **`GenUiMockTransport`** (`lib/src/genui_mock_transport.dart`) — the *only*
  file in this package that imports `package:genui`. It implements
  `Transport` by replaying a fixture through `genui`'s own
  `A2uiTransportAdapter`, so parsing the A2UI wire format out of raw text
  chunks is always delegated to `genui` itself — this package never has to
  track or reimplement that protocol.

If a future `genui` release changes `Transport`, only
`genui_mock_transport.dart` should need to change.

## What's recorded

A fixture is a sequence of turns; each turn is the ordered list of raw text
chunks (and inter-chunk delays) that arrived after one `sendRequest` call —
exactly what a real `Transport` streams through `incomingText` /
`incomingMessages`, before any A2UI parsing happens. Recording at this layer
means the fixture captures precisely what the model said, with no lossy
intermediate representation.

## License

MIT — see [LICENSE](LICENSE).

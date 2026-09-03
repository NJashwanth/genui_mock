## 0.1.2

* Upgrade to `genui` `^0.10.2` (from `0.10.1`).
* `genui` 0.10.2 fixed `A2uiTransportAdapter.incomingText` trimming every
  streamed chunk. Since `GenUiMockTransport` replays fixtures *through* that
  adapter, replayed prose is now emitted with its recorded whitespace intact:
  a sentence recorded across two chunks (`'the quick '` + `'brown fox'`) used
  to arrive as `'the quickbrown fox'`, and now round-trips byte for byte.
* The constraint is `^0.10.2` rather than `^0.10.1` deliberately — byte-for-byte
  replay is this package's core promise, and 0.10.1 cannot deliver it.
* If you had assertions that worked around the old trimming (e.g. expecting
  `'Hello.'` for a recorded `'Hello.\n'`), they need updating to expect the
  recorded text. No other API or behavior change.
* No change to the fixture format — existing recorded fixtures keep working
  unchanged, and now replay more faithfully than before.

## 0.1.1

* Upgrade to `genui` `^0.10.1` (from `0.9.2`).
* `genui` 0.10.0 moved its A2UI message types (e.g. `A2uiMessage`,
  `CreateSurface` → `CreateSurfaceMessage`) out to `package:a2ui_core` and
  stopped re-exporting them. `GenUiMockTransport.incomingMessages` is now
  typed against `a2ui_core`'s `A2uiMessage`, and `genui_mock` now depends on
  `a2ui_core: ^0.1.0` directly.
* No change to the fixture format or the JSON wire protocol — this is a
  Dart-type-only migration on genui's side, so existing recorded fixtures
  keep working unchanged.

## 0.1.0

* Initial release.
* `GenUiFixture`, `RecordedTurn`, `RecordedChunk`: a plain-Dart, JSON
  fixture format for recorded GenUI sessions.
* `GenUiSessionRecorder`: records a live `Stream<String>` of model chunks
  (with timing) into a fixture, forwarding chunks through unchanged.
* `GenUiFixturePlayer` / `replayTurn`: replays a fixture's turns as
  `Stream<String>`, either instantly or paced to the original timing.
* `GenUiMockTransport`: implements `genui`'s `Transport` interface by
  replaying a fixture through `genui`'s own `A2uiTransportAdapter`. Built
  against `genui` 0.9.2.

## Unreleased

* Move from `genui` to the A2UI Dart SDKs, which replace it. `genui_mock`
  now depends on `a2ui_core` `^0.5.0` instead of `genui` `^0.10.4` and
  `a2ui_core` `^0.1.0`. The fixture format, `GenUiSessionRecorder` and
  `GenUiFixturePlayer` are unchanged.
* Breaking: `GenUiMockTransport` no longer implements `genui`'s `Transport`.
  It keeps `incomingText`, `incomingMessages`, `sendRequest`, `sentMessages`
  and `dispose`, and a test reads it the way an app reads its live transport.
* Breaking: `incomingMessages` emits `a2ui_core` `AgentToRendererMessage`s,
  the new name of `A2uiMessage`. Pass each one to a `MessageProcessor` with
  `processMessages(AgentToRendererMessagePayload.of(message))`, and render
  the surfaces with `a2ui_flutter`'s `A2uiSurface`.
* Breaking: `sendRequest` takes a `String` instead of a `ChatMessage`, and
  `sentMessages` is a `List<String>`.
* Breaking: recorded A2UI JSON that is not a valid message is added to
  `incomingMessages` as an `A2uiValidationError`. With `genui` it arrived on
  `incomingText` as an `A2uiValidationException`, and as an uncaught error.
* Recorded replies are still split into text and A2UI JSON the way `genui`
  0.10 split them, by a copy of its parser: JSON in markdown fences or bare
  JSON objects becomes messages. Each message is now parsed by `a2ui_core`
  0.5, which also accepts v0.9.1 and v1.0 messages, and rejects fields a
  message does not define and an `updateComponents` with no components.
* Text still held back when a turn ends, such as an unclosed `{` or markdown
  fence, now arrives at the end of that turn. With `genui` it waited for the
  chunks of the next turn.
* `a2ui_flutter`'s `basicCatalog()` has only the canonical basic catalog id.
  Fixtures recorded before `genui` 0.10.3 carry the old
  `https://a2ui.org/specification/v0_9/basic_catalog.json` id, so register
  the basic catalog under that id too, as the README shows.
* The example and the README render with `MessageProcessor` and
  `A2uiSurface`.

## 0.1.3

* Upgrade to `genui` `^0.10.4` (from `0.10.2`).
* `genui` 0.10.3 changed `basicCatalogId` to the canonical
  `https://a2ui.org/specification/v0_9/catalogs/basic/catalog.json` and kept
  the old `https://a2ui.org/specification/v0_9/basic_catalog.json` as an
  alias. Fixtures recorded before 0.10.3 have the old id baked into their
  `createSurface` chunks; they still render against the basic catalog, and a
  new test covers both ids so that stays true.
* `genui` 0.10.4 makes `Image` read the catalog's `description` property as
  accessibility text. Recorded `Image` components that carried a
  `description` now get it announced on replay, with no fixture change.
* The example's fixture now uses the canonical catalog id, which is what new
  recordings will contain.
* No API change and no change to the fixture format.

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

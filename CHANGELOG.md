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

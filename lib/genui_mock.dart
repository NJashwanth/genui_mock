/// Record, save, and replay GenUI streaming sessions as deterministic,
/// git-diffable JSON fixtures — so you can test how a Catalog widget renders
/// against real recorded model output without burning an API call or
/// tolerating non-deterministic responses.
///
/// See the package README for the recommended record → save → replay
/// workflow. [GenUiFixture], [GenUiSessionRecorder], and [GenUiFixturePlayer]
/// have no dependency on A2UI; [GenUiMockTransport] is the small, isolated
/// adapter that replays a fixture as the A2UI messages an `a2ui_core`
/// `MessageProcessor` renders.
library;

export 'src/fixture.dart';
export 'src/genui_mock_transport.dart';
export 'src/player.dart';
export 'src/recorder.dart';

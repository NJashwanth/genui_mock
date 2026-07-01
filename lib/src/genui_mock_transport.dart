/// The only file in this package that imports `package:genui`.
///
/// Everything else (fixture format, recorder, player) is plain Dart with no
/// knowledge of GenUI's object model. This file's only job is to satisfy
/// GenUI's `Transport` interface — the abstraction GenUI itself uses to
/// decouple its rendering engine from any particular network client — by
/// replaying a [GenUiFixture] through it.
///
/// Parsing of A2UI messages out of raw text chunks is delegated entirely to
/// GenUI's own `A2uiTransportAdapter`, so this package never has to track
/// (or fall behind) the A2UI wire format itself.
library;

import 'dart:async';

import 'package:genui/genui.dart';

import 'fixture.dart';
import 'player.dart';

/// A `Transport` that replays a recorded [GenUiFixture] instead of talking
/// to a real model.
///
/// Drop this in wherever your app would normally construct its live
/// `Transport` (e.g. when building a `Conversation`) to get byte-for-byte
/// deterministic, network-free GenUI output in tests:
///
/// ```dart
/// final fixture = GenUiFixture.decode(await File('test/fixtures/weather.json').readAsString());
/// final transport = GenUiMockTransport(fixture);
/// final conversation = Conversation(controller: controller, transport: transport);
/// await conversation.sendRequest(ChatMessage.user('what is the weather?'));
/// ```
///
/// Each call to [sendRequest] consumes and replays the fixture's next
/// recorded turn, mirroring how a real session gets one streamed response
/// per request.
class GenUiMockTransport implements Transport {
  /// Creates a [GenUiMockTransport] that replays [fixture].
  ///
  /// Use [mode] and [speedMultiplier] to control pacing — see
  /// [PlaybackMode] and [GenUiFixturePlayer].
  GenUiMockTransport(
    GenUiFixture fixture, {
    PlaybackMode mode = PlaybackMode.instant,
    double speedMultiplier = 1.0,
  }) : _player = GenUiFixturePlayer(
         fixture,
         mode: mode,
         speedMultiplier: speedMultiplier,
       );

  final GenUiFixturePlayer _player;
  final A2uiTransportAdapter _adapter = A2uiTransportAdapter();

  /// Every message passed to [sendRequest] so far, in order — useful for
  /// asserting on what your code under test actually sent.
  List<ChatMessage> get sentMessages => List.unmodifiable(_sentMessages);
  final List<ChatMessage> _sentMessages = [];

  @override
  Stream<String> get incomingText => _adapter.incomingText;

  @override
  Stream<A2uiMessage> get incomingMessages => _adapter.incomingMessages;

  @override
  Future<void> sendRequest(ChatMessage message) async {
    _sentMessages.add(message);
    await for (final chunk in _player.playNextTurn()) {
      _adapter.addChunk(chunk);
    }
  }

  @override
  void dispose() {
    _adapter.dispose();
  }
}

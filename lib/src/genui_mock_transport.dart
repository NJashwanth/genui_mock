/// The only file in this package that turns a fixture into A2UI messages.
///
/// Everything else (fixture format, recorder, player) is plain Dart with no
/// knowledge of A2UI's object model. This file's only job is to stand in for
/// the transport an app reads model replies from, by replaying a
/// [GenUiFixture] as the text and A2UI messages that transport would hand to
/// an `a2ui_core` `MessageProcessor`.
///
/// Recorded replies are split into text and A2UI JSON the way `genui` 0.10
/// split them (see `reply_parser.dart`), and `a2ui_core` parses each message,
/// so this package never has to track the A2UI wire format itself.
library;

import 'dart:async';

import 'package:a2ui_core/a2ui_core.dart' as core;

import 'fixture.dart';
import 'player.dart';
import 'reply_parser.dart';

/// A transport that replays a recorded [GenUiFixture] instead of talking
/// to a real model.
///
/// Drop this in wherever your app would normally read a live model's
/// replies, and pass its messages to the `MessageProcessor` that renders your
/// surfaces, to get byte-for-byte deterministic, network-free A2UI output in
/// tests:
///
/// ```dart
/// final fixture = GenUiFixture.decode(await File('test/fixtures/weather.json').readAsString());
/// final transport = GenUiMockTransport(fixture);
/// transport.incomingMessages.listen(
///   (message) => processor.processMessages(AgentToRendererMessagePayload.of(message)),
/// );
/// await transport.sendRequest('what is the weather?');
/// ```
///
/// Each call to [sendRequest] consumes and replays the fixture's next
/// recorded turn, mirroring how a real session gets one streamed response
/// per request.
class GenUiMockTransport {
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
  final StreamController<String> _text = StreamController.broadcast();
  final StreamController<core.AgentToRendererMessage> _messages =
      StreamController.broadcast();

  /// Every message passed to [sendRequest] so far, in order — useful for
  /// asserting on what your code under test actually sent.
  List<String> get sentMessages => List.unmodifiable(_sentMessages);
  final List<String> _sentMessages = [];

  /// The recorded prose, streamed back chunk by chunk exactly as it was
  /// recorded — whitespace included, so concatenating the chunks reproduces
  /// the original text byte for byte.
  Stream<String> get incomingText => _text.stream;

  /// The A2UI messages in the recorded replies.
  ///
  /// Pass each one to an `a2ui_core` `MessageProcessor` with
  /// `processMessages(AgentToRendererMessagePayload.of(message))`. Recorded
  /// A2UI JSON that is not a valid message is added to this stream as an
  /// [core.A2uiValidationError], and the rest of the reply is still replayed.
  Stream<core.AgentToRendererMessage> get incomingMessages => _messages.stream;

  /// Records [message] in [sentMessages], then replays the fixture's next
  /// recorded turn through [incomingText] and [incomingMessages].
  ///
  /// [message] is whatever your code would send to the model, such as the
  /// user's text. The reply is the recorded one, whatever [message] says.
  ///
  /// Throws a [StateError] if every recorded turn has already been played.
  Future<void> sendRequest(String message) async {
    _sentMessages.add(message);
    final reply = ReplyParser(
      onText: _text.add,
      onMessage: _messages.add,
      onError: _messages.addError,
    );
    await for (final chunk in _player.playNextTurn()) {
      reply.add(chunk);
    }
    reply.close();
  }

  /// Closes [incomingText] and [incomingMessages].
  void dispose() {
    _text.close();
    _messages.close();
  }
}

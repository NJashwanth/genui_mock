/// Records real streamed chunks (and their timing) into a [GenUiFixture],
/// without depending on `package:genui` at all.
///
/// A [GenUiSessionRecorder] taps whatever `Stream<String>` your app already
/// feeds into GenUI's transport (e.g. the raw chunks from your model API
/// call, before they reach `A2uiTransportAdapter.addChunk`). It forwards
/// every chunk through unchanged — so recording never changes what your app
/// does — while timing the gaps between chunks and accumulating them into
/// turns you can later save as a fixture.
library;

import 'dart:async';

import 'fixture.dart';

/// Records one or more turns of a live GenUI session for later replay.
///
/// Typical usage: wrap the chunk stream for each request/response cycle in
/// [recordTurn], pass the *returned* stream to whatever you'd normally feed
/// (unchanged), and once the session is over call [toFixture] and save the
/// result with [GenUiFixture.encode].
///
/// ```dart
/// final recorder = GenUiSessionRecorder(name: 'weather_forecast');
/// // ...for each user turn:
/// final recordedChunks = recorder.recordTurn(rawChunksFromModel);
/// await for (final chunk in recordedChunks) {
///   transportAdapter.addChunk(chunk); // app behaves exactly as before
/// }
/// // ...once the session is done:
/// final fixture = recorder.toFixture();
/// await File('test/fixtures/weather_forecast.json').writeAsString(fixture.encode());
/// ```
class GenUiSessionRecorder {
  /// Creates a [GenUiSessionRecorder].
  GenUiSessionRecorder({required this.name, this.description});

  /// The name that will be given to the produced [GenUiFixture].
  final String name;

  /// The description that will be given to the produced [GenUiFixture].
  final String? description;

  final List<RecordedTurn> _turns = [];

  /// The turns recorded so far.
  List<RecordedTurn> get turns => List.unmodifiable(_turns);

  /// Taps [chunks], recording each chunk's text and the time elapsed since
  /// the previous one (or since subscription, for the first chunk), and
  /// forwards every chunk downstream unchanged.
  ///
  /// The recorded turn is appended to [turns] only once [chunks] closes, so
  /// make sure to fully drain the returned stream.
  Stream<String> recordTurn(Stream<String> chunks, {String? label}) {
    final recorded = <RecordedChunk>[];
    final stopwatch = Stopwatch();
    late final StreamController<String> controller;
    StreamSubscription<String>? subscription;

    controller = StreamController<String>(
      onListen: () {
        stopwatch.start();
        subscription = chunks.listen(
          (chunk) {
            recorded.add(RecordedChunk(text: chunk, delay: stopwatch.elapsed));
            stopwatch.reset();
            controller.add(chunk);
          },
          onError: controller.addError,
          onDone: () {
            _turns.add(
              RecordedTurn(chunks: List.unmodifiable(recorded), label: label),
            );
            controller.close();
          },
          cancelOnError: false,
        );
      },
      onCancel: () => subscription?.cancel(),
    );
    return controller.stream;
  }

  /// Builds a [GenUiFixture] out of every turn recorded so far.
  GenUiFixture toFixture() => GenUiFixture(
    name: name,
    description: description,
    turns: List.unmodifiable(_turns),
  );
}

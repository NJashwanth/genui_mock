/// The fixture data model: a plain-Dart, JSON-serializable recording of one
/// or more GenUI conversation turns.
///
/// Nothing in this file depends on `package:genui`. A fixture is just a
/// sequence of text chunks with the timing they originally arrived with,
/// which is exactly what a real GenUI [`Transport`] streams in and out —
/// see `genui_mock_transport.dart` for the one file that bridges the two.
library;

import 'dart:convert';

/// The JSON schema version written by this release of `genui_mock`.
///
/// Bump this if [GenUiFixture.toJson]/[GenUiFixture.fromJson] ever change in
/// a way that isn't backwards compatible, so old fixtures can still be
/// migrated or rejected with a clear error instead of failing silently.
const int genUiFixtureFormatVersion = 1;

/// A single chunk of text as it was received from the model, plus how long
/// after the *previous* chunk (or after the request was sent, for the first
/// chunk of a turn) it arrived.
class RecordedChunk {
  /// Creates a [RecordedChunk].
  const RecordedChunk({required this.text, required this.delay});

  /// Deserializes a [RecordedChunk] from JSON.
  factory RecordedChunk.fromJson(Map<String, dynamic> json) {
    return RecordedChunk(
      text: json['text'] as String,
      delay: Duration(milliseconds: json['delayMs'] as int),
    );
  }

  /// The raw text chunk, exactly as streamed by the model.
  final String text;

  /// How long after the previous event this chunk arrived.
  final Duration delay;

  /// Serializes this chunk to JSON.
  Map<String, dynamic> toJson() => {
    'text': text,
    'delayMs': delay.inMilliseconds,
  };

  @override
  bool operator ==(Object other) =>
      other is RecordedChunk && other.text == text && other.delay == delay;

  @override
  int get hashCode => Object.hash(text, delay);

  @override
  String toString() =>
      'RecordedChunk(${delay.inMilliseconds}ms, ${text.length} chars)';
}

/// All the chunks that made up one streamed model response, i.e. everything
/// that arrived after a single call to `Transport.sendRequest`.
class RecordedTurn {
  /// Creates a [RecordedTurn].
  const RecordedTurn({required this.chunks, this.label});

  /// Deserializes a [RecordedTurn] from JSON.
  factory RecordedTurn.fromJson(Map<String, dynamic> json) {
    return RecordedTurn(
      label: json['label'] as String?,
      chunks: (json['chunks'] as List<dynamic>)
          .map((e) => RecordedChunk.fromJson(e as Map<String, dynamic>))
          .toList(growable: false),
    );
  }

  /// An optional human-readable note about what this turn represents, e.g.
  /// `"user asks for a 3-day forecast"`. Purely descriptive; never read by
  /// the replay logic.
  final String? label;

  /// The ordered chunks that made up the model's response for this turn.
  final List<RecordedChunk> chunks;

  /// Serializes this turn to JSON.
  Map<String, dynamic> toJson() => {
    if (label != null) 'label': label,
    'chunks': chunks.map((c) => c.toJson()).toList(growable: false),
  };
}

/// A recorded GenUI session: one or more [RecordedTurn]s captured from a
/// real, live conversation, saved so it can be replayed later without any
/// network access.
class GenUiFixture {
  /// Creates a [GenUiFixture].
  GenUiFixture({
    required this.name,
    required this.turns,
    this.description,
    DateTime? recordedAt,
  }) : recordedAt = recordedAt ?? DateTime.now();

  /// Deserializes a [GenUiFixture] from a decoded JSON map.
  ///
  /// Throws a [FormatException] if the fixture was written by an
  /// incompatible (newer) format version.
  factory GenUiFixture.fromJson(Map<String, dynamic> json) {
    final formatVersion = json['formatVersion'] as int? ?? 1;
    if (formatVersion > genUiFixtureFormatVersion) {
      throw FormatException(
        'This fixture was written with genui_mock format version '
        '$formatVersion, but this version of genui_mock only understands up '
        'to $genUiFixtureFormatVersion. Upgrade genui_mock to read it.',
      );
    }
    return GenUiFixture(
      name: json['name'] as String,
      description: json['description'] as String?,
      recordedAt: DateTime.parse(json['recordedAt'] as String),
      turns: (json['turns'] as List<dynamic>)
          .map((e) => RecordedTurn.fromJson(e as Map<String, dynamic>))
          .toList(growable: false),
    );
  }

  /// A short identifying name for this fixture, e.g. `"weather_forecast"`.
  final String name;

  /// An optional longer description of what this session recorded.
  final String? description;

  /// When this fixture was recorded.
  final DateTime recordedAt;

  /// The ordered turns captured in this session. Replaying the fixture
  /// consumes them in this order, one per `sendRequest` call.
  final List<RecordedTurn> turns;

  /// Serializes this fixture to a decoded JSON map.
  Map<String, dynamic> toJson() => {
    'formatVersion': genUiFixtureFormatVersion,
    'name': name,
    if (description != null) 'description': description,
    'recordedAt': recordedAt.toUtc().toIso8601String(),
    'turns': turns.map((t) => t.toJson()).toList(growable: false),
  };

  /// Encodes this fixture as pretty-printed, git-diffable JSON text.
  ///
  /// Intentionally avoids any `dart:io` dependency so the same fixture file
  /// can be loaded on every platform GenUI runs on (including web) — write
  /// the returned string with whatever file API suits your project (e.g.
  /// `File(path).writeAsString(...)` or an asset in `test/fixtures/`).
  String encode() => const JsonEncoder.withIndent('  ').convert(toJson());

  /// Decodes a fixture previously produced by [encode].
  static GenUiFixture decode(String jsonText) =>
      GenUiFixture.fromJson(jsonDecode(jsonText) as Map<String, dynamic>);
}

// Adapted from `A2uiParserTransformer` in package:genui 0.10.4
// (https://github.com/flutter/genui/tree/main/packages/genui), which carries
// this notice:
//
// Copyright 2025 The Flutter Authors.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are
// met:
//
//     * Redistributions of source code must retain the above copyright
//       notice, this list of conditions and the following disclaimer.
//     * Redistributions in binary form must reproduce the above
//       copyright notice, this list of conditions and the following
//       disclaimer in the documentation and/or other materials provided
//       with the distribution.
//     * Neither the name of Google Inc. nor the names of its
//       contributors may be used to endorse or promote products derived
//       from this software without specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
// IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
// ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
// LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
// CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
// SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
// INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
// CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
// ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
// POSSIBILITY OF SUCH DAMAGE.

/// Splits a model's streamed reply into prose and A2UI messages, the way
/// `genui` 0.10 read replies before it was replaced by the A2UI SDKs.
///
/// Fixtures recorded with `genui` hold A2UI JSON in markdown fences or as
/// bare JSON objects, which is what `genui`'s prompt asked models to write.
/// Keeping `genui`'s parser means those fixtures replay with the same text and
/// the same messages as before.
library;

import 'dart:convert';

import 'package:a2ui_core/a2ui_core.dart';

/// Reads the text chunks of one reply and reports prose to [onText], each
/// A2UI message to [onMessage], and each JSON payload that looks like an A2UI
/// message but is not a valid one to [onError].
///
/// Call [add] for each chunk and [close] once the reply has ended, which
/// reports the text still held back while waiting for a JSON payload to
/// complete.
class ReplyParser {
  /// Creates a [ReplyParser] for one reply.
  ReplyParser({
    required this.onText,
    required this.onMessage,
    required this.onError,
  });

  /// Receives the prose of the reply, with its whitespace.
  final void Function(String text) onText;

  /// Receives each A2UI message of the reply.
  final void Function(AgentToRendererMessage message) onMessage;

  /// Receives the error for each A2UI message that could not be read.
  final void Function(A2uiValidationError error) onError;

  String _buffer = '';

  // When true, whitespace-only content is treated as a JSONL separator and
  // discarded. When false, it is reported as text.
  bool _wasLastEventA2ui = false;

  /// Reads the next chunk of the reply.
  void add(String chunk) {
    _buffer += chunk;
    _processBuffer();
  }

  /// Ends the reply, reporting any text still held back as text.
  void close() {
    if (_buffer.isNotEmpty) {
      _emitText(_buffer);
      _buffer = '';
    }
  }

  void _processBuffer() {
    while (_buffer.isNotEmpty) {
      // 1. Check for a markdown JSON block.
      final _Match? markdownMatch = _findMarkdownJson(_buffer);
      if (markdownMatch != null) {
        try {
          final Object? decoded = jsonDecode(markdownMatch.content);
          if (decoded != null) {
            _emitBefore(markdownMatch.start);
            _emitMessage(decoded);
            _buffer = _buffer.substring(markdownMatch.end);
            continue;
          }
        } on FormatException {
          // Invalid JSON in a markdown block. Report it as text right away,
          // so the fallback below does not wait for more data forever.
          _emitBefore(markdownMatch.start);
          _emitText(markdownMatch.original);
          _buffer = _buffer.substring(markdownMatch.end);
          continue;
        }
      }

      // 2. Check for balanced JSON.
      final _Match? jsonMatch = _findBalancedJson(_buffer);
      if (jsonMatch != null) {
        try {
          final Object? decoded = jsonDecode(jsonMatch.content);
          if (decoded != null) {
            _emitBefore(jsonMatch.start);
            _emitMessage(decoded);
            _buffer = _buffer.substring(jsonMatch.end);
            continue;
          }
        } on FormatException {
          // Invalid JSON. Report it as text right away to avoid stalling.
          _emitBefore(jsonMatch.start);
          _emitText(jsonMatch.original);
          _buffer = _buffer.substring(jsonMatch.end);
          continue;
        }
      }

      // 3. Fall back, or wait for more data.
      final int markdownStart = _buffer.indexOf('```');
      final int braceStart = _buffer.indexOf('{');

      var firstPotentialStart = -1;
      if (markdownStart != -1 && braceStart != -1) {
        firstPotentialStart = markdownStart < braceStart
            ? markdownStart
            : braceStart;
      } else if (markdownStart != -1) {
        firstPotentialStart = markdownStart;
      } else {
        firstPotentialStart = braceStart;
      }

      if (firstPotentialStart == -1) {
        // No potential JSON start.
        if (_buffer.isNotEmpty) {
          if (_wasLastEventA2ui && _buffer.trim().isEmpty) {
            // Whitespace-only after a JSON message: treat it as a JSONL
            // separator, and hold it until more data arrives or the reply
            // ends.
            break;
          }
          _emitText(_buffer);
          _buffer = '';
        }
        break;
      } else {
        // Found a potential start at `firstPotentialStart`.
        if (firstPotentialStart > 0) {
          final String prefix = _buffer.substring(0, firstPotentialStart);
          if (_wasLastEventA2ui && prefix.trim().isEmpty) {
            // Skip a whitespace-only prefix after a JSON message (JSONL
            // separator).
            _buffer = _buffer.substring(firstPotentialStart);
            continue;
          }
          _emitText(prefix);
          _buffer = _buffer.substring(firstPotentialStart);
        }
        // The buffer starts with potential JSON. Wait for more data.
        break;
      }
    }
  }

  void _emitBefore(int index) {
    if (index > 0) {
      _emitText(_buffer.substring(0, index));
    }
  }

  void _emitText(String text) {
    _wasLastEventA2ui = false;
    // Remove protocol tags that might leak into the text.
    final String cleanText = text
        .replaceAll('<a2ui_message>', '')
        .replaceAll('</a2ui_message>', '');

    if (cleanText.isNotEmpty) {
      onText(cleanText);
    }
  }

  /// Top-level keys that mark a JSON payload as an attempted A2UI message.
  /// If reading one of these fails, report an error rather than fall back to
  /// plain text. `version` is included so that a malformed but versioned
  /// payload still counts as an attempted message.
  static const _a2uiMessageKeys = {
    'version',
    'createSurface',
    'updateComponents',
    'updateDataModel',
    'deleteSurface',
  };

  bool _looksLikeA2uiMessage(Map<String, Object?> json) =>
      json.keys.any(_a2uiMessageKeys.contains);

  void _emitMessage(Object json) {
    if (json is Map<String, Object?>) {
      _tryEmitOne(json);
    } else if (json is List) {
      for (final Object? item in json) {
        if (item is Map<String, Object?>) {
          _tryEmitOne(item);
        }
      }
    }
  }

  void _tryEmitOne(Map<String, Object?> json) {
    try {
      onMessage(AgentToRendererMessage.fromJson(json));
      _wasLastEventA2ui = true;
    } on A2uiValidationError catch (error) {
      if (_looksLikeA2uiMessage(json)) {
        onError(error);
      } else {
        // Not an A2UI message; report it as plain text.
        onText(jsonEncode(json));
      }
      _wasLastEventA2ui = false;
    }
  }

  _Match? _findMarkdownJson(String text) {
    final regex = RegExp(r'```(?:json)?\s*([\s\S]*?)\s*```');
    final RegExpMatch? match = regex.firstMatch(text);
    if (match != null) {
      return _Match(
        match.start,
        match.end,
        match.group(1) ?? '',
        match.group(0) ?? '',
      );
    }
    return null;
  }

  _Match? _findBalancedJson(String input) {
    if (!input.startsWith('{')) return null;

    var balance = 0;
    var inString = false;
    var isEscaped = false;

    for (var i = 0; i < input.length; i++) {
      final String char = input[i];

      if (isEscaped) {
        isEscaped = false;
        continue;
      }
      if (char == '\\') {
        isEscaped = true;
        continue;
      }
      if (char == '"') {
        inString = !inString;
        continue;
      }

      if (!inString) {
        if (char == '{') {
          balance++;
        } else if (char == '}') {
          balance--;
          if (balance == 0) {
            final String text = input.substring(0, i + 1);
            return _Match(0, i + 1, text, text);
          }
        }
      }
    }
    return null;
  }
}

class _Match {
  _Match(this.start, this.end, this.content, this.original);
  final int start;
  final int end;
  final String content;
  final String original;
}

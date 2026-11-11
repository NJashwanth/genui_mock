// Demonstrates replaying a recorded genui_mock fixture through A2UI's real
// `MessageProcessor` and `A2uiSurface` widget — no network access, no API key.
//
// In a real app the fixture below would come from `GenUiFixture.decode(...)`
// on a JSON file you saved with `GenUiSessionRecorder` while recording a live
// session (see the package README). Here it's built in code so this example
// runs standalone with nothing to record from.
import 'dart:async';

import 'package:a2ui_core/a2ui_core.dart';
import 'package:a2ui_flutter/a2ui_flutter.dart';
import 'package:a2ui_flutter/v0_9/basic_catalog.dart' as v0_9;
import 'package:flutter/material.dart';
import 'package:genui_mock/genui_mock.dart';

void main() => runApp(const ExampleApp());

/// A fixture that mimics what a model would actually stream back: some
/// prose, then a `createSurface` message, then an `updateComponents`
/// message describing a card with a text child — each as its own chunk,
/// exactly as they'd arrive over the wire.
GenUiFixture _greetingFixture() {
  return GenUiFixture(
    name: 'greeting_card',
    description: 'user asks for a friendly greeting',
    turns: [
      RecordedTurn(
        chunks: [
          const RecordedChunk(
            text: "Here's a friendly greeting for you:\n",
            delay: Duration.zero,
          ),
          const RecordedChunk(
            text:
                '```json\n'
                '{"version": "v0.9", "createSurface": '
                '{"surfaceId": "greeting", '
                '"catalogId": "https://a2ui.org/specification/v0_9/catalogs/basic/catalog.json"}}\n'
                '```',
            delay: Duration(milliseconds: 300),
          ),
          const RecordedChunk(
            text:
                '```json\n'
                '{"version": "v0.9", "updateComponents": {"surfaceId": "greeting", "components": ['
                '{"id": "root", "component": "Card", "child": "message"},'
                '{"id": "message", "component": "Text", "text": "Hello from a recorded genui_mock fixture!"}'
                ']}}\n'
                '```',
            delay: Duration(milliseconds: 400),
          ),
        ],
      ),
    ],
  );
}

class ExampleApp extends StatefulWidget {
  const ExampleApp({super.key});

  @override
  State<ExampleApp> createState() => _ExampleAppState();
}

class _ExampleAppState extends State<ExampleApp> {
  late final GenUiMockTransport _transport;
  late final MessageProcessor<ComponentImplementation> _processor;
  late final Subscription _surfaceCreated;
  late final StreamSubscription<AgentToRendererMessage> _messages;
  SurfaceModel<ComponentImplementation>? _surface;

  @override
  void initState() {
    super.initState();
    _transport = GenUiMockTransport(
      _greetingFixture(),
      mode: PlaybackMode.paced,
    );
    _processor = MessageProcessor(
      catalogs: [v0_9.basicCatalog()],
      // The surface streams in over several messages, which the strict
      // checks would reject.
      validationConfig: ValidationConfig.relaxed,
    );

    _surfaceCreated = _processor.model.onSurfaceCreated.subscribe((surface) {
      setState(() => _surface = surface);
    });
    _messages = _transport.incomingMessages.listen(
      (message) =>
          _processor.processMessages(AgentToRendererMessagePayload.of(message)),
    );

    // Replaying a fixture never touches the network — this resolves as soon
    // as the recorded chunks have been replayed.
    _transport.sendRequest('Show me a greeting');
  }

  @override
  void dispose() {
    _messages.cancel();
    _surfaceCreated.unsubscribe();
    _processor.dispose();
    _transport.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('genui_mock example')),
        body: Center(
          child: _surface == null
              ? const CircularProgressIndicator()
              : A2uiSurface(key: ObjectKey(_surface), surface: _surface!),
        ),
      ),
    );
  }
}

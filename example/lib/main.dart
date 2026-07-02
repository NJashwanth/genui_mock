// Demonstrates replaying a recorded genui_mock fixture through GenUI's real
// `SurfaceController` and `Surface` widget — no network access, no API key.
//
// In a real app the fixture below would come from `GenUiFixture.decode(...)`
// on a JSON file you saved with `GenUiSessionRecorder` while recording a live
// session (see the package README). Here it's built in code so this example
// runs standalone with nothing to record from.
import 'package:flutter/material.dart';
import 'package:genui/genui.dart';
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
                '"catalogId": "https://a2ui.org/specification/v0_9/basic_catalog.json"}}\n'
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
  late final SurfaceController _controller;
  late final Conversation _conversation;
  String? _surfaceId;

  @override
  void initState() {
    super.initState();
    _transport = GenUiMockTransport(
      _greetingFixture(),
      mode: PlaybackMode.paced,
    );
    _controller = SurfaceController(catalogs: [BasicCatalogItems.asCatalog()]);
    _conversation = Conversation(
      transport: _transport,
      controller: _controller,
    );

    _controller.surfaceUpdates.listen((update) {
      if (update is SurfaceAdded) {
        setState(() => _surfaceId = update.surfaceId);
      }
    });

    // Replaying a fixture never touches the network — this resolves as soon
    // as the recorded chunks have been replayed.
    _conversation.sendRequest(ChatMessage.user('Show me a greeting'));
  }

  @override
  void dispose() {
    _conversation.dispose();
    _controller.dispose();
    _transport.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('genui_mock example')),
        body: Center(
          child: _surfaceId == null
              ? const CircularProgressIndicator()
              : Surface(surfaceContext: _controller.contextFor(_surfaceId!)),
        ),
      ),
    );
  }
}

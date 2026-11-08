import 'package:flutter/material.dart';
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:vable_flutter/vable_flutter.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  String _platformVersion = 'Unknown';
  String _statusMessage = 'Not initialized';
  bool _isInitialized = false;
  bool _isVoiceChatActive = false;

  // Replace with your actual Vable public key, or pass one:
  // flutter run --dart-define=VABLE_PUBLIC_KEY=<key> --dart-define=VABLE_ENV=dev
  static const String vablePublicKey =
      String.fromEnvironment('VABLE_PUBLIC_KEY', defaultValue: 'your-public-key-here');
  static const String vableEnvironment = String.fromEnvironment('VABLE_ENV');

  // The signed-in user's token, from your backend. Leave it empty for guests.
  // To try it: flutter run --dart-define=VABLE_ACCESS_TOKEN=<token>
  static const String vableAccessToken = String.fromEnvironment('VABLE_ACCESS_TOKEN');

  /// What the assistant last set with the example's intent
  String _assistantNote = '';

  @override
  void initState() {
    super.initState();
    initPlatformState();
    Vable.onVoiceChatStarted = () => setState(() => _isVoiceChatActive = true);
    Vable.onVoiceChatEnded = () => setState(() => _isVoiceChatActive = false);
  }

  /// Something the assistant can do from a call or the chat. Registered once
  /// the SDK is initialized, since Android takes intents only after that.
  void _registerIntents() {
    Vable.registerIntent(VableIntent(
      name: 'showNote',
      description: 'Shows a short note on the example app\'s screen',
      parameters: {
        'note': IntentParameter(description: 'The note to show', type: 'string', required: true),
      },
      onIntent: (parameters) {
        setState(() => _assistantNote = '${parameters['note'] ?? ''}');
        return 'The note is on the screen';
      },
    ));
  }

  Future<void> initPlatformState() async {
    String platformVersion;
    try {
      platformVersion =
          await Vable.getPlatformVersion() ?? 'Unknown platform version';
    } on PlatformException {
      platformVersion = 'Failed to get platform version.';
    }

    if (!mounted) return;

    setState(() {
      _platformVersion = platformVersion;
    });
  }

  Future<void> _initializeVable() async {
    try {
      setState(() {
        _statusMessage = 'Initializing...';
      });

      final success = await Vable.initialize(
        vablePublicKey,
        environment: vableEnvironment.isEmpty ? null : vableEnvironment,
        accessToken: vableAccessToken.isEmpty ? null : vableAccessToken,
      );

      if (success) _registerIntents();
      setState(() {
        _isInitialized = success;
        _statusMessage = success ? 'Initialized successfully' : 'Initialization failed';
      });
    } catch (e) {
      setState(() {
        _statusMessage = 'Error: $e';
      });
    }
  }

  Future<void> _startVoiceChat() async {
    try {
      setState(() {
        _statusMessage = 'Starting voice chat...';
      });

      // Pass context to enable Flutter screen scanning
      final success = await Vable.startVoiceChat(context);

      if (success) {
        final isActive = await Vable.isVoiceChatActive();
        setState(() {
          _isVoiceChatActive = isActive;
          _statusMessage = 'Voice chat started (screen scanning enabled)';
        });
      } else {
        setState(() {
          _statusMessage = 'Failed to start voice chat';
        });
      }
    } catch (e) {
      setState(() {
        _statusMessage = 'Error: $e';
      });
    }
  }

  Future<void> _endVoiceChat() async {
    try {
      setState(() {
        _statusMessage = 'Ending voice chat...';
      });

      final success = await Vable.endVoiceChat();

      if (success) {
        final isActive = await Vable.isVoiceChatActive();
        setState(() {
          _isVoiceChatActive = isActive;
          _statusMessage = 'Voice chat ended';
        });
      } else {
        setState(() {
          _statusMessage = 'Failed to end voice chat';
        });
      }
    } catch (e) {
      setState(() {
        _statusMessage = 'Error: $e';
      });
    }
  }

  /// Opens the text chat, for users who would rather type
  Future<void> _openChat(BuildContext context) async {
    try {
      await Vable.openChat(context);
    } catch (e) {
      setState(() => _statusMessage = 'Error: $e');
    }
  }

  Future<void> _checkStatus() async {
    try {
      final isActive = await Vable.isVoiceChatActive();
      setState(() {
        _isVoiceChatActive = isActive;
        _statusMessage = isActive ? 'Voice chat is active' : 'Voice chat is not active';
      });
    } catch (e) {
      setState(() {
        _statusMessage = 'Error: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Vable Flutter Example'),
        ),
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Running on: $_platformVersion',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 20),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      Text(
                        'Status',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(_statusMessage),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _isInitialized ? Icons.check_circle : Icons.circle_outlined,
                            color: _isInitialized ? Colors.green : Colors.grey,
                          ),
                          const SizedBox(width: 8),
                          const Text('Initialized'),
                          const SizedBox(width: 20),
                          Icon(
                            _isVoiceChatActive ? Icons.mic : Icons.mic_off,
                            color: _isVoiceChatActive ? Colors.green : Colors.grey,
                          ),
                          const SizedBox(width: 8),
                          const Text('Voice Chat'),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _isInitialized ? null : _initializeVable,
                child: const Text('Initialize Vable'),
              ),
              const SizedBox(height: 10),
              // Voice first, with the chat beside it for users who would rather type
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: !_isInitialized || _isVoiceChatActive ? null : _startVoiceChat,
                      icon: const Icon(Icons.mic),
                      label: const Text('Start Voice Chat'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    key: const Key('openChat'),
                    tooltip: 'Chat',
                    onPressed: _isInitialized ? () => _openChat(context) : null,
                    icon: const Icon(Icons.chat_bubble_outline),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ElevatedButton(
                onPressed: !_isInitialized || !_isVoiceChatActive ? null : _endVoiceChat,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
                child: const Text('End Voice Chat'),
              ),
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed: _isInitialized ? _checkStatus : null,
                child: const Text('Check Status'),
              ),
              const SizedBox(height: 10),
              if (_assistantNote.isNotEmpty)
                Text('Assistant\'s note: $_assistantNote', key: const Key('assistantNote')),
              // The conversation, as an app with its own chat UI would read it
              StreamBuilder<List<VableChatMessage>>(
                stream: Vable.chatMessages,
                initialData: Vable.currentChatMessages,
                builder: (context, snapshot) {
                  final messages = snapshot.data ?? const [];
                  final last = messages.where((m) => m.role == VableChatRole.assistant).lastOrNull;
                  return Text(
                    '${messages.length} chat lines. Last reply: ${last?.text ?? '-'}',
                    style: Theme.of(context).textTheme.bodySmall,
                  );
                },
              ),
              const SizedBox(height: 20),
              const Divider(),
              const SizedBox(height: 10),
              Text(
                'Note: Make sure to replace "your-public-key-here" with your actual Vable public key in the code.',
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

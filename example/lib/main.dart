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

  // Replace with your actual Vable public key
  static const String vablePublicKey = 'your-public-key-here';

  @override
  void initState() {
    super.initState();
    initPlatformState();
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

      final success = await Vable.initialize(vablePublicKey);

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
              ElevatedButton(
                onPressed: !_isInitialized || _isVoiceChatActive ? null : _startVoiceChat,
                child: const Text('Start Voice Chat'),
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

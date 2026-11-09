import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:vable_flutter/vable_flutter.dart';

/// An app that draws the agent's UI itself, with [VableCallStyle.none]. It
/// shows the agent's state and reply, highlights what the agent is about to
/// touch, and keeps paying for the user.
///
/// Run it with `--dart-define=VABLE_HEADLESS=true`. With
/// `--dart-define=VABLE_AUTO_START=true` the call starts on launch, and each
/// event is printed as a `VABLE_QA` line for tests.
class HeadlessDemo extends StatefulWidget {
  const HeadlessDemo({super.key, required this.publicKey, this.environment});

  final String publicKey;
  final String? environment;

  @override
  State<HeadlessDemo> createState() => _HeadlessDemoState();
}

class _HeadlessDemoState extends State<HeadlessDemo> {
  static const bool _autoStart = bool.fromEnvironment('VABLE_AUTO_START');
  static const bool _muteMic = bool.fromEnvironment('VABLE_MUTE_MIC');

  final _navigatorKey = GlobalKey<NavigatorState>();
  final _destination = TextEditingController();
  StreamSubscription<VableEvent>? _events;

  VableAgentState _state = VableAgentState.idle;
  String _reply = '';
  Rect? _highlight;
  String _searched = '';
  bool _inCall = false;

  @override
  void initState() {
    super.initState();
    _events = Vable.events.listen(_onEvent);
    _setUp();
  }

  Future<void> _setUp() async {
    VableLogger.enabled = _autoStart;
    await Vable.initialize(widget.publicKey, environment: widget.environment);
    await Vable.setCallStyle(VableCallStyle.none);
    Vable.setTyping(const VableTyping.perCharacter(Duration(milliseconds: 40)));
    Vable.setActionGate(_beforeAction);
    if (_muteMic) await Vable.setMicrophoneMuted(true);
    if (_autoStart) {
      // The navigator's context, once the first frame is up
      await WidgetsBinding.instance.endOfFrame;
      await _startCall();
    }
  }

  /// Shows the agent's target for a moment before it acts. Deleting is kept
  /// back, to show a declined action.
  Future<bool> _beforeAction(VableAction action) async {
    _log('gate', {
      'kind': action.kind.name,
      'label': action.label,
      'hasBounds': action.bounds != null,
    });
    if (action.label?.contains('Delete') ?? false) return false;
    setState(() => _highlight = action.bounds);
    await Future.delayed(const Duration(milliseconds: 400));
    return true;
  }

  void _onEvent(VableEvent event) {
    switch (event) {
      case VableAgentStateChanged(:final state):
        setState(() => _state = state);
        _log('state', {'state': state.name});
      case VableAssistantText(:final text, :final isStreaming):
        setState(() => _reply = text);
        if (!isStreaming) _log('reply', {'text': text});
      case VableActionStarted(:final action):
        _log('actionStarted', {
          'id': action.id,
          'kind': action.kind.name,
          'label': action.label,
        });
      case VableActionFinished(:final action, :final ok, :final result):
        setState(() => _highlight = null);
        _log('actionFinished', {
          'id': action.id,
          'kind': action.kind.name,
          'ok': ok,
          'result': result,
        });
      case VableCallStarted():
        setState(() => _inCall = true);
        _log('call', {'state': 'started'});
      case VableCallEnded():
        setState(() => _inCall = false);
        _log('call', {'state': 'ended'});
      case VableInputLevel():
      case VableUserTranscript():
      case VableUserInterrupted():
        break;
    }
  }

  void _log(String event, Map<String, Object?> details) {
    if (_autoStart) {
      debugPrint('VABLE_QA ${jsonEncode({'event': event, ...details})}');
    }
  }

  Future<void> _startCall() async {
    final context = _navigatorKey.currentContext;
    if (context == null) return;
    try {
      await Vable.startVoiceChat(context);
    } catch (e) {
      _log('error', {'message': '$e'});
    }
  }

  @override
  void dispose() {
    _events?.cancel();
    _destination.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      builder: (context, child) => Stack(
        children: [
          child!,
          if (_highlight != null)
            Positioned.fromRect(
              rect: _highlight!.inflate(4),
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.deepPurple, width: 3),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
        ],
      ),
      home: Scaffold(
        appBar: AppBar(title: const Text('Trips')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              controller: _destination,
              decoration: const InputDecoration(labelText: 'Destination'),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () => setState(() => _searched = _destination.text),
              child: const Text('Search trips'),
            ),
            if (_searched.isNotEmpty) Text('Showing trips to $_searched'),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () {},
              child: const Text('Delete saved trips'),
            ),
            const SizedBox(height: 12),
            VableRequiresUser(
              reason: 'payment',
              child: FilledButton(
                onPressed: () {},
                child: const Text('Pay £240'),
              ),
            ),
            const Divider(height: 40),
            // The app's own call UI, kept from the agent
            ExcludeSemantics(child: _callControls()),
          ],
        ),
      ),
    );
  }

  Widget _callControls() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Assistant: ${_state.name}', key: const Key('agentState')),
        if (_reply.isNotEmpty) Text(_reply),
        const SizedBox(height: 12),
        if (_inCall)
          // A touch pauses the agent; this lets it carry on
          TextButton(
            onPressed: () {
              Vable.resumeActions();
              _log('resumed', {});
            },
            child: const Text('Carry on'),
          ),
        _inCall
            ? OutlinedButton(
                onPressed: Vable.endVoiceChat,
                child: const Text('End call'),
              )
            : FilledButton.icon(
                onPressed: _startCall,
                icon: const Icon(Icons.mic),
                label: const Text('Talk to the assistant'),
              ),
      ],
    );
  }
}

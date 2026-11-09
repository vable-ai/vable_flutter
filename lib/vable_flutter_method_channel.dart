import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'src/agent_control.dart';
import 'vable_flutter.dart';
import 'vable_flutter_platform_interface.dart';

/// An implementation of [VableFlutterPlatform] that uses method channels.
class MethodChannelVableFlutter extends VableFlutterPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('vable_flutter');

  /// Constructor that sets up the method call handler
  MethodChannelVableFlutter() {
    methodChannel.setMethodCallHandler(_handleMethodCall);
  }

  /// Handle method calls from the native side
  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onNavigate':
        final url = call.arguments['url'] as String?;
        if (url != null) {
          final toolId = call.arguments['toolId'] as String?;
          await _withFrames(toolId, () => _navigate(url, toolId));
        } else {
          VableLogger.error('[VableFlutter] Warning: onNavigate called without url argument');
        }
      case 'onAssistantText':
        _control.onAssistantText(
          call.arguments?['text'] as String? ?? '',
          isFinal: call.arguments?['isFinal'] as bool? ?? false,
        );
      case 'onVoiceLevels':
        _control.onVoiceLevels(
          (call.arguments?['agent'] as num?)?.toDouble() ?? 0,
          (call.arguments?['user'] as num?)?.toDouble() ?? 0,
        );
      case 'onVoiceChatEnded':
        Vable.handleVoiceChatEnded();
      case 'onVoiceChatStarted':
        await Vable.handleVoiceChatStarted();
      case 'onChatUpdated':
        Vable.handleChatUpdated(VableChatMessage.listFrom(call.arguments?['messages']));
      case 'onChatError':
        Vable.handleChatError(call.arguments?['code'] as String? ?? 'message_failed');
      case 'onChatOpened':
        Vable.handleChatOpened();
      case 'onChatClosed':
        Vable.handleChatClosed();
      case 'onIntent':
        final intentId = call.arguments['id'] as String?;
        // The ID of the agent's tool call, sent back with the result
        final toolId = call.arguments['toolId'] as String?;
        final parameters = (call.arguments['parameters'] as Map?)
            ?.cast<String, dynamic>() ?? {};
        VableLogger.debug('[VableFlutter] onIntent received: id=$intentId, parameters=$parameters');
        if (intentId != null) {
          await _withFrames(toolId, () => _runIntent(intentId, parameters, toolId));
        }
      default:
        VableLogger.error('[VableFlutter] Unknown method call: ${call.method}');
    }
  }

  /// Runs [action] between the frames taken before and after it, when the
  /// project records them. Neither frame holds the action up.
  Future<void> _withFrames(String? toolId, Future<void> Function() action) async {
    final frames = ScreenScannerManager().frames;
    frames.actionBefore(toolId);
    try {
      await action();
    } finally {
      frames.actionAfter(toolId);
    }
  }

  VableAgentControl get _control => VableAgentControl.instance;

  /// Opens a route for the agent, once the app lets it, and sends the result.
  Future<void> _navigate(String url, String? toolId) async {
    final actionId = toolId ?? _control.localId();
    final waited = await _control.beforeAct(VableAction(
      id: actionId,
      kind: VableActionKind.navigate,
      tool: 'navigate',
      args: {'url': url},
    ));
    final result = waited ?? await Vable.navigateForAgent(url);
    await Vable.sendToolResult(
      toolName: 'navigate',
      toolId: toolId,
      result: _control.finish(actionId, result),
    );
  }

  /// Does what the agent asked for and sends it the result.
  Future<void> _runIntent(String intentId, Map<String, dynamic> parameters, String? toolId) async {
    final actionId = toolId ?? _control.localId();
    String result;
    try {
      result = await _resultOf(intentId, parameters, actionId);
    } catch (e) {
      VableLogger.error('[VableFlutter] $intentId failed: $e');
      result = 'Failed: $e';
    }
    await Vable.sendToolResult(
      toolName: intentId,
      toolId: toolId,
      result: _control.finish(actionId, result),
    );
  }

  Future<String> _resultOf(String intentId, Map<String, dynamic> parameters, String actionId) async {
    final scanner = ScreenScannerManager();
    final elementId = parameters['id']?.toString();
    switch (intentId) {
      case 'clickElement':
        if (elementId == null) return 'Failed: no element was given';
        return scanner.clickForAgent(elementId, actionId: actionId);
      case 'inputText':
        final text = parameters['text']?.toString();
        if (elementId == null || text == null) return 'Failed: no field or text was given';
        return scanner.inputForAgent(elementId, text, actionId: actionId);
      case 'goBack':
        return scanner.goBackForAgent(actionId: actionId);
      case 'adjustSlider':
        if (elementId == null) return 'Failed: no slider was given';
        return scanner.adjustForAgent(
          elementId,
          up: parameters['direction']?.toString() != 'down',
          steps: num.tryParse('${parameters['steps']}')?.toInt() ?? 1,
          target: num.tryParse('${parameters['target']}'),
          actionId: actionId,
        );
      case 'scrollScreen':
        return scanner.scrollForAgent(
          down: parameters['direction']?.toString() != 'up',
          actionId: actionId,
        );
      case 'pointAt':
        if (elementId == null) return 'Failed: no element was given';
        return scanner.pointAtForAgent(elementId, actionId: actionId);
      default:
        final waited = await _control.beforeAct(VableAction(
          id: actionId,
          kind: VableActionKind.intent,
          tool: intentId,
          args: parameters,
        ));
        return waited ?? await Vable.runIntentForAgent(intentId, parameters);
    }
  }

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>('getPlatformVersion');
    return version;
  }

  @override
  Future<bool> initialize(
    String publicKey, {
    String? environment,
    bool debugLogging = false,
    String? accessToken,
  }) async {
    try {
      final args = <String, dynamic>{'publicKey': publicKey, 'debugLogging': debugLogging};
      if (environment != null) args['environment'] = environment;
      if (accessToken != null) args['accessToken'] = accessToken;
      final result = await methodChannel.invokeMethod<bool>('initialize', args);
      return result ?? false;
    } on PlatformException catch (e) {
      throw Exception('Failed to initialize Vable: ${e.message}');
    }
  }

  @override
  Future<void> setAccessToken(String? accessToken) async {
    await methodChannel.invokeMethod<bool>('setAccessToken', {'accessToken': accessToken});
  }

  @override
  Future<void> setMicrophoneMuted(bool muted) async {
    await methodChannel.invokeMethod<bool>('setMicrophoneMuted', {'muted': muted});
  }

  @override
  Future<void> setCallPillPosition(String position) async {
    await methodChannel.invokeMethod<bool>('setCallPillPosition', {'position': position});
  }

  @override
  Future<void> setCallStyle(String style) async {
    await methodChannel.invokeMethod<bool>('setCallStyle', {'style': style});
  }

  @override
  Future<void> setGlowColor(int argb) async {
    await methodChannel.invokeMethod<bool>('setGlowColor', {'color': argb});
  }

  @override
  Future<void> setEndButtonVisible(bool visible) async {
    await methodChannel.invokeMethod<bool>('setEndButtonVisible', {'visible': visible});
  }

  @override
  Future<bool> startVoiceChat() async {
    try {
      final result = await methodChannel.invokeMethod<bool>('startVoiceChat');
      return result ?? false;
    } on PlatformException catch (e) {
      if (e.code == 'NOT_INITIALIZED') {
        throw Exception('Vable SDK not initialized. Call initialize() first.');
      }
      throw Exception('Failed to start voice chat: ${e.message}');
    }
  }

  @override
  Future<bool> endVoiceChat() async {
    try {
      final result = await methodChannel.invokeMethod<bool>('endVoiceChat');
      return result ?? false;
    } on PlatformException catch (e) {
      if (e.code == 'NOT_INITIALIZED') {
        throw Exception('Vable SDK not initialized. Call initialize() first.');
      }
      throw Exception('Failed to end voice chat: ${e.message}');
    }
  }

  @override
  Future<bool> isVoiceChatActive() async {
    try {
      final result = await methodChannel.invokeMethod<bool>('isVoiceChatActive');
      return result ?? false;
    } on PlatformException catch (e) {
      if (e.code == 'NOT_INITIALIZED') {
        throw Exception('Vable SDK not initialized. Call initialize() first.');
      }
      throw Exception('Failed to check voice chat status: ${e.message}');
    }
  }

  @override
  Future<bool> updateIntents(Map<String, dynamic> contextUpdate) async {
    try {
      final result = await methodChannel.invokeMethod<bool>('updateIntents', {
        'contextUpdate': contextUpdate,
      });
      return result ?? false;
    } on PlatformException catch (e) {
      if (e.code == 'NOT_INITIALIZED') {
        throw Exception('Vable SDK not initialized. Call initialize() first.');
      }
      throw Exception('Failed to update intents: ${e.message}');
    }
  }

  @override
  Future<void> openChat() async {
    try {
      await methodChannel.invokeMethod<bool>('openChat');
    } on PlatformException catch (e) {
      if (e.code == 'NOT_INITIALIZED') {
        throw Exception('Vable SDK not initialized. Call initialize() first.');
      }
      throw Exception('Failed to open the chat: ${e.message}');
    }
  }

  @override
  Future<void> closeChat() async {
    await methodChannel.invokeMethod<bool>('closeChat');
  }

  @override
  Future<bool> isChatOpen() async {
    return await methodChannel.invokeMethod<bool>('isChatOpen') ?? false;
  }

  @override
  Future<void> sendChatMessage(String text) async {
    try {
      await methodChannel.invokeMethod<bool>('sendChatMessage', {'text': text});
    } on PlatformException catch (e) {
      throw Exception('Failed to send the message: ${e.message}');
    }
  }

  @override
  Future<List<dynamic>> getChatMessages() async {
    return await methodChannel.invokeMethod<List<dynamic>>('getChatMessages') ?? const [];
  }

  @override
  Future<void> startNewChat() async {
    await methodChannel.invokeMethod<bool>('startNewChat');
  }

  @override
  Future<void> setChatButtonVisible(bool visible) async {
    await methodChannel.invokeMethod<bool>('setChatButtonVisible', {'visible': visible});
  }

  @override
  Future<Map<dynamic, dynamic>?> getScreenFrames() {
    return methodChannel.invokeMethod<Map<dynamic, dynamic>>('getScreenFrames');
  }

  @override
  Future<bool> sendToolResult(String toolName, String? toolId, String result) async {
    try {
      final res = await methodChannel.invokeMethod<bool>('sendToolResult', {
        'toolName': toolName,
        'toolId': toolId,
        'result': result,
      });
      return res ?? false;
    } on PlatformException catch (e) {
      if (e.code == 'NOT_INITIALIZED') {
        throw Exception('Vable SDK not initialized. Call initialize() first.');
      }
      throw Exception('Failed to send tool result: ${e.message}');
    }
  }
}

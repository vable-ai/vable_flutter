import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'vable_flutter.dart';
import 'vable_flutter_platform_interface.dart';
import 'src/vable_logger.dart';

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
          Vable.handleNavigationEvent(url);
        } else {
          VableLogger.error('[VableFlutter] Warning: onNavigate called without url argument');
        }
      case 'onVoiceChatEnded':
        Vable.handleVoiceChatEnded();
      case 'onIntent':
        final intentId = call.arguments['id'] as String?;
        final parameters = (call.arguments['parameters'] as Map?)
            ?.cast<String, dynamic>() ?? {};
        VableLogger.debug('[VableFlutter] onIntent received: id=$intentId, parameters=$parameters');
        if (intentId == 'clickElement') {
          final elementId = parameters['id']?.toString();
          if (elementId != null) {
            try {
              final result = await ScreenScannerManager().clickForAgent(elementId);
              Vable.sendToolResult(toolName: "clickElement", result: result);
            } catch (e) {
              VableLogger.error('[VableFlutter] clickElement failed: $e');
              Vable.sendToolResult(toolName: "clickElement", result: "Failed: $e");
            }
          } else {
            VableLogger.error('[VableFlutter] clickElement intent missing "id" parameter');
            Vable.sendToolResult(toolName: "clickElement", result: "Failed: no element was given");
          }
        } else if (intentId == 'inputText') {
          final elementId = parameters['id']?.toString();
          final text = parameters['text']?.toString();
          if (elementId != null && text != null) {
            try {
              final result = await ScreenScannerManager().inputForAgent(elementId, text);
              Vable.sendToolResult(toolName: "inputText", result: result);
            } catch (e) {
              VableLogger.error('[VableFlutter] inputText failed: $e');
              Vable.sendToolResult(toolName: "inputText", result: "Failed: $e");
            }
          } else {
            VableLogger.error('[VableFlutter] inputText intent missing "id" or "text" parameter');
            Vable.sendToolResult(toolName: "inputText", result: "Failed: no field or text was given");
          }
        } else if (intentId == 'goBack') {
          final result = await ScreenScannerManager().goBackForAgent();
          Vable.sendToolResult(toolName: "goBack", result: result);
        } else if (intentId == 'adjustSlider') {
          final elementId = parameters['id']?.toString();
          if (elementId == null) {
            Vable.sendToolResult(toolName: "adjustSlider", result: "Failed: no slider was given");
          } else {
            final result = await ScreenScannerManager().adjustForAgent(
              elementId,
              up: parameters['direction']?.toString() != 'down',
              steps: num.tryParse('${parameters['steps']}')?.toInt() ?? 1,
              target: num.tryParse('${parameters['target']}'),
            );
            Vable.sendToolResult(toolName: "adjustSlider", result: result);
          }
        } else if (intentId == 'scrollScreen') {
          final result = await ScreenScannerManager().scrollForAgent(
            down: parameters['direction']?.toString() != 'up',
          );
          Vable.sendToolResult(toolName: "scrollScreen", result: result);
        } else if (intentId != null) {
          await Vable.handleIntentEvent(intentId, parameters);
        }
      default:
        VableLogger.error('[VableFlutter] Unknown method call: ${call.method}');
    }
  }

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>('getPlatformVersion');
    return version;
  }

  @override
  Future<bool> initialize(String publicKey, {String? environment, bool debugLogging = false}) async {
    try {
      final args = <String, dynamic>{'publicKey': publicKey, 'debugLogging': debugLogging};
      if (environment != null) args['environment'] = environment;
      final result = await methodChannel.invokeMethod<bool>('initialize', args);
      return result ?? false;
    } on PlatformException catch (e) {
      throw Exception('Failed to initialize Vable: ${e.message}');
    }
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

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

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
          Vable.handleNavigationEvent(url);
        } else {
          debugPrint('[VableFlutter] Warning: onNavigate called without url argument');
        }
      case 'onIntent':
        final intentId = call.arguments['id'] as String?;
        final parameters = (call.arguments['parameters'] as Map?)
            ?.cast<String, dynamic>() ?? {};
        debugPrint('[VableFlutter] onIntent received: id=$intentId, parameters=$parameters');
        if (intentId == 'clickElement') {
          final elementId = parameters['id']?.toString();
          if (elementId != null) {
            try {
              Vable.triggerElement(elementId);
              await Future.delayed(Duration(seconds: 1));
              Vable.sendToolResult(toolName: "clickElement", result: "Element Triggered");
            } catch (e) {
              debugPrint('[VableFlutter] triggerElement failed: $e');
            }
          } else {
            debugPrint('[VableFlutter] clickElement intent missing "id" parameter');
          }
        } else if (intentId == 'inputText') {
          final elementId = parameters['id']?.toString();
          final text = parameters['text']?.toString();
          if (elementId != null && text != null) {
            try {
              await Vable.inputTextElement(elementId, text);
              await Future.delayed(Duration(milliseconds: 500));
              Vable.sendToolResult(toolName: "inputText", result: "Text Entered");
            } catch (e) {
              debugPrint('[VableFlutter] inputTextElement failed: $e');
              Vable.sendToolResult(toolName: "inputText", result: "Failed: $e");
            }
          } else {
            debugPrint('[VableFlutter] inputText intent missing "id" or "text" parameter');
          }
        }
      default:
        debugPrint('[VableFlutter] Unknown method call: ${call.method}');
    }
  }

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>('getPlatformVersion');
    return version;
  }

  @override
  Future<bool> initialize(String publicKey, {String? environment}) async {
    try {
      final args = <String, dynamic>{'publicKey': publicKey};
      if (environment != null) args['environment'] = environment;
      final result = await methodChannel.invokeMethod<bool>('initialize', args);
      return result ?? false;
    } on PlatformException catch (e) {
      throw Exception('Failed to initialize Vable: ${e.message}');
    }
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

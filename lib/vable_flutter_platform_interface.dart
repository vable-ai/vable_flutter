import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'vable_flutter_method_channel.dart';

abstract class VableFlutterPlatform extends PlatformInterface {
  /// Constructs a VableFlutterPlatform.
  VableFlutterPlatform() : super(token: _token);

  static final Object _token = Object();

  static VableFlutterPlatform _instance = MethodChannelVableFlutter();

  /// The default instance of [VableFlutterPlatform] to use.
  ///
  /// Defaults to [MethodChannelVableFlutter].
  static VableFlutterPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [VableFlutterPlatform] when
  /// they register themselves.
  static set instance(VableFlutterPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }

  /// Initialize the Vable SDK with a public key.
  ///
  /// This must be called before any other Vable methods.
  /// [publicKey] The public key for authentication.
  /// Returns true if initialization was successful.
  Future<bool> initialize(String publicKey) {
    throw UnimplementedError('initialize() has not been implemented.');
  }

  /// Start a voice chat session.
  ///
  /// This will display the voice chat UI and initialize WebRTC and NATS connections.
  /// Returns true if voice chat started successfully.
  /// Throws an error if Vable has not been initialized.
  Future<bool> startVoiceChat() {
    throw UnimplementedError('startVoiceChat() has not been implemented.');
  }

  /// End the current voice chat session.
  ///
  /// This will close all connections and remove the overlay.
  /// Returns true if voice chat ended successfully.
  Future<bool> endVoiceChat() {
    throw UnimplementedError('endVoiceChat() has not been implemented.');
  }

  /// Check if a voice chat session is currently active.
  ///
  /// Returns true if voice chat is active, false otherwise.
  Future<bool> isVoiceChatActive() {
    throw UnimplementedError('isVoiceChatActive() has not been implemented.');
  }

  /// Update application context with intents, routes, and related information.
  ///
  /// This provides the AI agent with navigation and intent context.
  /// [contextUpdate] A map containing the context update data
  /// Returns true if the update was successful.
  Future<bool> updateIntents(Map<String, dynamic> contextUpdate) {
    throw UnimplementedError('updateIntents() has not been implemented.');
  }

  /// Send a tool result back to the AI agent.
  ///
  /// [toolName] The name of the tool that was invoked.
  /// [toolId] Optional tool use ID from the original toolUse request.
  /// [result] The result content to return to the AI.
  /// Returns true if the result was sent successfully.
  Future<bool> sendToolResult(String toolName, String? toolId, String result) {
    throw UnimplementedError('sendToolResult() has not been implemented.');
  }
}

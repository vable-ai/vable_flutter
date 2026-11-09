import 'dart:async';

import 'package:flutter/material.dart';
import 'package:vable_flutter/src/models/ui_element.dart';
import 'vable_flutter_platform_interface.dart';
import 'src/agent_control.dart';
import 'src/screen_frames.dart';
import 'src/screen_scanner_manager.dart';
import 'src/models/context_models.dart';
import 'src/models/agent_models.dart';
import 'src/models/chat_models.dart';
import 'src/vable_logger.dart';

// Export screen scanner for advanced use cases
export 'src/screen_scanner_manager.dart';
export 'src/screen_frames.dart'
    show VableScreenFramesConfig, VableFrameReason, VableScreenFrameHeader, VableScreenFrames;
export 'src/vable_navigator_observer.dart';
export 'src/vable_no_op.dart';
export 'src/models/ui_element.dart';
export 'src/models/context_models.dart';
export 'src/models/agent_models.dart';
export 'src/models/chat_models.dart';
export 'src/route_extractor.dart';
export 'src/vable_logger.dart';

/// Where the call pill sits on the screen
enum VableCallPillPosition { top, bottom }

/// How a call shows on screen
enum VableCallStyle {
  /// A soft glow round the edges of the screen, with no text, and one small
  /// button on the edge to end the call. The glow never takes a touch. The
  /// user can also end the call by saying goodbye.
  glow,

  /// A small pill with the call's status and a button to hang up
  pill,

  /// Nothing on screen: no glow, pill or buttons. Your app draws the call from
  /// [Vable.events] and ends it with [Vable.endVoiceChat]. The agent also gets
  /// a `pointAt` tool, for showing the user a control, and the user's touches
  /// pause it unless you turn [Vable.pauseOnUserTouch] off.
  none,
}

/// Supported routing libraries for AI-driven navigation
enum VableRoutingLibrary {
  /// Default Flutter Navigator (Navigator.pushNamed)
  native,

  /// GoRouter package (router.go or router.push)
  goRouter,

  /// AutoRoute package (router.navigate or router.navigateNamed)
  autoRoute,
}

/// Callback type for handling navigation events from the AI agent
typedef VableNavigationCallback = void Function(String url);

class Vable {
  static final ScreenScannerManager _screenScannerManager =
      ScreenScannerManager();

  /// Current navigation context (updated by NavigatorObserver or startVoiceChat)
  static BuildContext? _navigationContext;

  /// Routing library to use for navigation
  static VableRoutingLibrary _routingLibrary = VableRoutingLibrary.native;

  /// Router instance (GoRouter, StackRouter, etc.)
  static dynamic _routerInstance;

  /// Custom navigation callback. If set, this will be called instead of library-specific navigation.
  static VableNavigationCallback? _navigationCallback;

  /// Called when a session ends for any reason, including the user hanging up
  /// on the voice chat overlay or the agent ending the call.
  static VoidCallback? onVoiceChatEnded;

  /// Called when a call has connected, including one the user started from
  /// the chat's mic button.
  static VoidCallback? onVoiceChatStarted;

  /// Called when the chat opens, including when the user switches a call to it.
  static VoidCallback? onChatOpened;

  /// Called when the chat closes, by the user, your app, or a switch to a call.
  static VoidCallback? onChatClosed;

  /// Called when a chat turn fails, with `message_failed`, `tokens_exhausted`
  /// or `connection_failed`. The chat shows the failure itself.
  static ValueChanged<String>? onChatError;

  // MARK: Your own call UI

  static VableAgentControl get _control => VableAgentControl.instance;

  /// What happens in calls and the chat, for apps that draw their own UI with
  /// [VableCallStyle.none]: the agent's state, its reply as it arrives, the
  /// mic level, and each action it takes on the screen.
  ///
  /// ```dart
  /// Vable.events.listen((event) {
  ///   switch (event) {
  ///     case VableAgentStateChanged(:final state): orb.state = state;
  ///     case VableInputLevel(:final level): orb.level = level;
  ///     case VableActionStarted(:final action): highlight(action.bounds);
  ///     default:
  ///   }
  /// });
  /// ```
  static Stream<VableEvent> get events => _control.events;

  /// What the agent is doing now. [events] says when it changes.
  static VableAgentState get agentState => _control.state;

  /// Runs before each thing the agent does on the screen, once its target is
  /// found and scrolled into view: taps, typing, scrolling, going back,
  /// sliders, navigation and your own intents. The agent waits until it
  /// returns, so you can highlight [VableAction.bounds] first. Return false to
  /// skip it, and the agent is told the user declined. Pass null to remove it.
  ///
  /// ```dart
  /// Vable.setActionGate((action) async {
  ///   showHighlight(action.bounds);
  ///   await Future.delayed(const Duration(milliseconds: 400));
  ///   return true;
  /// });
  /// ```
  ///
  /// In the text chat, keep it under a minute: a chat reply is given up on 90
  /// seconds after the agent's last action.
  static void setActionGate(VableActionGate? gate) => _control.gate = gate;

  /// How the agent types into fields: all at once (the default), or one
  /// character at a time so the user sees it typed.
  ///
  /// ```dart
  /// Vable.setTyping(const VableTyping.perCharacter(Duration(milliseconds: 45)));
  /// ```
  static void setTyping(VableTyping typing) => _control.typing = typing;

  /// Holds the agent's next action until [resumeActions]. The call and the
  /// conversation carry on, so the user can still talk to it.
  static void pauseActions() => _control.pause();

  /// Lets the agent carry on with the action it was waiting to do.
  static void resumeActions() => _control.resume();

  /// Whether the agent's actions are paused, by you or by the user's touch.
  static bool get actionsPaused => _control.paused;

  /// Stops what the agent is doing: what it's saying, the reply it's working
  /// on, and its actions on the screen. The action it's waiting to do, and any
  /// that arrive in the next few seconds, are skipped, and it's told the user
  /// stopped the task. The call or chat carries on.
  static Future<void> cancelCurrentTask() async {
    _control.cancel();
    await VableFlutterPlatform.instance.cancelTurn();
  }

  /// Has the agent say [text] word for word, on a call or in the chat, as its
  /// own words: spoken on a call, and kept in the conversation. For short
  /// prompts your app decides on, such as a question before quick replies.
  ///
  /// ```dart
  /// await Vable.say('Which dates work for you?');
  /// ```
  static Future<void> say(String text) => VableFlutterPlatform.instance.say(text);

  /// Tells the agent the user changed something themselves, so it doesn't
  /// overwrite it. It hears at its next action. [elementId] is the control's
  /// `s_<n>` id; or give its [label].
  static void notifyUserInteraction({String? elementId, String? label}) {
    final scanner = _screenScannerManager;
    final name = label ??
        [...scanner.lastClickableElements, ...scanner.lastAdjustableElements]
            .where((e) => e.id == elementId)
            .map((e) => e.label)
            .followedBy(scanner.lastInputElements.where((e) => e.id == elementId).map((e) => e.label))
            .firstOrNull;
    _control.noteUserInteraction(name);
  }

  /// Whether the user touching the screen pauses the agent, during a call or
  /// while the chat is open. The agent's own taps don't count. The pause ends
  /// when you call [resumeActions], or when the user next talks or types to
  /// the agent; then what it was waiting to do is dropped, since the
  /// conversation has moved on. Either way, it hears what the user touched.
  /// On by default with [VableCallStyle.none], and off otherwise.
  static bool get pauseOnUserTouch => _control.pauseOnUserTouch;
  static set pauseOnUserTouch(bool value) => _control.pauseOnUserTouch = value;

  /// The context the screen is scanned from while a call or the chat is open.
  static BuildContext? _scanContext;
  static bool _callActive = false;
  static bool _chatOpen = false;
  static bool _framesStarted = false;
  static List<VableChatMessage> _chatMessages = const [];
  static final StreamController<List<VableChatMessage>> _chatController =
      StreamController<List<VableChatMessage>>.broadcast();

  /// All routes known to Vable, populated by [initialize] or [configureRouter].
  static List<VableRoute> _routes = [];

  /// All routes registered with Vable (from [initialize] or auto-extracted by [configureRouter]).
  static List<VableRoute> get routes => List.unmodifiable(_routes);

  static Future<String?> getPlatformVersion() {
    return VableFlutterPlatform.instance.getPlatformVersion();
  }

  /// Initialize the Vable SDK with your public key.
  ///
  /// This must be called before any other Vable methods.
  /// Typically called in your app's main() or initState().
  ///
  /// Optionally provide [routes] to send route information to the AI agent.
  ///
  /// Example:
  /// ```dart
  /// // Basic initialization
  /// await Vable.initialize('your-public-key');
  ///
  /// // With routes
  /// final routes = VableRouteExtractor.fromRoutesMap(myAppRoutes);
  /// await Vable.initialize('your-public-key', routes: routes);
  ///
  /// // With a signed-in user
  /// await Vable.initialize('your-public-key', accessToken: session.vableToken);
  /// ```
  ///
  /// [publicKey] Your Vable public key for authentication.
  /// [routes] Optional list of app routes to send to the AI agent.
  /// [accessToken] The signed-in user's token, so the agent knows who they
  /// are. Leave it out for guests. See [setAccessToken].
  /// Returns true if initialization was successful.
  /// Throws an Exception if initialization fails.
  static Future<bool> initialize(
    String publicKey, {
    List<VableRoute>? routes,
    String? environment,
    String? accessToken,
  }) async {
    final result = await VableFlutterPlatform.instance.initialize(
      publicKey,
      environment: environment,
      debugLogging: VableLogger.enabled,
      accessToken: accessToken,
    );

    VableLogger.info('Vable initialized with routes ${routes?.length}');
    // If routes are provided, store and send them to the AI agent
    if (result && routes != null && routes.isNotEmpty) {
      _routes = List.of(routes);
      _screenScannerManager.updateRoutes(_routes);
      try {
        await _sendRoutes();
      } catch (e) {
        // Log error but don't fail initialization
        VableLogger.error('Warning: Failed to send routes during initialization: $e');
      }
    }

    return result;
  }

  /// Start a voice chat session.
  ///
  /// This will display the Vable voice chat overlay and initialize
  /// WebRTC and NATS connections for voice communication.
  ///
  /// The [context] parameter is required for Flutter screen scanning and AI-driven navigation.
  /// Pass the current BuildContext to enable automatic screen context extraction.
  ///
  /// Note: On Android, RECORD_AUDIO permission is required.
  /// Ensure you request this permission before calling this method.
  ///
  /// Example:
  /// ```dart
  /// await Vable.startVoiceChat(context);
  /// ```
  ///
  /// Returns true if voice chat started successfully.
  /// Throws an Exception if Vable is not initialized or if starting fails.
  static Future<bool> startVoiceChat(BuildContext context) async {
    // Scan first, so the native side has the screen and tools before the
    // microphone opens. Otherwise the agent answers without them.
    _screenScannerManager.startScanning(
      context: context,
      scanInterval: const Duration(seconds: 3),
    );

    final bool result;
    try {
      result = await VableFlutterPlatform.instance.startVoiceChat();
    } catch (_) {
      _screenScannerManager.stopScanning();
      rethrow;
    }

    if (!result) {
      _syncScanning();
    } else {
      if (context.mounted) {
        // Store the Navigator's context for navigation (never unmounts)
        final navigatorContext = Navigator.maybeOf(context)?.context;
        _navigationContext = navigatorContext ?? context;
        _scanContext = _navigationContext;
      }
      _callActive = true;
      _syncScanning();
      await _startScreenFrames();
    }

    return result;
  }

  /// Scans the screen while a call or the chat is open, so the agent has it.
  static void _syncScanning() {
    _control.setSession(call: _callActive, chat: _chatOpen);
    final context = _scanContext;
    if (_callActive || _chatOpen) {
      if (!_screenScannerManager.isScanning && context != null && context.mounted) {
        _screenScannerManager.startScanning(context: context, scanInterval: const Duration(seconds: 3));
      }
    } else {
      _screenScannerManager.stopScanning();
    }
  }

  static void _rememberContext(BuildContext context) {
    final navigatorContext = Navigator.maybeOf(context)?.context;
    _scanContext = navigatorContext ?? context;
    _navigationContext = _scanContext;
  }

  /// Records what the user sees during the call, if the project turned it on.
  /// The room is created by now, and its response says whether it's on.
  static Future<void> _startScreenFrames() async {
    if (_framesStarted) return;
    _framesStarted = true;
    try {
      final config = await VableFlutterPlatform.instance.getScreenFrames();
      _screenScannerManager.frames.start(VableScreenFramesConfig.fromMap(config));
    } catch (e) {
      // A native side without frames
      VableLogger.debug('[VableFlutter] Screen frames unavailable: $e');
    }
  }

  /// End the current voice chat session.
  ///
  /// This will close all connections and remove the voice chat overlay.
  /// Also stops automatic screen scanning.
  ///
  /// Example:
  /// ```dart
  /// await Vable.endVoiceChat();
  /// ```
  ///
  /// Returns true if voice chat ended successfully.
  /// Throws an Exception if ending fails.
  static Future<bool> endVoiceChat() async {
    _endCall();
    return VableFlutterPlatform.instance.endVoiceChat();
  }

  /// Stops what only a call needs. Scanning carries on while the chat is open.
  static void _endCall() {
    _callActive = false;
    _framesStarted = false;
    _screenScannerManager.frames.stop();
    _syncScanning();
    if (!_chatOpen) _navigationContext = null;
  }

  /// Internal method called by the platform implementation when a session ends.
  static void handleVoiceChatEnded() {
    _endCall();
    onVoiceChatEnded?.call();
  }

  /// Internal: a call connected, perhaps one the user started from the chat.
  static Future<void> handleVoiceChatStarted() async {
    _callActive = true;
    _syncScanning();
    await _startScreenFrames();
    onVoiceChatStarted?.call();
  }

  // MARK: Text chat

  /// Open the text chat, for users who would rather type.
  ///
  /// It rises from the bottom of the screen and leaves your app above it
  /// usable. Voice and chat share one conversation: the chat carries on from
  /// a call and the other way round, and the chat has a mic button to switch
  /// to talking. A call that's running is ended.
  ///
  /// ```dart
  /// IconButton(
  ///   icon: const Icon(Icons.chat_bubble_outline),
  ///   onPressed: () => Vable.openChat(context),
  /// )
  /// ```
  static Future<void> openChat(BuildContext context) async {
    _rememberContext(context);
    _chatOpen = true;
    // Scan first, so the agent has the screen and tools by the first message
    _syncScanning();
    _setChatMessages(VableChatMessage.listFrom(await VableFlutterPlatform.instance.getChatMessages()));
    try {
      await VableFlutterPlatform.instance.openChat();
    } catch (_) {
      _chatOpen = false;
      _syncScanning();
      rethrow;
    }
  }

  /// Close the text chat. A reply still arriving is let finish first, and the
  /// conversation is kept for the next chat or call.
  static Future<void> closeChat() => VableFlutterPlatform.instance.closeChat();

  /// Whether the chat is on screen.
  static Future<bool> isChatOpen() => VableFlutterPlatform.instance.isChatOpen();

  /// Send a message as the user without the chat on screen, for apps that draw
  /// their own chat. The reply streams into [chatMessages].
  static Future<void> sendMessage(String text) {
    _control.userTurnStarted();
    return VableFlutterPlatform.instance.sendChatMessage(text);
  }

  /// The conversation's lines, each time they change: a new line, or a reply
  /// growing as it streams in.
  static Stream<List<VableChatMessage>> get chatMessages => _chatController.stream;

  /// The conversation's lines as last heard from the native SDK, oldest first.
  static List<VableChatMessage> get currentChatMessages => _chatMessages;

  /// Forget the conversation and start a new one. The chat stays open if it is.
  static Future<void> startNewChat() => VableFlutterPlatform.instance.startNewChat();

  /// Whether calls show a button to switch to the chat, beside the end button.
  /// On by default. Takes effect from the next call.
  static Future<void> setChatButtonVisible(bool visible) =>
      VableFlutterPlatform.instance.setChatButtonVisible(visible);

  static void _setChatMessages(List<VableChatMessage> messages) {
    _chatMessages = List.unmodifiable(messages);
    _chatController.add(_chatMessages);
  }

  /// Internal: the native chat's lines changed.
  static void handleChatUpdated(List<VableChatMessage> messages) {
    _setChatMessages(messages);
    _control.onChatMessages(messages);
  }

  /// Internal: a chat turn failed.
  static void handleChatError(String code) => onChatError?.call(code);

  /// Internal: the native side opened the chat, perhaps from a call's chat button.
  static void handleChatOpened() {
    _chatOpen = true;
    _syncScanning();
    onChatOpened?.call();
  }

  /// Internal: the chat closed.
  static void handleChatClosed() {
    _chatOpen = false;
    _syncScanning();
    if (!_callActive) _navigationContext = null;
    onChatClosed?.call();
  }

  /// Mute or unmute the microphone, during a session or ahead of one.
  ///
  /// The agent keeps talking while it's muted, it just can't hear the user.
  /// Set or clear the signed-in user's access token, for example after they
  /// sign in or out, or when your app refreshes the token.
  ///
  /// The token is a JWT your backend signs with your Vable project's signing
  /// key, with the user's id in `sub` and optionally `email`, `firstName` and
  /// `lastName`. It's sent when a call starts, so the agent knows who the user
  /// is and can act for them. A call that's already running keeps the token
  /// it started with; the new one is used from the next call. Pass null to
  /// make the next call a guest call.
  ///
  /// ```dart
  /// await Vable.setAccessToken(newToken);
  /// ```
  static Future<void> setAccessToken(String? accessToken) {
    return VableFlutterPlatform.instance.setAccessToken(accessToken);
  }

  static Future<void> setMicrophoneMuted(bool muted) {
    return VableFlutterPlatform.instance.setMicrophoneMuted(muted);
  }

  /// Put the call pill at the top or bottom of the screen, for apps with tabs
  /// or buttons it would cover. It's at the bottom unless you move it, and
  /// this takes effect from the next session.
  static Future<void> setCallPillPosition(VableCallPillPosition position) {
    return VableFlutterPlatform.instance.setCallPillPosition(position.name);
  }

  /// Show calls as a glow round the edges of the screen (the default), as the
  /// pill, or not at all with [VableCallStyle.none] for apps that draw their
  /// own. Takes effect from the next session.
  static Future<void> setCallStyle(VableCallStyle style) {
    _control.headless = style == VableCallStyle.none;
    return VableFlutterPlatform.instance.setCallStyle(style.name);
  }

  /// The glow's colour, usually your brand colour. It's shown in lighter and
  /// deeper tints of itself. Takes effect from the next session.
  static Future<void> setGlowColor(Color color) {
    return VableFlutterPlatform.instance.setGlowColor(color.toARGB32());
  }

  /// Whether the glow shows its small end button. It rests on the right edge
  /// and can be dragged out of the way. Hide it only if your app has its own
  /// way to end the call, through [endVoiceChat]. Takes effect from the next
  /// session.
  static Future<void> setEndButtonVisible(bool visible) {
    return VableFlutterPlatform.instance.setEndButtonVisible(visible);
  }

  /// Check if a voice chat session is currently active.
  ///
  /// Example:
  /// ```dart
  /// bool isActive = await Vable.isVoiceChatActive();
  /// if (isActive) {
  ///   print('Voice chat is active');
  /// }
  /// ```
  ///
  /// Returns true if voice chat is active, false otherwise.
  static Future<bool> isVoiceChatActive() {
    return VableFlutterPlatform.instance.isVoiceChatActive();
  }

  /// Update the screen scanning interval.
  ///
  /// [interval] The new interval between scans (default: 3 seconds).
  ///
  /// Example:
  /// ```dart
  /// Vable.updateScanInterval(Duration(seconds: 5));
  /// ```
  static void updateScanInterval(Duration interval) {
    _screenScannerManager.updateScanInterval(interval);
  }

  /// Check if screen scanning is currently active.
  static bool get isScreenScanningActive => _screenScannerManager.isScanning;

  /// All clickable elements found during the most recent screen scan.
  ///
  /// Each element's [ClickableElement.label] is the concatenation of every text
  /// node inside that element's subtree, making it easy to identify what a
  /// button or card represents without traversing the tree yourself.
  ///
  /// Use [triggerElement] to programmatically tap any of these.
  static List<ClickableElement> get clickableElements =>
      _screenScannerManager.lastClickableElements;

  /// All input elements found during the most recent screen scan.
  ///
  /// Use [inputTextElement] to programmatically type into any of these.
  static List<InputElement> get inputElements =>
      _screenScannerManager.lastInputElements;

  /// Simulate a tap on the clickable element identified by [id].
  ///
  /// [id] must match a [ClickableElement.id] from [clickableElements].
  /// Dispatches synthetic pointer-down and pointer-up events at the element's
  /// centre so the widget's gesture recogniser fires normally.
  ///
  /// Throws [ArgumentError] if no element with that id was found in the last scan.
  static void triggerElement(String id) {
    _screenScannerManager.triggerElement(id);
  }

  /// Type [text] into the input element identified by [id].
  ///
  /// [id] must match an [InputElement.id] from [inputElements].
  /// Focuses the field and sets its value via [SystemChannels.textInput],
  /// so it works with any TextField-based widget including ReactiveTextField.
  ///
  /// Throws [ArgumentError] if no input element with that id was found in the last scan.
  static Future<void> inputTextElement(String id, String text) {
    return _screenScannerManager.inputTextElement(id, text);
  }

  /// Update application context with intents, routes, and related information.
  ///
  /// This provides the AI agent with navigation and intent context.
  /// Can be called at any time after initialization to update the context.
  ///
  /// Example:
  /// ```dart
  /// // Update with routes
  /// final routes = VableRouteExtractor.fromRoutesMap(myAppRoutes);
  /// await Vable.updateIntents(VableContextUpdate(routes: routes));
  ///
  /// // Update with intents and routes
  /// await Vable.updateIntents(VableContextUpdate(
  ///   routes: routes,
  ///   intents: [
  ///     VableIntent(name: 'checkout', description: 'Complete purchase'),
  ///   ],
  ///   intentStates: [
  ///     VableIntentState(
  ///       name: 'cart',
  ///       description: 'Items currently in the shopping cart',
  ///       value: cartItems,
  ///     ),
  ///   ],
  /// ));
  /// ```
  ///
  /// [contextUpdate] The context update containing intents, routes, and related data.
  /// Returns true if the update was successful.
  /// Throws an Exception if the update fails.
  /// Sends the routes the scanner manager holds, keeping the intents and state
  /// the app sent. Sending them through [updateIntents] would replace those.
  static Future<bool> _sendRoutes() {
    return VableFlutterPlatform.instance.updateIntents(
      _screenScannerManager.fullContext().toJson(),
    );
  }

  static Future<bool> updateIntents(VableContextUpdate contextUpdate) {
    _screenScannerManager.updateHostContext(contextUpdate);
    return VableFlutterPlatform.instance.updateIntents(
      _screenScannerManager.fullContext().toJson(),
    );
  }

  /// Adds one intent, or replaces the one with the same name. Use this from a
  /// screen's `initState`, and [unregisterIntent] from its `dispose`, for actions
  /// that only make sense on that screen.
  static Future<bool> registerIntent(VableIntent intent) {
    final host = _screenScannerManager.hostContext;
    return updateIntents(host.copyWith(
      intents: [...host.intents.where((i) => i.name != intent.name), intent],
    ));
  }

  /// Removes the intent called [name], so the agent stops offering it.
  static Future<bool> unregisterIntent(String name) {
    final host = _screenScannerManager.hostContext;
    return updateIntents(host.copyWith(
      intents: host.intents.where((i) => i.name != name).toList(),
    ));
  }

  /// Adds one piece of app state, or replaces the one with the same name.
  static Future<bool> updateIntentState(VableIntentState state) {
    final host = _screenScannerManager.hostContext;
    return updateIntents(host.copyWith(
      intentStates: [...host.intentStates.where((s) => s.name != state.name), state],
    ));
  }

  /// Runs the app's handler for an intent the agent called and tells the agent
  /// how it went. Without a result the agent would wait for one.
  ///
  /// [toolId] is the ID of the agent's tool call, sent back with the result.
  static Future<void> handleIntentEvent(
    String name,
    Map<String, dynamic> parameters, {
    String? toolId,
  }) async {
    await sendToolResult(
      toolName: name,
      toolId: toolId,
      result: await runIntentForAgent(name, parameters),
    );
  }

  /// Runs the app's handler for an intent the agent called, and returns what
  /// to tell the agent.
  static Future<String> runIntentForAgent(String name, Map<String, dynamic> parameters) async {
    final handler = _screenScannerManager.intentHandler(name);
    if (handler == null) {
      VableLogger.error('[VableFlutter] No handler for intent $name. Give it an onIntent.');
      return "Failed: this app can't do that yet";
    }

    try {
      return (await handler(parameters)) ?? 'Done.';
    } catch (e) {
      VableLogger.error('[VableFlutter] Intent $name failed: $e');
      return 'Failed: $e';
    }
  }

  /// Send a tool result back to the AI agent.
  ///
  /// Call this after handling a tool use request from the AI to return the result.
  ///
  /// Example:
  /// ```dart
  /// await Vable.sendToolResult(
  ///   toolName: 'get_balance',
  ///   toolId: 'tool_abc123',
  ///   result: '{"balance": 42.00}',
  /// );
  /// ```
  ///
  /// [toolName] The name of the tool that was invoked.
  /// [toolId] Optional tool use ID from the original toolUse request.
  /// [result] The result content to return to the AI.
  /// Returns true if the result was sent successfully.
  static Future<bool> sendToolResult({
    required String toolName,
    String? toolId,
    required String result,
  }) {
    return VableFlutterPlatform.instance.sendToolResult(toolName, toolId, result);
  }

  /// Configure the routing library for AI-driven navigation.
  ///
  /// Vable supports multiple routing libraries without requiring them as dependencies.
  /// Specify which library you're using and provide the router instance.
  ///
  /// **IMPORTANT**: Call this AFTER your router and DI container are initialized!
  ///
  /// Example with GoRouter:
  /// ```dart
  /// final router = GoRouter(routes: [...]);
  ///
  /// Vable.configureRouter(
  ///   library: VableRoutingLibrary.goRouter,
  ///   router: router,
  /// );
  /// ```
  ///
  /// Example with AutoRoute (auto-extracts routes by default):
  /// ```dart
  /// // After DI is configured
  /// final router = getIt<AppRouter>();
  ///
  /// Vable.configureRouter(
  ///   library: VableRoutingLibrary.autoRoute,
  ///   router: router,
  ///   // Routes are automatically extracted from router!
  /// );
  /// ```
  ///
  /// Disable auto-extraction:
  /// ```dart
  /// Vable.configureRouter(
  ///   library: VableRoutingLibrary.autoRoute,
  ///   router: router,
  ///   autoExtractRoutes: false, // Disable auto-extraction
  /// );
  /// ```
  ///
  /// **Better for AutoRoute - use callback for navigation**:
  /// ```dart
  /// Vable.setNavigationCallback((url) {
  ///   final router = getIt<AppRouter>();
  ///   switch (url) {
  ///     case '/account':
  ///       router.push(const AccountRoute());
  ///       break;
  ///   }
  /// });
  /// ```
  ///
  /// Example with native Flutter routing (default):
  /// ```dart
  /// // No configuration needed, just define routes in MaterialApp:
  /// MaterialApp(
  ///   routes: {
  ///     '/account': (context) => AccountPage(),
  ///   },
  /// )
  /// ```
  ///
  /// [library] The routing library you're using
  /// [router] The router instance from your app (e.g., GoRouter, StackRouter)
  /// [autoExtractRoutes] Automatically extract and send routes to AI (default: true)
  /// [excludeRoutes] Paths to leave out of the extracted routes, such as pages
  /// that need an item passed to them and show nothing when opened by path
  static void configureRouter({
    required VableRoutingLibrary library,
    dynamic router,
    bool autoExtractRoutes = true,
    List<String> excludeRoutes = const [],
  }) {
    try {
      _routingLibrary = library;
      _routerInstance = router;

      VableLogger.info('[VableFlutter] Router configured: ${library.name}');

      if (library != VableRoutingLibrary.native && router == null) {
        VableLogger.error('[VableFlutter] ⚠️ Warning: Router instance not provided for ${library.name}');
        VableLogger.error('[VableFlutter] Navigation will fail until router is set');
      }

      // Basic validation - try to access router without calling methods
      if (router != null) {
        VableLogger.debug('[VableFlutter] ✓ Router instance provided');

        // Auto-extract routes if enabled
        if (autoExtractRoutes) {
          _autoExtractAndSendRoutes(library, router, excludeRoutes);
        } else {
          VableLogger.debug('[VableFlutter] Route auto-extraction disabled');
        }
      }
    } catch (e) {
      VableLogger.error('[VableFlutter] ❌ Error configuring router: $e');
      VableLogger.error('[VableFlutter] This usually means the router is not initialized yet');
      VableLogger.error('[VableFlutter] Ensure your router/DI is set up before calling configureRouter()');

      // Reset to native to prevent crashes
      _routingLibrary = VableRoutingLibrary.native;
      _routerInstance = null;
    }
  }

  /// Automatically extract routes from router instance and send to AI
  static void _autoExtractAndSendRoutes(
    VableRoutingLibrary library,
    dynamic router,
    List<String> excludeRoutes,
  ) {
    try {
      VableLogger.debug('[VableFlutter] Attempting to auto-extract routes from ${library.name}...');

      List<VableRoute>? extractedRoutes;

      switch (library) {
        case VableRoutingLibrary.autoRoute:
          extractedRoutes = _extractAutoRouteRoutes(router);
          break;
        case VableRoutingLibrary.goRouter:
          extractedRoutes = _extractGoRouterRoutes(router);
          break;
        case VableRoutingLibrary.native:
          // Native routes should be provided manually
          VableLogger.debug('[VableFlutter] Native router - routes should be provided in initialize()');
          break;
      }

      extractedRoutes = extractedRoutes
          ?.where((route) => !excludeRoutes.contains(route.path))
          .toList();

      if (extractedRoutes != null && extractedRoutes.isNotEmpty) {
        VableLogger.info('[VableFlutter] ✓ Extracted ${extractedRoutes.length} routes');

        // Store globally, sync to scanner manager, and send to AI
        _routes = List.of(extractedRoutes);
        _screenScannerManager.updateRoutes(_routes);
        _sendRoutes().then((_) {
          VableLogger.info('[VableFlutter] ✓ Routes sent to AI agent');
        }).catchError((e) {
          VableLogger.error('[VableFlutter] ⚠️ Failed to send routes to AI: $e');
        });
      } else {
        VableLogger.debug('[VableFlutter] No routes extracted - you may need to provide them manually');
      }
    } catch (e) {
      VableLogger.error('[VableFlutter] ⚠️ Failed to auto-extract routes: $e');
      VableLogger.debug('[VableFlutter] You can provide routes manually in initialize()');
    }
  }

  /// Extract routes from AutoRoute router
  static List<VableRoute>? _extractAutoRouteRoutes(dynamic router) {
    try {
      // AutoRoute exposes routes through various methods
      // Try to access the routes list

      // Method 1: Try accessing routes property directly
      try {
        final routes = router.routes;
        if (routes != null) {
          return _parseAutoRouteConfig(routes);
        }
      } catch (e) {
        VableLogger.debug('[VableFlutter] routes property not accessible: ${e.toString().split('\n')[0]}');
      }

      // Method 2: Try accessing config
      try {
        final config = router.config;
        if (config != null && config.routes != null) {
          return _parseAutoRouteConfig(config.routes);
        }
      } catch (e) {
        VableLogger.debug('[VableFlutter] config.routes not accessible: ${e.toString().split('\n')[0]}');
      }

      // Method 3: Try matcher routes
      try {
        final matcher = router.matcher;
        if (matcher != null) {
          final routes = matcher.routes;
          if (routes != null) {
            return _parseAutoRouteConfig(routes);
          }
        }
      } catch (e) {
        VableLogger.debug('[VableFlutter] matcher.routes not accessible: ${e.toString().split('\n')[0]}');
      }

      VableLogger.debug('[VableFlutter] Could not extract routes from AutoRoute router');
      return null;
    } catch (e) {
      VableLogger.error('[VableFlutter] Error extracting AutoRoute routes: $e');
      return null;
    }
  }

  /// Parse AutoRoute config to extract route paths
  static List<VableRoute> _parseAutoRouteConfig(dynamic routes, {String parentPath = ''}) {
    final List<VableRoute> vableRoutes = [];

    try {
      if (routes is List || routes is Iterable) {
        for (final route in routes) {
          try {
            // Try to get path from route
            String? path;
            String? name;

            // Try different properties that might contain the path
            if (route.path != null) {
              path = route.path.toString();
            } else if (route.routeName != null) {
              path = route.routeName.toString();
            }

            // Try to get name
            if (route.name != null) {
              name = route.name.toString();
            } else if (route.title != null) {
              name = route.title.toString();
            }

            if (path != null && path.isNotEmpty) {
              // Build full path by combining parent path with current path
              String fullPath = _buildFullPath(parentPath, path);

              // Only add non-root parent routes (routes with actual pages, not just wrappers)
              // Skip if it's a root path '/' that has children (it's likely a wrapper)
              bool isWrapper = (fullPath == '/' || fullPath.isEmpty) && _hasChildren(route);

              if (!isWrapper) {
                vableRoutes.add(VableRoute(
                  path: fullPath,
                  name: name ?? _pathToName(fullPath),
                ));

                VableLogger.debug('[VableFlutter] Extracted route: $fullPath ${name != null ? "($name)" : ""}');
              }

              // Recursively extract child routes
              if (_hasChildren(route)) {
                try {
                  final children = route.children;
                  if (children != null) {
                    // A plain list since AutoRoute 8. Older versions wrap it
                    final childRoutes = _parseAutoRouteConfig(
                      children is Iterable ? children : children.routes,
                      parentPath: fullPath,
                    );
                    vableRoutes.addAll(childRoutes);
                  }
                } catch (e) {
                  VableLogger.debug('[VableFlutter] Could not extract children: ${e.toString().split('\n')[0]}');
                }
              }
            }
          } catch (e) {
            // Skip this route if we can't parse it
            VableLogger.debug('[VableFlutter] Could not parse route: ${e.toString().split('\n')[0]}');
          }
        }
      }
    } catch (e) {
      VableLogger.error('[VableFlutter] Error parsing route config: $e');
    }

    return vableRoutes;
  }

  /// Build full path from parent and child paths
  static String _buildFullPath(String parentPath, String childPath) {
    // Clean up paths
    parentPath = parentPath.trim();
    childPath = childPath.trim();

    // If parent is empty or root, just use child path
    if (parentPath.isEmpty || parentPath == '/') {
      // Ensure child path starts with /
      if (!childPath.startsWith('/')) {
        return '/$childPath';
      }
      return childPath;
    }

    // Remove trailing slash from parent
    if (parentPath.endsWith('/')) {
      parentPath = parentPath.substring(0, parentPath.length - 1);
    }

    // Remove leading slash from child if present
    if (childPath.startsWith('/')) {
      childPath = childPath.substring(1);
    }

    // Combine
    return '$parentPath/$childPath';
  }

  /// Check if a route has children
  static bool _hasChildren(dynamic route) {
    try {
      // print(route.children is List);
      // print((route.children as List).isNotEmpty);
      // return route.children != null && route.children is List && (route.children as List).isNotEmpty;
      return route.children != null;
    } catch (e) {
      return false;
    }
  }

  /// Extract routes from GoRouter
  static List<VableRoute>? _extractGoRouterRoutes(dynamic router) {
    try {
      // GoRouter has a configuration property with routes
      final config = router.configuration;
      if (config != null && config.routes != null) {
        return _parseGoRouterConfig(config.routes);
      }

      VableLogger.debug('[VableFlutter] Could not extract routes from GoRouter');
      return null;
    } catch (e) {
      VableLogger.error('[VableFlutter] Error extracting GoRouter routes: $e');
      return null;
    }
  }

  /// Parse GoRouter config to extract route paths
  static List<VableRoute> _parseGoRouterConfig(dynamic routes) {
    final List<VableRoute> vableRoutes = [];

    try {
      if (routes is List) {
        for (final route in routes) {
          try {
            String? path = route.path?.toString();
            String? name = route.name?.toString();

            if (path != null) {
              vableRoutes.add(VableRoute(
                path: path,
                name: name ?? _pathToName(path),
              ));

              VableLogger.debug('[VableFlutter] Extracted GoRouter route: $path ${name != null ? "($name)" : ""}');

              // Recursively extract child routes
              if (route.routes != null && route.routes is List) {
                final childRoutes = _parseGoRouterConfig(route.routes);
                vableRoutes.addAll(childRoutes);
              }
            }
          } catch (e) {
            VableLogger.debug('[VableFlutter] Could not parse GoRouter route: ${e.toString().split('\n')[0]}');
          }
        }
      }
    } catch (e) {
      VableLogger.error('[VableFlutter] Error parsing GoRouter config: $e');
    }

    return vableRoutes;
  }

  /// Convert path to human-readable name
  static String _pathToName(String path) {
    // Remove leading slash
    String name = path.startsWith('/') ? path.substring(1) : path;

    // Replace hyphens and underscores with spaces
    name = name.replaceAll('-', ' ').replaceAll('_', ' ');

    // Remove route parameters
    name = name.replaceAll(RegExp(r':\w+'), '');

    // Capitalize first letter of each word
    name = name.split(' ').map((word) {
      if (word.isEmpty) return word;
      return word[0].toUpperCase() + word.substring(1);
    }).join(' ');

    return name.trim();
  }

  /// Set a custom navigation callback to handle navigation events from the AI agent.
  ///
  /// This overrides the routing library configuration. Use this for complete custom control.
  ///
  /// Example with custom callback:
  /// ```dart
  /// Vable.setNavigationCallback((url) {
  ///   // Custom navigation logic
  ///   myCustomRouter.navigateTo(url);
  /// });
  /// ```
  ///
  /// [callback] The callback to handle navigation events.
  static void setNavigationCallback(VableNavigationCallback? callback) {
    _navigationCallback = callback;
    VableLogger.info('[VableFlutter] Navigation callback ${callback != null ? "registered" : "unregistered"}');
  }

  /// Update the navigation context. Typically called by [VableNavigatorObserver]
  /// when routes change to ensure navigation always uses the current context.
  ///
  /// This is automatically handled if you add [VableNavigatorObserver] to your
  /// MaterialApp's navigatorObservers list.
  ///
  /// Example:
  /// ```dart
  /// MaterialApp(
  ///   navigatorObservers: [VableNavigatorObserver()],
  ///   // ...
  /// )
  /// ```
  static void updateNavigationContext(BuildContext context) {
    _navigationContext = context;
    VableLogger.debug('[VableFlutter] Navigation context updated');
  }

  /// Internal method to handle navigation events from the native side.
  /// Called by the platform implementation when the AI agent requests navigation.
  /// [toolId] is the ID of the agent's tool call, sent back with the result.
  static Future<void> handleNavigationEvent(String url, {String? toolId}) async {
    await sendToolResult(toolName: "navigate", toolId: toolId, result: await navigateForAgent(url));
  }

  /// Opens [url] for the agent, and returns what to tell it.
  static Future<String> navigateForAgent(String url) async {
    VableLogger.info('[VableFlutter] Navigation event received: $url');

    final before = await _screenScannerManager.captureScreen();

    // Priority 1: Custom callback (complete override)
    if (_navigationCallback != null) {
      VableLogger.debug('[VableFlutter] Using custom navigation callback');
      var navigated = false;
      try {
        _navigationCallback!(url);
        navigated = true;
        VableLogger.info('[VableFlutter] ✓ Successfully navigated to $url');
      } catch (e) {
        VableLogger.error('[VableFlutter] ❌ Error in custom navigation callback: $e');
      }
      return _navigationResult(url, navigated, before);
    }

    var navigated = false;
    // Priority 2: Configured routing library
    switch (_routingLibrary) {
      case VableRoutingLibrary.goRouter:
        navigated = _navigateWithGoRouter(url);
        break;

      case VableRoutingLibrary.autoRoute:
        navigated = await _navigateWithAutoRoute(url);
        break;

      case VableRoutingLibrary.native:
        navigated = _navigateWithNativeRouter(url);
        break;
    }

    return _navigationResult(url, navigated, before);
  }

  static Future<String> _navigationResult(
    String url,
    bool navigated,
    VableScreenSnapshot? before,
  ) async {
    if (!navigated) return "Failed: couldn't open $url";
    final change = await _screenScannerManager.describeChangeSince(before);
    if (await _screenScannerManager.leaveEmptyScreen()) {
      return "Failed: $url came up empty, so it was closed. It needs something "
          "picked first. Open it yourself by tapping what leads there, such as "
          "a tab, card or button, rather than asking the user to.";
    }
    return "Went to $url. $change".trim();
  }

  /// Navigate using GoRouter (go_router package)
  static bool _navigateWithGoRouter(String url) {
    VableLogger.debug('[VableFlutter] Using GoRouter for navigation');

    if (_routerInstance == null) {
      VableLogger.error('[VableFlutter] ❌ GoRouter instance not configured');
      VableLogger.error('[VableFlutter] Call: Vable.configureRouter(library: VableRoutingLibrary.goRouter, router: yourRouter)');
      return false;
    }

    try {
      // Try using go() method (preferred for GoRouter)
      _routerInstance.go(url);
      VableLogger.info('[VableFlutter] ✓ Successfully navigated to $url using GoRouter.go()');
      return true;
    } catch (e) {
      // Fallback to push() method
      try {
        _routerInstance.push(url);
        VableLogger.info('[VableFlutter] ✓ Successfully navigated to $url using GoRouter.push()');
        return true;
      } catch (e2) {
        VableLogger.error('[VableFlutter] ❌ Error navigating with GoRouter: $e');
        VableLogger.error('[VableFlutter] Ensure your GoRouter has route "$url" defined');
      }

      return false;
    }
  }

  /// Navigate using AutoRoute (auto_route package)
  static Future<bool> _navigateWithAutoRoute(String url) async {
    VableLogger.debug('[VableFlutter] Using AutoRoute for navigation');

    if (_routerInstance == null) {
      VableLogger.error('[VableFlutter] ❌ AutoRoute instance not configured');
      VableLogger.debug('[VableFlutter] ');
      VableLogger.error('[VableFlutter] AutoRoute requires special setup. Use callback instead:');
      VableLogger.debug('[VableFlutter] ');
      VableLogger.error('[VableFlutter] // After DI is configured');
      VableLogger.error('[VableFlutter] Vable.setNavigationCallback((url) {');
      VableLogger.error('[VableFlutter]   final router = getIt<AppRouter>(); // or your DI method');
      VableLogger.error('[VableFlutter]   switch (url) {');
      VableLogger.error('[VableFlutter]     case "/account":');
      VableLogger.error('[VableFlutter]       router.push(const AccountRoute());');
      VableLogger.error('[VableFlutter]       break;');
      VableLogger.debug('[VableFlutter]   }');
      VableLogger.error('[VableFlutter] });');
      return false;
    }

    if (_navigationContext == null || !_navigationContext!.mounted) {
      VableLogger.error('[VableFlutter] ❌ Navigation context unavailable for AutoRoute');
      VableLogger.error('[VableFlutter] Ensure startVoiceChat() was called with a valid context');
      return false;
    }

    // Wrap all AutoRoute navigation attempts in a big try-catch to prevent freezing
    try {
      bool navigated = false;

      // Try method 1: navigatePath with onFailure callback
      if (!navigated) {
        try {
          bool failed = false;
          await _routerInstance.navigatePath(
            url,
            onFailure: (failure) {
              VableLogger.error('[VableFlutter] navigatePath() failed: $failure');
              failed = true;
            },
          );
          if (!failed) {
            VableLogger.info('[VableFlutter] ✓ Successfully navigated to $url using AutoRoute.navigatePath().');
            navigated = true;
          }
        } catch (e) {
          // Method not available or failed, continue
          VableLogger.debug('[VableFlutter] navigatePath() not available: ${e.toString().split('\n')[0]}');
        }
      }

      // Try method 2: pushPath
      if (!navigated) {
        try {
          final result = _routerInstance.pushPath(url);
          if (result != null) {
            VableLogger.info('[VableFlutter] ✓ Successfully navigated to $url using AutoRoute.pushPath()');
            navigated = true;
          }
        } catch (e) {
          VableLogger.debug('[VableFlutter] pushPath() not available: ${e.toString().split('\n')[0]}');
        }
      }

      // Try method 3: the names older versions of AutoRoute used
      if (!navigated) {
        try {
          final result = _routerInstance.pushNamed(url);
          if (result != null) {
            VableLogger.info('[VableFlutter] ✓ Successfully navigated to $url using AutoRoute.pushNamed()');
            navigated = true;
          }
        } catch (e) {
          VableLogger.debug('[VableFlutter] pushNamed() not available: ${e.toString().split('\n')[0]}');
        }
      }

      // If all methods fail, provide helpful error
      if (!navigated) {
        VableLogger.error('[VableFlutter] ❌ Could not navigate with AutoRoute');
        VableLogger.debug('[VableFlutter] ');
        VableLogger.error('[VableFlutter] AutoRoute uses code generation and doesn\'t support string-based navigation well.');
        VableLogger.error('[VableFlutter] Use a custom callback instead:');
        VableLogger.debug('[VableFlutter] ');
        VableLogger.error('[VableFlutter] Vable.setNavigationCallback((url) {');
        VableLogger.error('[VableFlutter]   final router = getIt<AppRouter>();');
        VableLogger.error('[VableFlutter]   switch (url) {');
        VableLogger.error('[VableFlutter]     case "/account":');
        VableLogger.error('[VableFlutter]       router.push(const AccountRoute());');
        VableLogger.error('[VableFlutter]       break;');
        VableLogger.debug('[VableFlutter]   }');
        VableLogger.error('[VableFlutter] });');
      }
      return navigated;
    } catch (e, stackTrace) {
      VableLogger.error('[VableFlutter] ❌ Fatal error navigating with AutoRoute: $e');
      VableLogger.error('[VableFlutter] This might be a router initialization issue');
      VableLogger.error('[VableFlutter] Stack trace: ${stackTrace.toString().split('\n').take(3).join('\n')}');
      return false;
    }
  }

  /// Navigate using native Flutter Navigator
  static bool _navigateWithNativeRouter(String url) {
    VableLogger.debug('[VableFlutter] Using native Flutter Navigator');

    if (_navigationContext == null || !_navigationContext!.mounted) {
      VableLogger.error('[VableFlutter] ❌ Navigation context unavailable');
      VableLogger.error('[VableFlutter] Ensure startVoiceChat() was called with a valid context');
      return false;
    }

    try {
      Navigator.of(_navigationContext!).pushNamed(url);
      VableLogger.info('[VableFlutter] ✓ Successfully navigated to $url');
      return true;
    } catch (e) {
      VableLogger.error('[VableFlutter] ❌ Error navigating to $url: $e');
      VableLogger.debug('[VableFlutter] ');
      VableLogger.error('[VableFlutter] 📋 To fix this, choose one of these options:');
      VableLogger.debug('[VableFlutter] ');
      VableLogger.error('[VableFlutter] Option 1 - Configure routes in MaterialApp:');
      VableLogger.error('[VableFlutter] MaterialApp(');
      VableLogger.error('[VableFlutter]   routes: {');
      VableLogger.debug('[VableFlutter]     "$url": (context) => YourPage(),');
      VableLogger.debug('[VableFlutter]   },');
      VableLogger.debug('[VableFlutter] )');
      VableLogger.debug('[VableFlutter] ');
      VableLogger.error('[VableFlutter] Option 2 - Use onGenerateRoute:');
      VableLogger.error('[VableFlutter] MaterialApp(');
      VableLogger.error('[VableFlutter]   onGenerateRoute: (settings) {');
      VableLogger.error('[VableFlutter]     if (settings.name == "$url") {');
      VableLogger.error('[VableFlutter]       return MaterialPageRoute(builder: (_) => YourPage());');
      VableLogger.debug('[VableFlutter]     }');
      VableLogger.debug('[VableFlutter]   },');
      VableLogger.debug('[VableFlutter] )');
      VableLogger.debug('[VableFlutter] ');
      VableLogger.error('[VableFlutter] Option 3 - Configure routing library (GoRouter/AutoRoute):');
      VableLogger.debug('[VableFlutter] Vable.configureRouter(');
      VableLogger.error('[VableFlutter]   library: VableRoutingLibrary.goRouter,');
      VableLogger.error('[VableFlutter]   router: yourGoRouter,');
      VableLogger.debug('[VableFlutter] );');
      return false;
    }
  }
}

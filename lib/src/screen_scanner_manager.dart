import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'screen_scanner.dart';
import 'vable_no_op.dart';
import 'models/ui_element.dart';
import 'models/context_models.dart';
import 'vable_logger.dart';

// What the agent is told after an action, matching the web widget. The agent
// treats "Clicked" and "Filled in" as unproven until the change report backs them.
const String _elementGoneResult = 'Failed: that element is no longer on the screen';
const String _fieldGoneResult = 'Failed: that field is no longer on the screen';
const String _disabledResult = "Failed: that's turned off right now, so it can't be used";
const String _notTypableResult = "Failed: that field can't be typed in";
const String _noScrollResult = "Failed: there's nothing more to scroll to that way";
const String _blockedResult =
    'Not done: this app keeps that for the user. Ask them to check it and do it themselves.';

const Duration _settleInterval = Duration(milliseconds: 400);
const Duration _minSettleTime = Duration(milliseconds: 800);
const Duration _maxSettleTime = Duration(seconds: 3);
const Duration _focusTime = Duration(milliseconds: 300);

const int _maxNewTexts = 5;
const int _maxTextLength = 200;

/// The screen at one moment, for telling what an action changed.
class VableScreenSnapshot {
  VableScreenSnapshot._(this.texts, this.signature);

  final Set<String> texts;
  final String signature;
}

/// Manages periodic screen scanning and communication with native Android
class ScreenScannerManager with WidgetsBindingObserver{
  static final ScreenScannerManager _instance =
      ScreenScannerManager._internal();

  factory ScreenScannerManager() => _instance;

  ScreenScannerManager._internal();

  final FlutterScreenScanner _scanner = FlutterScreenScanner();
  final MethodChannel _channel = const MethodChannel('vable_flutter');

  Timer? _scanTimer;
  BuildContext? _context;
  bool _isScanning = false;
  Duration _scanInterval = const Duration(seconds: 3);

  List<ClickableElement> _lastClickableElements = [];
  List<InputElement> _lastInputElements = [];

  /// What was last sent, so a screen that hasn't changed isn't sent again.
  String? _lastSentScreen;

  /// The page on screen, from [VableNavigatorObserver].
  String? _routeName;

  /// Routes registered by Vable — kept in sync via [updateRoutes].
  List<VableRoute> _routes = [];

  /// What the app sent through [Vable.updateIntents]. Each context update
  /// replaces the last one on the server, so scans have to send it again.
  VableContextUpdate _hostContext = const VableContextUpdate();

  /// The clickable elements found during the most recent scan.
  List<ClickableElement> get lastClickableElements =>
      List.unmodifiable(_lastClickableElements);

  /// The input elements found during the most recent scan.
  List<InputElement> get lastInputElements =>
      List.unmodifiable(_lastInputElements);

  /// Called by [Vable] whenever its route list changes so that
  /// [_sendIntentContextToNative] can include up-to-date route context.
  void updateRoutes(List<VableRoute> routes) {
    _routes = List.of(routes);
  }

  /// Called by [Vable.updateIntents] so scans keep the app's own context.
  void updateHostContext(VableContextUpdate contextUpdate) {
    _hostContext = contextUpdate;
  }

  /// What the app has sent so far.
  VableContextUpdate get hostContext => _hostContext;

  /// The handler the app gave for the intent called [name], if any.
  VableIntentHandler? intentHandler(String name) {
    for (final intent in _hostContext.intents) {
      if (intent.name == name) return intent.onIntent;
    }
    return null;
  }

  /// The app's context together with what the agent needs from the SDK. Each
  /// update replaces the last one, so sending the app's alone would take away
  /// the agent's tools.
  VableContextUpdate fullContext() => _withScreenTools(
    _lastClickableElements,
    _lastInputElements,
  );

  /// Start periodic screen scanning
  void startScanning({
    required BuildContext context,
    Duration? scanInterval,
  }) {
    if (_isScanning) {
      VableLogger.debug('[VableFlutter] Screen scanning already active');
      return;
    }

    // Find the nearest Navigator's context (never unmounts)
    final navigatorContext = Navigator.maybeOf(context)?.context;
    _context = navigatorContext ?? context;

    _scanInterval = scanInterval ?? _scanInterval;
    _isScanning = true;

    VableLogger.debug('[VableFlutter] Starting screen scanning with interval: ${_scanInterval.inSeconds}s');

    // Perform initial scan immediately
    _performScan();

    // Schedule periodic scans
    _scanTimer = Timer.periodic(_scanInterval, (_) {
      _performScan();
    });
  }

  /// Stop periodic screen scanning
  void stopScanning() {
    _scanner.release();
    _lastSentScreen = null;
    if (!_isScanning) return;

    VableLogger.debug('[VableFlutter] Stopping screen scanning');
    _scanTimer?.cancel();
    _scanTimer = null;
    _isScanning = false;
    _context = null;
  }

  /// Update the current context (typically called by NavigatorObserver)
  void updateContext(BuildContext context) {
    _context = context;
  }

  /// Update the page on screen (called by NavigatorObserver)
  void updateRouteName(String? name) {
    _routeName = name;
  }

  /// Perform a single screen scan and send to native Android
  Future<void> _performScan() async {
    if (_context == null) {
      VableLogger.error('[VableFlutter] Context is null - cannot scan. Ensure NavigatorObserver is configured.');
      return;
    }

    if (!_context!.mounted) {
      VableLogger.debug('[VableFlutter] Context is unmounted - waiting for navigation update');
      return;
    }

    try {
      final screenState = await _scanner.scanScreen(_context!, routeName: _routeName);

      if (screenState != null) {
        // Grab clickables and inputs while the scanner's state is fresh.
        _lastClickableElements = List.of(_scanner.lastClickableElements);
        _lastInputElements = List.of(_scanner.lastInputElements);
        _logClickableElements(_lastClickableElements);

        final screen = _snapshotOf(screenState).signature;
        if (screen == _lastSentScreen) return;
        _lastSentScreen = screen;

        await Future.wait([
          _sendScreenContextToNative(screenState),
          _sendIntentContextToNative(_lastClickableElements, _lastInputElements),
        ]);
      }
    } catch (e, stackTrace) {
      VableLogger.error('[VableFlutter] Error during scan: $e');
      VableLogger.error('[VableFlutter] Stack trace: $stackTrace');
    }
  }

  /// Log every clickable element that has text content.
  void _logClickableElements(List<ClickableElement> elements) {
    if (elements.isEmpty) {
      VableLogger.debug('[VableFlutter] No clickable elements with text found.');
      return;
    }
    VableLogger.debug('[VableFlutter] Clickable elements (${elements.length}):');
    for (int i = 0; i < elements.length; i++) {
      VableLogger.debug('[VableFlutter]   [$i] ${elements[i]}');
    }
  }

  /// Taps [id] for the agent and returns what happened, for its tool result.
  ///
  /// Scans first so it acts on what's on screen now, not what the agent last saw.
  Future<String> clickForAgent(String id) async {
    final known = _clickable(id);
    await _performScan();
    final element = _clickable(id) ?? _sameElement(_lastClickableElements, known?.label, (e) => e.label);
    if (element == null) {
      return _scanner.isDisabled(id) ? _disabledResult : _elementGoneResult;
    }

    final center = await _bringOnScreen(element.id, element.isOffScreen, element.center);
    if (_isBlockedAt(center)) return _blockedResult;

    final before = await captureScreen();
    _scanner.tap(element.id);
    return 'Clicked. ${await describeChangeSince(before)}';
  }

  /// Types [text] into [id] for the agent and returns what happened, for its
  /// tool result.
  Future<String> inputForAgent(String id, String text) async {
    final known = _input(id);
    await _performScan();
    final element = _input(id) ?? _sameElement(_lastInputElements, known?.label, (e) => e.label);
    if (element == null) {
      return _scanner.isDisabled(id) ? _disabledResult : _fieldGoneResult;
    }

    final center = await _bringOnScreen(element.id, element.isOffScreen, element.center);
    if (_isBlockedAt(center)) return _blockedResult;

    final before = await captureScreen();
    if (!await _typeInto(element.id, text)) return _notTypableResult;
    return 'Filled in. ${await describeChangeSince(before)}';
  }

  /// Scrolls the main list for the agent and returns what came into view, for
  /// its tool result.
  Future<String> scrollForAgent({required bool down}) async {
    await _performScan();
    final before = await captureScreen();
    if (!_scanner.scroll(down: down)) return _noScrollResult;
    return 'Scrolled. ${await describeChangeSince(before)}';
  }

  ClickableElement? _clickable(String id) =>
      _lastClickableElements.cast<ClickableElement?>().firstWhere((e) => e?.id == id, orElse: () => null);

  InputElement? _input(String id) =>
      _lastInputElements.cast<InputElement?>().firstWhere((e) => e?.id == id, orElse: () => null);

  /// A rebuild can replace an element between the agent seeing it and acting on
  /// it. Only a label that can't mean anything else counts as the same element.
  T? _sameElement<T>(List<T> elements, String? label, String Function(T) labelOf) {
    if (label == null) return null;
    final matches = elements.where((e) => labelOf(e) == label);
    return matches.length == 1 ? matches.first : null;
  }

  /// Scrolls to an element if it needs it, and returns where it ended up.
  Future<Offset> _bringOnScreen(String id, bool isOffScreen, Offset center) async {
    if (!isOffScreen) return center;

    _scanner.showOnScreen(id);
    await _waitForScreenToSettle();
    await _performScan();
    return _clickable(id)?.center ?? _input(id)?.center ?? center;
  }

  /// Focuses a field by tapping it, and types into whichever field took focus.
  /// A field can move once the keyboard opens, so its position can't find it.
  Future<bool> _typeInto(String id, String text) async {
    _scanner.tap(id);
    await Future.delayed(_focusTime);

    final field = FocusManager.instance.primaryFocus?.context
        ?.findAncestorStateOfType<EditableTextState>();
    if (field == null) return false;

    field.updateEditingValue(TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    ));
    // The agent is typing, so the keyboard would only cover the screen
    field.widget.focusNode.unfocus();
    return true;
  }

  /// Hit tests like a real tap, because a tap lands by position: a clickable
  /// parent's centre can sit on a [VableNoOp] that it doesn't otherwise know of.
  bool _isBlockedAt(Offset position) {
    final result = HitTestResult();
    WidgetsBinding.instance.hitTestInView(
      result,
      position,
      WidgetsBinding.instance.platformDispatcher.implicitView!.viewId,
    );
    return result.path.any((entry) {
      final target = entry.target;
      return target is RenderMetaData && target.metaData == vableNoOpMarker;
    });
  }

  /// Records the screen, to pass to [describeChangeSince] after an action.
  Future<VableScreenSnapshot?> captureScreen() async {
    if (_context == null || !_context!.mounted) return null;

    final screenState = await _scanner.scanScreen(_context!, routeName: _routeName);
    if (screenState == null) return null;

    return _snapshotOf(screenState);
  }

  VableScreenSnapshot _snapshotOf(FlutterScreenState screenState) {
    return VableScreenSnapshot._(
      {
        ...screenState.elements.map((element) => element.text?.trim() ?? ''),
        // These carry a toggle's state, which is all that changes when it's tapped
        ..._scanner.lastClickableElements.map((element) => element.label),
      }..remove(''),
      [
        screenState.routeName,
        ...screenState.elements.map(
          (element) => '${element.id}|${element.text}|${element.isChecked}|${element.isEnabled}|${element.bounds}',
        ),
      ].join(','),
    );
  }

  /// Waits for the screen to settle, sends it to the agent, and describes what
  /// changed. "Clicked" only means the tap happened, so this is how the agent
  /// tells whether it worked.
  Future<String> describeChangeSince(VableScreenSnapshot? before) async {
    if (before == null) return '';

    final after = await _waitForScreenToSettle();
    await _performScan();
    if (after == null) return '';

    final newTexts = after.texts
        .difference(before.texts)
        .take(_maxNewTexts)
        .map((text) => text.length > _maxTextLength ? text.substring(0, _maxTextLength) : text)
        .map((text) => '"$text"');

    if (newTexts.isNotEmpty) return 'New on the screen: ${newTexts.join(', ')}.';
    if (after.signature != before.signature) {
      return 'The screen updated but shows no new text, so this is not confirmed.';
    }
    // An action can change app state that never reaches the screen, so no change
    // isn't proof that it failed.
    return 'Nothing changed on the screen, so this is not confirmed.';
  }

  Future<VableScreenSnapshot?> _waitForScreenToSettle() async {
    var waited = Duration.zero;
    var latest = await captureScreen();

    while (waited < _maxSettleTime) {
      await Future.delayed(_settleInterval);
      waited += _settleInterval;
      final next = await captureScreen();
      final isSettled = next?.signature == latest?.signature;
      latest = next;
      if (isSettled && waited >= _minSettleTime) break;
    }
    return latest;
  }

  /// Type [text] into the input element identified by [id].
  ///
  /// Throws [ArgumentError] if no input element with [id] exists in the last scan.
  Future<void> inputTextElement(String id, String text) async {
    final element = _input(id);
    if (element == null) {
      throw ArgumentError('[VableFlutter] No input element with id "$id" in the last scan.');
    }
    VableLogger.debug('[VableFlutter] Inputting text into: $element');
    await _typeInto(element.id, text);
  }

  /// Tap the element with the given [id].
  ///
  /// Throws [ArgumentError] if no element with [id] exists in the last scan.
  void triggerElement(String id) {
    final element = _clickable(id);
    if (element == null) {
      throw ArgumentError('[VableFlutter] No clickable element with id "$id" in the last scan.');
    }
    VableLogger.debug('[VableFlutter] Triggering: $element');
    _scanner.tap(element.id);
  }

  /// Send Flutter screen context to native Android
  Future<void> _sendScreenContextToNative(FlutterScreenState screenState) async {
    try {
      final jsonData = screenState.toJson();

      await _channel.invokeMethod('updateFlutterScreenContext', {
        'screenContext': jsonData,
      });

      VableLogger.debug('[VableFlutter] Sent ${screenState.elements.length} elements to native');
    } catch (e) {
      VableLogger.error('[VableFlutter] Error sending screen context to native: $e');
    }
  }

  /// Sends clickable and input elements to the native side as a [VableContextUpdate]
  /// containing a `clickElement` intent and (when inputs are present) an `inputText` intent.
  Future<void> _sendIntentContextToNative(
    List<ClickableElement> clickables,
    List<InputElement> inputs,
  ) async {
    VableLogger.debug('[VableFlutter] _sendIntentContextToNative. ${clickables.length} clickables. ${inputs.length} inputs');
    try {
      await _channel.invokeMethod('updateIntents', {
        'contextUpdate': _withScreenTools(clickables, inputs).toJson(),
      });

      VableLogger.debug(
        '[VableFlutter] Sent intent context: ${clickables.length} clickable(s), '
        '${inputs.length} input(s), ${_routes.length} route(s) to native',
      );
    } catch (e) {
      VableLogger.error('[VableFlutter] Error sending intent context to native: $e');
    }
  }

  VableContextUpdate _withScreenTools(
    List<ClickableElement> clickables,
    List<InputElement> inputs,
  ) {
    return VableContextUpdate(
      intents: [
        ..._hostContext.intents,
        VableIntent(
          name: 'clickElement',
          description:
              'Tap a visible interactive element on the current screen. '
              'Provide the element\'s "id" to trigger the corresponding tap. '
              'Use the available options to identify the correct element by its '
              'on-screen label before supplying its id. Visible Elements takes precedent to available routes since they can be used to follow the flow of the page more easily',
          parameters: {
            'id': IntentParameter(
              description:
                  'The scan ID of the element to tap. Each option lists the '
                  'human-readable label of an interactive element currently '
                  'visible on screen alongside its id value.',
              type: 'string',
              required: true,
              options: clickables
                  .map((e) => ToolParameterOption(label: e.label, value: e.id))
                  .toList(),
            ),
          },
        ),
        if (inputs.isNotEmpty)
          VableIntent(
            name: 'inputText',
            description:
                'Type text into a visible input field on the current screen. '
                'Provide the field\'s "id" and the "text" to enter.',
            parameters: {
              'id': IntentParameter(
                description:
                    'The scan ID of the input field to type into. Each option '
                    'lists the label or placeholder of the field alongside its id value.',
                type: 'string',
                required: true,
                options: inputs
                    .map((e) => ToolParameterOption(label: e.label, value: e.id))
                    .toList(),
              ),
              'text': IntentParameter(
                description: 'The text to type into the input field.',
                type: 'string',
                required: true,
                options: [],
              ),
            },
          ),
        if (_scanner.canScroll)
          VableIntent(
            name: 'scrollScreen',
            description:
                'Scroll the main list on the current screen to see more of it. '
                'Long lists only show part of what they hold, so scroll before '
                'saying that something is not there.',
            parameters: {
              'direction': IntentParameter(
                description: 'Which way to scroll.',
                type: 'string',
                required: true,
                options: [
                  ToolParameterOption(label: 'Down', value: 'down'),
                  ToolParameterOption(label: 'Up', value: 'up'),
                ],
              ),
            },
          ),
      ],
      intentStates: _hostContext.intentStates,
      intentPrompts: _hostContext.intentPrompts,
      routes: _routes.isEmpty ? _hostContext.routes : _routes,
    );
  }

  /// Manually trigger a screen scan
  Future<FlutterScreenState?> scanNow(BuildContext context) async {
    return await _scanner.scanScreen(context, routeName: _routeName);
  }

  /// Check if scanning is active
  bool get isScanning => _isScanning;

  /// Get current scan interval
  Duration get scanInterval => _scanInterval;

  /// Update scan interval (will take effect on next scan)
  void updateScanInterval(Duration interval) {
    _scanInterval = interval;

    if (_isScanning && _context != null) {
      // Restart scanning with new interval
      final context = _context!;
      stopScanning();
      startScanning(context: context, scanInterval: interval);
    }
  }
}

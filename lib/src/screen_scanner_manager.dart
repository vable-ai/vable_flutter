import 'dart:async';
import 'package:flutter/foundation.dart';
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
const String _noBackResult = "Failed: there's nothing to go back to";
const String _noScrollResult = "Failed: there's nothing more to scroll to that way";
const String _blockedResult =
    'Not done: this app keeps that for the user. Ask them to check it and do it themselves.';
const String _notAdjustableResult = "Failed: that can't be moved up or down";

const Duration _settleInterval = Duration(milliseconds: 400);
const Duration _minSettleTime = Duration(milliseconds: 800);
const Duration _maxSettleTime = Duration(seconds: 3);
const Duration _focusTime = Duration(milliseconds: 300);
const int _maxAdjustSteps = 50;

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
  List<ClickableElement> _lastAdjustableElements = [];

  /// Screens already warned about for unlabelled controls, so it's said once.
  final Set<String?> _warnedUnlabelled = {};

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

  /// The sliders and steppers found during the most recent scan.
  List<ClickableElement> get lastAdjustableElements =>
      List.unmodifiable(_lastAdjustableElements);

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
      final screenState = await _scanner.scanScreen(
        _context!,
        routeName: _routeName,
        isPrivateAt: _isKeptFromAgentAt,
      );

      if (screenState != null) {
        // Grab clickables and inputs while the scanner's state is fresh.
        _lastClickableElements = List.of(_scanner.lastClickableElements);
        _lastInputElements = List.of(_scanner.lastInputElements);
        _lastAdjustableElements = List.of(_scanner.lastAdjustableElements);
        _logClickableElements(_lastClickableElements);
        _warnAboutUnlabelled(_scanner.lastUnlabelled);

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

  /// Tells a developer, in debug builds, about controls the agent can't use
  /// because nothing says what they are, such as an icon button with no tooltip.
  void _warnAboutUnlabelled(List<Rect> unlabelled) {
    if (!kDebugMode || unlabelled.isEmpty || !_warnedUnlabelled.add(_routeName)) return;

    final where = unlabelled
        .map((rect) => '(${rect.left.round()}, ${rect.top.round()}) '
            '${rect.width.round()}x${rect.height.round()}')
        .join(', ');
    VableLogger.info(
      '[VableFlutter] ${unlabelled.length} control(s) on ${_routeName ?? 'this screen'} '
      "have no label, so the agent and screen readers can't use them. Give each a "
      'tooltip or wrap it in Semantics(label: ...). At: $where',
    );
  }

  /// What the agent is told when no element on screen has [id].
  String _missingResult(String id, String goneResult) {
    if (!FlutterScreenScanner.isScanId(id)) {
      return 'Failed: no element has the id "$id". Use an id from the options.';
    }
    return _scanner.isDisabled(id) ? _disabledResult : goneResult;
  }

  /// Taps [id] for the agent and returns what happened, for its tool result.
  ///
  /// Scans first so it acts on what's on screen now, not what the agent last saw.
  Future<String> clickForAgent(String id) async {
    final known = _clickable(id);
    await _performScan();
    final element = _clickable(id) ?? _sameElement(_lastClickableElements, known?.label, (e) => e.label);
    if (element == null) return _missingResult(id, _elementGoneResult);

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
    if (element == null) return _missingResult(id, _fieldGoneResult);

    final center = await _bringOnScreen(element.id, element.isOffScreen, element.center);
    if (_isBlockedAt(center)) return _blockedResult;

    final before = await captureScreen();
    if (!await _typeInto(element.id, text)) return _notTypableResult;
    return 'Filled in. ${await describeChangeSince(before)}';
  }

  /// Moves a slider for the agent, by [steps] or until it reaches [target], and
  /// returns where it ended up, for its tool result.
  Future<String> adjustForAgent(
    String id, {
    required bool up,
    int steps = 1,
    num? target,
  }) async {
    final known = _adjustable(id);
    await _performScan();
    final element = _adjustable(id) ??
        _sameElement(_lastAdjustableElements, known?.label, (e) => e.label);
    if (element == null) {
      if (_clickable(id) != null || _input(id) != null) return _notAdjustableResult;
      return _missingResult(id, _elementGoneResult);
    }

    final center = await _bringOnScreen(element.id, element.isOffScreen, element.center);
    if (_isBlockedAt(center)) return _blockedResult;

    final before = await captureScreen();
    final limit = target == null ? steps.clamp(1, _maxAdjustSteps) : _maxAdjustSteps;
    var label = element.label;
    // A target says which way to go, whatever direction was given
    final current = _numberIn(label);
    if (target != null && current != null && current != target) up = current < target;
    for (var step = 0; step < limit; step++) {
      if (target != null && _hasReached(label, target, up: up)) break;
      _scanner.adjust(element.id, up: up);
      await WidgetsBinding.instance.endOfFrame;
      await _performScan();
      final moved = _adjustable(element.id)?.label;
      // It's at the end of its range
      if (moved == null || moved == label) break;
      label = moved;
    }
    final change = await describeChangeSince(before);
    return 'Moved. It now reads "$label". $change'.trim();
  }

  /// Whether a slider's label shows it has reached [target], going [up] or down.
  bool _hasReached(String label, num target, {required bool up}) {
    final value = _numberIn(label);
    if (value == null) return false;
    return up ? value >= target : value <= target;
  }

  /// The last number in a slider's label, which is its value.
  num? _numberIn(String label) {
    final match = RegExp(r'-?\d+(\.\d+)?').allMatches(label).lastOrNull;
    return match == null ? null : num.tryParse(match.group(0)!);
  }

  /// Scrolls the main list for the agent and returns what came into view, for
  /// its tool result.
  Future<String> scrollForAgent({required bool down}) async {
    await _performScan();
    final before = await captureScreen();
    if (!_scanner.scroll(down: down)) return _noScrollResult;
    return 'Scrolled. ${await describeChangeSince(before)}';
  }

  /// Goes back for the agent and returns what it found, for its tool result.
  /// Back arrows are often icons with no label, which would leave it stuck.
  Future<String> goBackForAgent() async {
    final navigator = _navigatorWithHistory();
    if (navigator == null) return _noBackResult;

    final before = await captureScreen();
    if (!await navigator.maybePop()) return _noBackResult;
    return 'Went back. ${await describeChangeSince(before)}';
  }

  /// Leaves a page that came up empty, and returns whether it did. Routes that
  /// need an item passed to them show nothing when opened by path alone.
  Future<bool> leaveEmptyScreen() async {
    final screen = await captureScreen();
    if (screen == null || screen.texts.isNotEmpty) return false;

    final navigator = _navigatorWithHistory();
    if (navigator == null) return false;
    await navigator.maybePop();
    return true;
  }

  /// The nearest navigator with something to go back to, which can be the root
  /// one when the page on top is outside the app's tabs.
  NavigatorState? _navigatorWithHistory() {
    if (_context == null || !_context!.mounted) return null;

    final navigators = [
      Navigator.maybeOf(_context!),
      Navigator.maybeOf(_context!, rootNavigator: true),
    ];
    for (final navigator in navigators) {
      if (navigator != null && navigator.canPop()) return navigator;
    }
    return null;
  }

  ClickableElement? _clickable(String id) =>
      _lastClickableElements.cast<ClickableElement?>().firstWhere((e) => e?.id == id, orElse: () => null);

  InputElement? _input(String id) =>
      _lastInputElements.cast<InputElement?>().firstWhere((e) => e?.id == id, orElse: () => null);

  ClickableElement? _adjustable(String id) =>
      _lastAdjustableElements.cast<ClickableElement?>().firstWhere((e) => e?.id == id, orElse: () => null);

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
  bool _isBlockedAt(Offset position) => _isKeptFromAgentAt(position);

  /// Whether a [VableNoOp] covers [position]. Fields inside one are private too.
  bool _isKeptFromAgentAt(Offset position) {
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

    final screenState = await _scanner.scanScreen(
      _context!,
      routeName: _routeName,
      isPrivateAt: _isKeptFromAgentAt,
    );
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
        if (_navigatorWithHistory() != null)
          VableIntent(
            name: 'goBack',
            description:
                'Go back to the previous screen, or close the dialog or sheet '
                'that is open. Use this when there is no back button to tap.',
          ),
        if (_lastAdjustableElements.isNotEmpty)
          VableIntent(
            name: 'adjustSlider',
            description:
                'Move a slider or stepper on the current screen up or down. Give '
                'a "target" to move it until it reads that number, or "steps" '
                'to move it that many notches.',
            parameters: {
              'id': IntentParameter(
                description:
                    'The scan ID of the slider. Each option lists its label and '
                    'current value alongside its id value.',
                type: 'string',
                required: true,
                options: _lastAdjustableElements
                    .map((e) => ToolParameterOption(label: e.label, value: e.id))
                    .toList(),
              ),
              'direction': IntentParameter(
                description: 'Which way to move it.',
                type: 'string',
                required: true,
                options: [
                  ToolParameterOption(label: 'Up', value: 'up'),
                  ToolParameterOption(label: 'Down', value: 'down'),
                ],
              ),
              'target': IntentParameter(
                description:
                    'The number it should read when done, in the units its value '
                    'shows: for "40%", a percentage. It moves whichever way it needs to.',
                type: 'number',
                required: false,
                options: [],
              ),
              'steps': IntentParameter(
                description: 'How many notches to move it when there is no target. Defaults to 1.',
                type: 'number',
                required: false,
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
    return await _scanner.scanScreen(
      context,
      routeName: _routeName,
      isPrivateAt: _isKeptFromAgentAt,
    );
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

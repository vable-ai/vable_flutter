import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screen_scanner.dart';
import 'models/ui_element.dart';
import 'models/context_models.dart';

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
  int _pointerCounter = 100; // start above 0 to avoid conflicts with real input

  /// Routes registered by Vable — kept in sync via [updateRoutes].
  List<VableRoute> _routes = [];

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


  /// Start periodic screen scanning
  void startScanning({
    required BuildContext context,
    Duration? scanInterval,
  }) {
    if (_isScanning) {
      debugPrint('[VableFlutter] Screen scanning already active');
      return;
    }

    // Find the nearest Navigator's context (never unmounts)
    final navigatorContext = Navigator.maybeOf(context)?.context;
    _context = navigatorContext ?? context;

    _scanInterval = scanInterval ?? _scanInterval;
    _isScanning = true;

    debugPrint('[VableFlutter] Starting screen scanning with interval: ${_scanInterval.inSeconds}s');

    // Perform initial scan immediately
    _performScan();

    // Schedule periodic scans
    _scanTimer = Timer.periodic(_scanInterval, (_) {
      _performScan();
    });
  }

  /// Stop periodic screen scanning
  void stopScanning() {
    if (!_isScanning) return;

    debugPrint('[VableFlutter] Stopping screen scanning');
    _scanTimer?.cancel();
    _scanTimer = null;
    _isScanning = false;
    _context = null;
  }

  /// Update the current context (typically called by NavigatorObserver)
  void updateContext(BuildContext context) {
    _context = context;
  }

  /// Perform a single screen scan and send to native Android
  Future<void> _performScan() async {
    if (_context == null) {
      debugPrint('[VableFlutter] Context is null - cannot scan. Ensure NavigatorObserver is configured.');
      return;
    }

    if (!_context!.mounted) {
      debugPrint('[VableFlutter] Context is unmounted - waiting for navigation update');
      return;
    }

    try {
      final screenState = await _scanner.scanScreen(_context!);

      if (screenState != null) {
        // Grab clickables and inputs while the scanner's state is fresh.
        _lastClickableElements = List.of(_scanner.lastClickableElements);
        _lastInputElements = List.of(_scanner.lastInputElements);
        _logClickableElements(_lastClickableElements);
        await Future.wait([
          _sendScreenContextToNative(screenState),
          _sendIntentContextToNative(_lastClickableElements, _lastInputElements),
        ]);
      }
    } catch (e, stackTrace) {
      debugPrint('[VableFlutter] Error during scan: $e');
      debugPrint('[VableFlutter] Stack trace: $stackTrace');
    }
  }

  /// Log every clickable element that has text content.
  void _logClickableElements(List<ClickableElement> elements) {
    if (elements.isEmpty) {
      debugPrint('[VableFlutter] No clickable elements with text found.');
      return;
    }
    debugPrint('[VableFlutter] Clickable elements (${elements.length}):');
    for (int i = 0; i < elements.length; i++) {
      debugPrint('[VableFlutter]   [$i] ${elements[i]}');
    }
  }

  /// Type [text] into the input element identified by [id].
  ///
  /// Simulates a tap on the field to acquire focus, then uses
  /// [SystemChannels.textInput] to set the editing state so the connected
  /// [TextEditingController] (including reactive_forms' FormControl) receives
  /// the value — no controller reference required.
  ///
  /// Throws [ArgumentError] if no input element with [id] exists in the last scan.
  Future<void> inputTextElement(String id, String text) async {
    final element = _lastInputElements.cast<InputElement?>().firstWhere(
          (e) => e?.id == id,
          orElse: () => null,
        );
    if (element == null) {
      throw ArgumentError('[VableFlutter] No input element with id "$id" in the last scan.');
    }
    debugPrint('[VableFlutter] Inputting text into: $element');

    // Tap the centre to focus the field.
    _simulateTap(element.center);
    await Future.delayed(const Duration(milliseconds: 300));

    // Traverse the element tree to find the EditableTextState whose render box
    // contains the tapped point and update its value directly. This updates the
    // TextEditingController and triggers a widget rebuild — unlike
    // TextInput.setEditingState which only sends state to the platform/keyboard
    // and leaves Flutter's widget layer stale.
    if (_context == null || !_context!.mounted) return;
    _setEditableTextValue(_context!, element.center, text);
  }

  /// Walks the element tree from [context] to find the [EditableTextState]
  /// whose rendered bounds contain [center], then sets its text to [value].
  void _setEditableTextValue(BuildContext context, Offset center, String value) {
    bool updated = false;

    void visitor(Element el) {
      if (updated) return;
      if (el is StatefulElement && el.state is EditableTextState) {
        final renderObject = el.renderObject;
        if (renderObject is RenderBox && renderObject.hasSize) {
          final rect = renderObject.localToGlobal(Offset.zero) & renderObject.size;
          if (rect.contains(center)) {
            (el.state as EditableTextState).updateEditingValue(TextEditingValue(
              text: value,
              selection: TextSelection.collapsed(offset: value.length),
            ));
            updated = true;
            return;
          }
        }
      }
      el.visitChildElements(visitor);
    }

    context.visitChildElements(visitor);

    if (!updated) {
      debugPrint('[VableFlutter] inputTextElement: no EditableTextState found at $center');
    }
  }

  /// Simulate a tap on the element with the given [id].
  ///
  /// Dispatches synthetic pointer-down / pointer-up events at the element's
  /// centre so the gesture recogniser attached to that widget fires its onTap.
  ///
  /// Throws [ArgumentError] if no element with [id] exists in the last scan.
  void triggerElement(String id) {
    final element = _lastClickableElements.cast<ClickableElement?>().firstWhere(
          (e) => e?.id == id,
          orElse: () => null,
        );
    if (element == null) {
      throw ArgumentError('[VableFlutter] No clickable element with id "$id" in the last scan.');
    }
    debugPrint('[VableFlutter] Triggering: $element');
    _simulateTap(element.center);
  }

  /// Dispatch a synthetic tap (pointer down + up) at [position] in global
  /// screen coordinates.
  void _simulateTap(Offset position) {
    final int pointer = _pointerCounter++;
    GestureBinding.instance.handlePointerEvent(
      PointerDownEvent(position: position, pointer: pointer),
    );
    GestureBinding.instance.handlePointerEvent(
      PointerUpEvent(position: position, pointer: pointer),
    );
  }

  /// Send Flutter screen context to native Android
  Future<void> _sendScreenContextToNative(FlutterScreenState screenState) async {
    try {
      final jsonData = screenState.toJson();

      await _channel.invokeMethod('updateFlutterScreenContext', {
        'screenContext': jsonData,
      });

      debugPrint('[VableFlutter] Sent ${screenState.elements.length} elements to native');
    } catch (e) {
      debugPrint('[VableFlutter] Error sending screen context to native: $e');
    }
  }

  /// Sends clickable and input elements to the native side as a [VableContextUpdate]
  /// containing a `clickElement` intent and (when inputs are present) an `inputText` intent.
  Future<void> _sendIntentContextToNative(
    List<ClickableElement> clickables,
    List<InputElement> inputs,
  ) async {
    debugPrint('[VableFlutter] _sendIntentContextToNative. ${clickables.length} clickables. ${inputs.length} inputs');
    try {
      final intents = <VableIntent>[
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
      ];

      final contextUpdate = VableContextUpdate(
        intents: intents,
        routes: _routes,
      );

      await _channel.invokeMethod('updateIntents', {
        'contextUpdate': contextUpdate.toJson(),
      });

      debugPrint(
        '[VableFlutter] Sent intent context: ${clickables.length} clickable(s), '
        '${inputs.length} input(s), ${_routes.length} route(s) to native',
      );
    } catch (e) {
      debugPrint('[VableFlutter] Error sending intent context to native: $e');
    }
  }

  /// Manually trigger a screen scan
  Future<FlutterScreenState?> scanNow(BuildContext context) async {
    return await _scanner.scanScreen(context);
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
      stopScanning();
      startScanning(context: _context!, scanInterval: interval);
    }
  }
}

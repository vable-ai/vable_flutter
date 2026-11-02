import 'dart:ui' show CheckedState, Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'models/ui_element.dart';
import 'vable_logger.dart';

const Duration _firstBuildTimeout = Duration(seconds: 1);
const String _idPrefix = 's_';

// Fields whose values are hidden even when the app doesn't mark them, because
// they're the kind of thing that should never reach a model
final RegExp _privateFieldLabel = RegExp(
  r'card ?number|\bcard\b|cvv|cvc|security code|\bpin\b|account number|iban|'
  r'routing|sort code|\bssn\b|social security|passport|\bbvn\b|\bnin\b|password|passcode',
  caseSensitive: false,
);

/// Whether the field at a point on screen is one the app keeps private.
typedef VablePrivateTest = bool Function(Offset position);

/// Reads the screen from Flutter's semantics tree, the same view a screen reader
/// gets. The render tree holds every page in the stack and every hidden tab, and
/// says nothing about labels or disabled controls. Semantics leaves those out,
/// and works the same in release builds.
class FlutterScreenScanner {
  SemanticsHandle? _semantics;
  SemanticsOwner? _owner;

  List<FlutterUIElement> _elements = [];
  List<ClickableElement> _lastClickableElements = [];
  List<InputElement> _lastInputElements = [];
  List<ClickableElement> _lastAdjustableElements = [];
  List<Rect> _lastUnlabelled = [];

  // Largest first, so scrolling moves the main list
  List<_Scrollable> _scrollables = [];

  /// The clickable elements found during the most recent [scanScreen] call.
  List<ClickableElement> get lastClickableElements =>
      List.unmodifiable(_lastClickableElements);

  /// The input elements found during the most recent [scanScreen] call.
  List<InputElement> get lastInputElements =>
      List.unmodifiable(_lastInputElements);

  /// Sliders and other controls that move up and down in steps, found during
  /// the most recent [scanScreen] call. Their labels include the value.
  List<ClickableElement> get lastAdjustableElements =>
      List.unmodifiable(_lastAdjustableElements);

  /// Where the controls with nothing to call them are, from the most recent
  /// [scanScreen] call. Neither the agent nor a screen reader can use them.
  List<Rect> get lastUnlabelled => List.unmodifiable(_lastUnlabelled);

  /// Whether the screen has something that scrolls in either direction.
  bool get canScroll => _scrollables.isNotEmpty;

  /// Whether [id] is on screen but turned off.
  bool isDisabled(String id) =>
      _elements.any((element) => element.id == id && !element.isEnabled);

  /// Stops Flutter building the semantics tree. Scanning starts it again.
  void release() {
    _semantics?.dispose();
    _semantics = null;
    _owner = null;
  }

  /// Scan the current Flutter screen and return all detected UI elements.
  ///
  /// [isPrivateAt] hides the values of fields the app keeps private.
  Future<FlutterScreenState?> scanScreen(
    BuildContext context, {
    String? routeName,
    VablePrivateTest? isPrivateAt,
  }) async {
    try {
      if (_semantics == null) {
        _semantics = SemanticsBinding.instance.ensureSemantics();
        await WidgetsBinding.instance.endOfFrame.timeout(
          _firstBuildTimeout,
          onTimeout: () {},
        );
        if (!context.mounted) return null;
      }

      final owner = context.findRenderObject()?.owner?.semanticsOwner;
      final root = owner?.rootSemanticsNode;
      if (root == null) {
        VableLogger.debug('[VableFlutter] Semantics tree is not ready yet');
        return null;
      }
      _owner = owner;

      final scan = _Scan(1 / View.of(context).devicePixelRatio, isPrivateAt);
      scan.visit(root, Matrix4.identity(), null, 0);

      _elements = scan.elements;
      _lastClickableElements = scan.clickables;
      _lastInputElements = scan.inputs;
      _lastAdjustableElements = scan.adjustables;
      _lastUnlabelled = scan.unlabelled;
      _scrollables = scan.scrollables..sort((a, b) => b.area.compareTo(a.area));

      VableLogger.debug(
        '[VableFlutter] Screen scan completed. Found ${_elements.length} UI elements',
      );

      return FlutterScreenState(
        timestamp: DateTime.now().millisecondsSinceEpoch,
        elements: _elements,
        screenSize: MediaQuery.sizeOf(context),
        routeName: routeName,
        metadata: {'source': 'flutter'},
      );
    } catch (e, stackTrace) {
      VableLogger.error('[VableFlutter] Error during screen scan: $e');
      VableLogger.error('[VableFlutter] Stack trace: $stackTrace');
      return null;
    }
  }

  /// Taps through semantics, like a screen reader. Going by position would land
  /// on whatever has moved over the element.
  void tap(String id) {
    _owner?.performAction(_nodeId(id), SemanticsAction.tap);
  }

  /// Brings an element that's scrolled out of view back on to the screen.
  void showOnScreen(String id) {
    _owner?.performAction(_nodeId(id), SemanticsAction.showOnScreen);
  }

  /// Moves a slider or similar control one step up or down.
  void adjust(String id, {required bool up}) {
    _owner?.performAction(
      _nodeId(id),
      up ? SemanticsAction.increase : SemanticsAction.decrease,
    );
  }

  /// Scrolls the main list one step. Returns false if it can't go that way.
  bool scroll({required bool down}) {
    final action = down ? SemanticsAction.scrollUp : SemanticsAction.scrollDown;
    for (final scrollable in _scrollables) {
      if (down ? scrollable.canGoDown : scrollable.canGoUp) {
        _owner?.performAction(scrollable.nodeId, action);
        return true;
      }
    }
    return false;
  }

  int _nodeId(String id) => int.parse(id.substring(_idPrefix.length));

  /// Whether [id] could have come from a scan, so a made-up one can be told
  /// apart from an element that has gone.
  static bool isScanId(String id) =>
      id.startsWith(_idPrefix) && int.tryParse(id.substring(_idPrefix.length)) != null;
}

class _Scrollable {
  _Scrollable(this.nodeId, this.area, this.canGoDown, this.canGoUp);

  final int nodeId;
  final double area;
  final bool canGoDown;
  final bool canGoUp;
}

class _Scan {
  _Scan(this.scale, this.isPrivateAt);

  final double scale;
  final VablePrivateTest? isPrivateAt;
  final elements = <FlutterUIElement>[];
  final clickables = <ClickableElement>[];
  final inputs = <InputElement>[];
  final adjustables = <ClickableElement>[];
  final unlabelled = <Rect>[];
  final scrollables = <_Scrollable>[];

  // The last plain text seen, which often names the control beside it, as in
  // a Row of Text('Sugar') and a Slider
  String? _lastText;
  Rect? _lastTextBounds;

  void visit(SemanticsNode node, Matrix4 parentTransform, String? parentId, int depth) {
    final transform = node.transform == null
        ? parentTransform
        : (parentTransform.clone()..multiply(node.transform!));
    final id = '$_idPrefix${node.id}';
    final data = node.getSemanticsData();

    if (!node.isInvisible) {
      final bounds = MatrixUtils.transformRect(transform, node.rect);
      _add(node, data, id, _logical(bounds), parentId, depth);
    }

    if (node.mergeAllDescendantsIntoThisNode) return;
    node.visitChildren((child) {
      visit(child, transform, id, depth + 1);
      return true;
    });
  }

  Rect _logical(Rect rect) => Rect.fromLTRB(
    rect.left * scale,
    rect.top * scale,
    rect.right * scale,
    rect.bottom * scale,
  );

  void _add(
    SemanticsNode node,
    SemanticsData data,
    String id,
    Rect bounds,
    String? parentId,
    int depth,
  ) {
    final flags = data.flagsCollection;
    final isEnabled = flags.isEnabled != Tristate.isFalse;
    final isField = flags.isTextField;
    final canTap = data.hasAction(SemanticsAction.tap);
    final isClickable = canTap && isEnabled && !isField;
    final isAdjustable = isEnabled &&
        (data.hasAction(SemanticsAction.increase) || data.hasAction(SemanticsAction.decrease));
    // A scroll up moves the content up, which shows what's further down
    final canScrollDown = data.hasAction(SemanticsAction.scrollUp);
    final canScrollUp = data.hasAction(SemanticsAction.scrollDown);
    final isScrollable = canScrollDown || canScrollUp;

    var label = _firstText([data.label, data.tooltip]);
    if (label.isEmpty && (isAdjustable || isField)) label = _textBeside(bounds);
    final hint = _clean(data.hint);
    final isPrivate = flags.isObscured ||
        (isField && (_privateFieldLabel.hasMatch('$label $hint') ||
            (isPrivateAt?.call(bounds.center) ?? false)));
    final value = isPrivate ? '' : _clean(data.value);

    final hasContent = label.isNotEmpty || value.isNotEmpty || hint.isNotEmpty;
    if (!hasContent && (isClickable || isAdjustable)) unlabelled.add(bounds);
    if (!hasContent && !isField && !isScrollable) return;

    if (!isClickable && !isField && !isAdjustable && label.isNotEmpty) {
      _lastText = label;
      _lastTextBounds = bounds;
    }

    final type = _typeOf(flags, isClickable, isScrollable);
    elements.add(
      FlutterUIElement(
        id: id,
        type: type,
        bounds: bounds,
        text: [label, value].where((text) => text.isNotEmpty).join(' ').nullIfEmpty,
        semanticsLabel: isField ? label.nullIfEmpty : null,
        isClickable: isClickable,
        isScrollable: isScrollable,
        isEnabled: isEnabled,
        isVisible: !flags.isHidden,
        isFocusable: isField,
        isSelected: flags.isSelected == Tristate.isTrue,
        isChecked: _checkedState(flags),
        hint: canScrollDown
            ? 'There is more below. Scroll down to see it.'
            : isPrivate && isField
                ? 'What is typed here is private, so it is not shown.'
                : hint.nullIfEmpty,
        parentId: parentId,
        depth: depth,
      ),
    );

    if (isScrollable) {
      scrollables.add(
        _Scrollable(node.id, bounds.width * bounds.height, canScrollDown, canScrollUp),
      );
    }

    if (isField && isEnabled) {
      inputs.add(
        InputElement(
          id: id,
          type: type,
          bounds: bounds,
          label: _firstText([label, hint]).orElse('Text field'),
          depth: depth,
          isOffScreen: flags.isHidden,
        ),
      );
    } else if (isAdjustable) {
      if (label.isEmpty && value.isEmpty) return;
      adjustables.add(
        ClickableElement(
          id: id,
          type: type,
          bounds: bounds,
          label: [label, value].where((text) => text.isNotEmpty).join(', '),
          depth: depth,
          isOffScreen: flags.isHidden,
        ),
      );
    } else if (isClickable) {
      final name = _firstText([label, value, hint]);
      if (name.isEmpty) return;
      clickables.add(
        ClickableElement(
          id: id,
          type: type,
          bounds: bounds,
          label: '$name${_stateOf(flags)}',
          depth: depth,
          isOffScreen: flags.isHidden,
        ),
      );
    }
  }

  String _typeOf(SemanticsFlags flags, bool isClickable, bool isScrollable) {
    if (flags.isTextField) return 'input_field';
    if (flags.isSlider) return 'seek_bar';
    if (flags.isInMutuallyExclusiveGroup) return 'radio_button';
    if (flags.isChecked != CheckedState.none) return 'checkbox';
    if (flags.isToggled != Tristate.none) return 'switch';
    if (flags.isLink) return 'link';
    if (flags.isButton) return 'button';
    if (flags.isImage) return 'image';
    if (isClickable) return 'button';
    if (isScrollable) return 'scroll_view';
    return 'text';
  }

  bool? _checkedState(SemanticsFlags flags) {
    if (flags.isChecked != CheckedState.none) {
      return flags.isChecked == CheckedState.isTrue;
    }
    if (flags.isToggled != Tristate.none) {
      return flags.isToggled == Tristate.isTrue;
    }
    return null;
  }

  /// So the agent can tell a toggle's state, and see that tapping changed it.
  String _stateOf(SemanticsFlags flags) {
    if (flags.isInMutuallyExclusiveGroup) {
      return flags.isChecked == CheckedState.isTrue ? ' (selected)' : '';
    }
    if (flags.isChecked != CheckedState.none) {
      return flags.isChecked == CheckedState.isTrue ? ' (checked)' : ' (not checked)';
    }
    if (flags.isToggled != Tristate.none) {
      return flags.isToggled == Tristate.isTrue ? ' (on)' : ' (off)';
    }
    return flags.isSelected == Tristate.isTrue ? ' (selected)' : '';
  }

  /// Text just before a control on the same line, or just above it, which
  /// usually says what the control is for.
  String _textBeside(Rect bounds) {
    final text = _lastText;
    final textBounds = _lastTextBounds;
    if (text == null || textBounds == null) return '';

    final sameLine = textBounds.center.dy >= bounds.top &&
        textBounds.center.dy <= bounds.bottom &&
        textBounds.right <= bounds.left + 8;
    final justAbove = textBounds.bottom <= bounds.top + 4 &&
        bounds.top - textBounds.bottom < 24 &&
        textBounds.left < bounds.right;
    return sameLine || justAbove ? text : '';
  }

  String _firstText(List<String> texts) => texts
      .map(_clean)
      .firstWhere((text) => text.isNotEmpty, orElse: () => '');

  String _clean(String text) => text.replaceAll(RegExp(r'\s+'), ' ').trim();
}

extension on String {
  String? get nullIfEmpty => isEmpty ? null : this;

  String orElse(String fallback) => isEmpty ? fallback : this;
}

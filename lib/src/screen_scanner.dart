import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'models/ui_element.dart';
import 'vable_logger.dart';

/// Scans the Flutter widget tree and extracts UI element information
class FlutterScreenScanner {
  int _idCounter = 0;
  final Map<String, FlutterUIElement> _elementsMap = {};
  final Map<String, List<String>> _parentChildMap = {};

  // Maps clickable element ID → all text tokens found in its subtree.
  // Populated during traversal using an ancestor stack.
  final Map<String, List<String>> _clickableDescendantTexts = {};

  List<ClickableElement> _lastClickableElements = [];
  List<InputElement> _lastInputElements = [];

  /// The clickable elements found during the most recent [scanScreen] call.
  List<ClickableElement> get lastClickableElements =>
      List.unmodifiable(_lastClickableElements);

  /// The input elements found during the most recent [scanScreen] call.
  List<InputElement> get lastInputElements =>
      List.unmodifiable(_lastInputElements);

  /// Scan the current Flutter screen and return all detected UI elements.
  ///
  /// After this call, [lastClickableElements] is populated with every clickable
  /// element whose subtree contains at least one non-empty text node.
  Future<FlutterScreenState?> scanScreen(BuildContext context) async {
    try {
      _elementsMap.clear();
      _parentChildMap.clear();
      _clickableDescendantTexts.clear();
      _lastClickableElements = [];
      _lastInputElements = [];
      _idCounter = 0;

      // Get the root render object
      final RenderObject? renderObject = context.findRenderObject();
      if (renderObject == null) {
        VableLogger.error('[VableFlutter] No render object found');
        return null;
      }

      // Get screen size
      final Size screenSize = MediaQuery.of(context).size;

      // Get current route name
      final String? routeName = ModalRoute.of(context)?.settings.name;

      // Traverse the render tree; the mutable list acts as an ancestor stack.
      await _traverseRenderTree(renderObject, null, 0, []);

      // Update child relationships
      _updateChildRelationships();

      // Build the clickable and input element lists from the collected data.
      _lastClickableElements = _buildClickableElements();
      _lastInputElements = _buildInputElements();

      final elements = _elementsMap.values.toList();
      VableLogger.debug('[VableFlutter] Screen scan completed. Found ${elements.length} UI elements');

      return FlutterScreenState(
        timestamp: DateTime.now().millisecondsSinceEpoch,
        elements: elements,
        screenSize: screenSize,
        routeName: routeName,
        metadata: {'source': 'flutter'},
      );
    } catch (e, stackTrace) {
      VableLogger.error('[VableFlutter] Error during screen scan: $e');
      VableLogger.error('[VableFlutter] Stack trace: $stackTrace');
      return null;
    }
  }

  /// Build [ClickableElement] list from text tokens collected during traversal.
  List<ClickableElement> _buildClickableElements() {
    final List<ClickableElement> result = [];
    for (final entry in _clickableDescendantTexts.entries) {
      final tokens = entry.value;
      if (tokens.isEmpty) continue;
      final element = _elementsMap[entry.key];
      if (element == null) continue;
      result.add(ClickableElement(
        id: element.id,
        type: element.type,
        bounds: element.bounds,
        label: tokens.join(' ').trim(),
        depth: element.depth,
      ));
    }
    // Shallowest first so the most encompassing elements come first.
    result.sort((a, b) => a.depth.compareTo(b.depth));
    return result;
  }

  /// Build [InputElement] list from all `input_field` elements found during traversal.
  List<InputElement> _buildInputElements() {
    final List<InputElement> result = [];
    for (final element in _elementsMap.values) {
      if (element.type != 'input_field') continue;
      final label = element.semanticsLabel ?? element.text ?? 'Input field';
      result.add(InputElement(
        id: element.id,
        type: element.type,
        bounds: element.bounds,
        label: label,
        depth: element.depth,
      ));
    }
    result.sort((a, b) => a.depth.compareTo(b.depth));
    return result;
  }

  /// Recursively traverse the render tree.
  ///
  /// [activeClickableIds] is a mutable stack of clickable ancestor element IDs.
  /// Every text node encountered adds its text to each ID in the stack so that
  /// clickable elements accumulate the full text of their entire subtree.
  /// The stack is mutated (push before children, pop after) — this is safe
  /// because there are no actual `await` points and [visitChildren] is sync.
  Future<void> _traverseRenderTree(
    RenderObject renderObject,
    String? parentId,
    int depth,
    List<String> activeClickableIds,
  ) async {
    try {
      // Skip if depth is too deep (prevent infinite recursion)
      // 100 is needed for deeply nested widgets (e.g. cards inside scroll views
      // inside sliver grids inside scaffold bodies can easily reach depth 55+)
      if (depth > 100) return;

      final element = _createUIElement(renderObject, parentId, depth);

      // Only add elements that are potentially useful
      if (_shouldIncludeElement(element)) {
        _elementsMap[element.id] = element;

        // Track parent-child relationships
        if (parentId != null) {
          _parentChildMap.putIfAbsent(parentId, () => []).add(element.id);
        }

        // Debug logging for navigation elements
        if (element.type == 'navigation' || element.type == 'button' && element.className?.contains('Navigation') == true) {
          VableLogger.debug('[VableFlutter] Found navigation element: ${element.className} - ${element.type} - clickable: ${element.isClickable} - text: ${element.text} - semantics: ${element.semanticsLabel}');
        }
      }

      // If this element is clickable and included, push it onto the ancestor
      // stack so its descendants' text tokens are accumulated into its bucket.
      final bool pushedToStack =
          element.isClickable && _elementsMap.containsKey(element.id);
      if (pushedToStack) {
        _clickableDescendantTexts.putIfAbsent(element.id, () => []);
        activeClickableIds.add(element.id);
      }

      // Distribute this element's own text to every active clickable ancestor
      // (including itself when pushedToStack is true).
      final String? text = element.text;
      if (text != null && text.isNotEmpty) {
        for (final id in activeClickableIds) {
          _clickableDescendantTexts.putIfAbsent(id, () => []).add(text);
        }
      }

      // Recursively process children with the (possibly extended) stack.
      renderObject.visitChildren((child) {
        _traverseRenderTree(child, element.id, depth + 1, activeClickableIds);
      });

      // Restore the stack after visiting all children.
      if (pushedToStack) {
        activeClickableIds.removeLast();
      }
    } catch (e) {
      VableLogger.error('[VableFlutter] Error processing render object: $e');
    }
  }

  /// Create a FlutterUIElement from a RenderObject
  FlutterUIElement _createUIElement(
    RenderObject renderObject,
    String? parentId,
    int depth,
  ) {
    final id = _generateElementId();

    // Get bounds
    final bounds = _getBounds(renderObject);

    // Determine element type and properties
    final type = _determineElementType(renderObject);
    final text = _extractText(renderObject);
    final semanticsLabel = _extractSemanticsLabel(renderObject);
    final className = renderObject.runtimeType.toString();

    // Determine interaction capabilities
    final isClickable = _isClickable(renderObject);
    final isScrollable = _isScrollable(renderObject);
    final isEnabled = true; // Flutter doesn't have a simple enabled state like Android
    final isVisible = _isVisible(renderObject);
    final isFocusable = _isFocusable(renderObject);

    // Extract additional properties
    final properties = _extractProperties(renderObject);

    return FlutterUIElement(
      id: id,
      type: type,
      bounds: bounds,
      text: text,
      semanticsLabel: semanticsLabel,
      className: className,
      isClickable: isClickable,
      isScrollable: isScrollable,
      isEnabled: isEnabled,
      isVisible: isVisible,
      isFocusable: isFocusable,
      isSelected: false,
      parentId: parentId,
      depth: depth,
      properties: properties,
    );
  }

  /// Determine if an element should be included in the scan results
  bool _shouldIncludeElement(FlutterUIElement element) {
    // Always include elements with meaningful content
    if (element.text != null && element.text!.isNotEmpty) return true;
    if (element.semanticsLabel != null && element.semanticsLabel!.isNotEmpty) return true;

    // Always include interactive elements
    if (element.isClickable) return true;
    if (element.isScrollable) return true;

    // Always include significant UI component types
    final significantTypes = {
      'button',
      'input_field',
      'checkbox',
      'radio_button',
      'switch',
      'navigation',
      'toolbar',
      'fab',
      'tab',
      'dialog',
      'list',
      'image',
    };

    if (significantTypes.contains(element.type)) return true;

    // VableLogger.debug('[VableFlutter] Ignoring element ${element.className}');

    // Exclude generic containers without any useful information
    return false;
  }

  /// Get the global bounds of a RenderObject
  Rect _getBounds(RenderObject renderObject) {
    try {
      if (renderObject is RenderBox && renderObject.hasSize) {
        final offset = renderObject.localToGlobal(Offset.zero);
        final size = renderObject.size;
        return Rect.fromLTWH(offset.dx, offset.dy, size.width, size.height);
      }
    } catch (e) {
      // Ignore errors getting bounds
    }
    return Rect.zero;
  }

  /// Determine the element type from RenderObject
  String _determineElementType(RenderObject renderObject) {
    final className = renderObject.runtimeType.toString();

    // Check for navigation components first (Material 2 & 3)
    if (className.contains('NavigationBar') ||
        className.contains('BottomNavigationBar') ||
        className.contains('NavigationRail')) {
      return 'navigation';
    } else if (className.contains('NavigationDestination') ||
               className.contains('BottomNavigationBarItem')) {
      return 'button'; // Nav items are interactive buttons
    } else if (className.contains('Button') || className.contains('Inkwell')) {
      return 'button';
    } else if (className.contains('Text') && !className.contains('Field')) {
      return 'text';
    } else if (className.contains('TextField') ||
        className.contains('EditableText') ||
        className == 'RenderEditable') {
      return 'input_field';
    } else if (className.contains('Image')) {
      return 'image';
    } else if (className.contains('Checkbox')) {
      return 'checkbox';
    } else if (className.contains('Radio')) {
      return 'radio_button';
    } else if (className.contains('Switch')) {
      return 'switch';
    } else if (className.contains('Slider')) {
      return 'seek_bar';
    } else if (className.contains('List')) {
      return 'list';
    } else if (className.contains('Grid') || className.contains('Masonry')) {
      return 'list';
    } else if (className.contains('Tab')) {
      return 'tab';
    } else if (className.contains('AppBar') || className.contains('ToolBar')) {
      return 'toolbar';
    } else if (className.contains('Progress') || className.contains('Indicator')) {
      return 'progress_bar';
    } else if (className.contains('Dialog')) {
      return 'dialog';
    } else if (className.contains('Card')) {
      return 'card';
    } else if (className.contains('Chip')) {
      return 'chip';
    } else if (className.contains('FloatingActionButton')) {
      return 'fab';
    } else if (className.contains('Scroll')) {
      return 'scroll_view';
    } else if (className.contains('PageView')) {
      return 'pager';
    }

    // Semantics-based fallback: catches wrapped text fields (e.g. ReactiveTextField)
    // when the render object class name isn't conclusive but semantics are available.
    try {
      final semantics = renderObject.debugSemantics;
      if (semantics != null &&
          semantics.getSemanticsData().hasFlag(SemanticsFlag.isTextField)) {
        return 'input_field';
      }
    } catch (_) {}

    return 'container';
  }

  /// Extract text content from RenderObject
  String? _extractText(RenderObject renderObject) {
    if (renderObject is RenderParagraph) {
      return renderObject.text.toPlainText();
    }
    return null;
  }

  /// Extract semantics label from RenderObject
  String? _extractSemanticsLabel(RenderObject renderObject) {
    try {
      // Try to get semantics from the render object
      final semantics = renderObject.debugSemantics;
      if (semantics != null) {
        // Combine label, value, and hint for better context
        final parts = <String>[];

        if (semantics.label.isNotEmpty) {
          parts.add(semantics.label);
        }

        if (semantics.value.isNotEmpty) {
          parts.add(semantics.value);
        }

        if (semantics.hint.isNotEmpty) {
          parts.add(semantics.hint);
        }

        if (parts.isNotEmpty) {
          return parts.join(' - ');
        }
      }
    } catch (e) {
      // Semantics might not be available in all contexts
    }
    return null;
  }

  /// Check if RenderObject is clickable (has gesture detector)
  bool _isClickable(RenderObject renderObject) {
    // Check if it's a common clickable widget type
    final className = renderObject.runtimeType.toString();

    if (className.contains('Button') ||
        className.contains('Inkwell') ||
        className.contains('GestureDetector') ||
        // GestureDetector produces RenderPointerListener in the render tree
        className.contains('PointerListener') ||
        className.contains('InkResponse') ||
        className.contains('NavigationDestination') ||
        className.contains('BottomNavigationBarItem')) {
      return true;
    }

    // Check for semantics that indicate tappability
    try {
      final semantics = renderObject.debugSemantics;
      if (semantics != null) {
        // Check if the semantics node has tap actions in its configuration
        return semantics.getSemanticsData().hasAction(SemanticsAction.tap);
      }
    } catch (e) {
      // Semantics might not be available
    }

    return false;
  }

  /// Check if RenderObject is scrollable
  bool _isScrollable(RenderObject renderObject) {
    final className = renderObject.runtimeType.toString();
    return renderObject is RenderViewport ||
        renderObject is RenderSliverList ||
        renderObject is RenderSliverGrid ||
        className.contains('Scroll') ||
        className.contains('Masonry') ||
        className.contains('SliverMasonry');
  }

  /// Check if RenderObject is visible
  bool _isVisible(RenderObject renderObject) {
    if (renderObject is RenderBox) {
      return renderObject.hasSize &&
             renderObject.size.width > 0 &&
             renderObject.size.height > 0;
    }
    return true;
  }

  /// Check if RenderObject is focusable
  bool _isFocusable(RenderObject renderObject) {
    final className = renderObject.runtimeType.toString();
    return className.contains('TextField') ||
        className.contains('Button') ||
        className.contains('Focusable') ||
        className == 'RenderEditable';
  }

  /// Extract additional properties from RenderObject
  Map<String, dynamic> _extractProperties(RenderObject renderObject) {
    final properties = <String, dynamic>{};

    if (renderObject is RenderBox && renderObject.hasSize) {
      properties['width'] = renderObject.size.width;
      properties['height'] = renderObject.size.height;
    }

    return properties;
  }

  /// Update child relationships in all elements
  void _updateChildRelationships() {
    _parentChildMap.forEach((parentId, childIds) {
      final parent = _elementsMap[parentId];
      if (parent != null) {
        _elementsMap[parentId] = FlutterUIElement(
          id: parent.id,
          type: parent.type,
          bounds: parent.bounds,
          text: parent.text,
          semanticsLabel: parent.semanticsLabel,
          className: parent.className,
          isClickable: parent.isClickable,
          isScrollable: parent.isScrollable,
          isEnabled: parent.isEnabled,
          isVisible: parent.isVisible,
          isFocusable: parent.isFocusable,
          isSelected: parent.isSelected,
          isChecked: parent.isChecked,
          hint: parent.hint,
          parentId: parent.parentId,
          children: childIds,
          depth: parent.depth,
          properties: parent.properties,
        );
      }
    });
  }

  /// Generate a unique ID for an element
  String _generateElementId() {
    return 'flutter_element_${++_idCounter}';
  }
}

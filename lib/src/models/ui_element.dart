import 'package:flutter/rendering.dart';

/// Represents a UI element detected in the Flutter widget tree
class FlutterUIElement {
  final String id;
  final String type;
  final Rect bounds;
  final String? text;
  final String? semanticsLabel;
  final String? className;
  final bool isClickable;
  final bool isScrollable;
  final bool isEnabled;
  final bool isVisible;
  final bool isFocusable;
  final bool isSelected;
  final bool? isChecked;
  final String? hint;
  final String? parentId;
  final List<String> children;
  final int depth;
  final Map<String, dynamic> properties;

  FlutterUIElement({
    required this.id,
    required this.type,
    required this.bounds,
    this.text,
    this.semanticsLabel,
    this.className,
    required this.isClickable,
    required this.isScrollable,
    required this.isEnabled,
    required this.isVisible,
    required this.isFocusable,
    required this.isSelected,
    this.isChecked,
    this.hint,
    this.parentId,
    this.children = const [],
    this.depth = 0,
    this.properties = const {},
  });

  /// Convert to JSON for passing to native Android
  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'id': id,
      'type': type,
      'bounds': {
        'left': bounds.left,
        'top': bounds.top,
        'right': bounds.right,
        'bottom': bounds.bottom,
        'width': bounds.width,
        'height': bounds.height,
      },
      'isClickable': isClickable,
      'isScrollable': isScrollable,
      'isEnabled': isEnabled,
      'isVisible': isVisible,
      'isFocusable': isFocusable,
      'isSelected': isSelected,
      'depth': depth,
    };
    if (text != null) map['text'] = text!;
    if (semanticsLabel != null) map['contentDescription'] = semanticsLabel!;
    if (className != null) map['className'] = className!;
    if (isChecked != null) map['isChecked'] = isChecked!;
    if (hint != null) map['hint'] = hint!;
    if (parentId != null) map['parentId'] = parentId!;
    if (children.isNotEmpty) map['children'] = children;
    if (properties.isNotEmpty) map['properties'] = properties;
    return map;
  }
}

/// A clickable UI element with all descendant text aggregated for easy identification.
///
/// Use [Vable.clickableElements] to access the latest list after a scan,
/// and [Vable.triggerElement] to simulate a tap on one.
class ClickableElement {
  /// The element ID from the scan — use this with [Vable.triggerElement].
  final String id;

  /// Render object type (e.g. 'list', 'button', 'image').
  final String type;

  /// Global bounds of the element on screen.
  final Rect bounds;

  /// All text found in this element and its descendants, space-joined.
  final String label;

  /// Widget tree depth of this element.
  final int depth;

  ClickableElement({
    required this.id,
    required this.type,
    required this.bounds,
    required this.label,
    required this.depth,
  });

  /// Center of the element in global screen coordinates — used for tap simulation.
  Offset get center => bounds.center;

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'bounds': {
          'left': bounds.left,
          'top': bounds.top,
          'right': bounds.right,
          'bottom': bounds.bottom,
        },
        'label': label,
        'center': {'x': center.dx, 'y': center.dy},
        'depth': depth,
      };

  @override
  String toString() =>
      'ClickableElement(id: $id, type: $type, label: "$label", center: (${center.dx.toStringAsFixed(1)}, ${center.dy.toStringAsFixed(1)}))';
}

/// An input UI element (text field, search bar, etc.) identified during a scan.
///
/// Use [Vable.inputElements] to access the latest list after a scan.
class InputElement {
  /// The element ID from the scan — use this with the `inputText` tool.
  final String id;

  /// Render object type (e.g. 'input_field').
  final String type;

  /// Global bounds of the element on screen.
  final Rect bounds;

  /// Hint text, semantics label, or current value that identifies the field.
  final String label;

  /// Widget tree depth of this element.
  final int depth;

  InputElement({
    required this.id,
    required this.type,
    required this.bounds,
    required this.label,
    required this.depth,
  });

  /// Center of the element in global screen coordinates.
  Offset get center => bounds.center;

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'bounds': {
          'left': bounds.left,
          'top': bounds.top,
          'right': bounds.right,
          'bottom': bounds.bottom,
        },
        'label': label,
        'center': {'x': center.dx, 'y': center.dy},
        'depth': depth,
      };

  @override
  String toString() =>
      'InputElement(id: $id, type: $type, label: "$label", center: (${center.dx.toStringAsFixed(1)}, ${center.dy.toStringAsFixed(1)}))';
}

/// Represents the complete Flutter screen state
class FlutterScreenState {
  final int timestamp;
  final List<FlutterUIElement> elements;
  final Size screenSize;
  final String? routeName;
  final Map<String, dynamic> metadata;

  FlutterScreenState({
    required this.timestamp,
    required this.elements,
    required this.screenSize,
    this.routeName,
    this.metadata = const {},
  });

  /// Convert to JSON for passing to native Android
  Map<String, dynamic> toJson() {
    final screen = <String, dynamic>{
      'bounds': {
        'width': screenSize.width,
        'height': screenSize.height,
      },
    };
    if (routeName != null) screen['route'] = routeName!;

    final map = <String, dynamic>{
      'timestamp': timestamp,
      'screen': screen,
      'elementCount': elements.length,
    };
    if (elements.isNotEmpty) map['elements'] = elements.map((e) => e.toJson()).toList();
    if (metadata.isNotEmpty) map['metadata'] = metadata;
    return map;
  }
}

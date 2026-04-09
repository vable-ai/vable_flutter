import 'package:flutter/material.dart';
import 'screen_scanner_manager.dart';
import '../vable_flutter.dart';

/// NavigatorObserver that tracks the current screen context and updates
/// both the ScreenScannerManager and Vable navigation context automatically.
///
/// Add this to your MaterialApp's navigatorObservers to enable automatic
/// context tracking for screen scanning and AI-driven navigation.
///
/// Example:
/// ```dart
/// MaterialApp(
///   navigatorObservers: [VableNavigatorObserver()],
///   // ...
/// )
/// ```
class VableNavigatorObserver extends NavigatorObserver {
  BuildContext? _currentContext;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    _updateContext(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    if (previousRoute != null) {
      _updateContext(previousRoute);
    }
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    if (newRoute != null) {
      _updateContext(newRoute);
    }
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didRemove(route, previousRoute);
    if (previousRoute != null) {
      _updateContext(previousRoute);
    }
  }

  void _updateContext(Route route) {
    // Wait for the next frame to ensure the route is fully mounted
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (route.navigator?.context != null) {
        _currentContext = route.navigator!.context;

        // Update screen scanner context
        ScreenScannerManager().updateContext(_currentContext!);

        // Update navigation context for AI-driven navigation
        Vable.updateNavigationContext(_currentContext!);

        debugPrint('[VableFlutter] Navigator context updated');
      }
    });
  }

  /// Get the current context (may be null if no routes exist)
  BuildContext? get currentContext => _currentContext;
}

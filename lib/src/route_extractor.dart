import 'package:flutter/widgets.dart';
import 'models/context_models.dart';

/// Helper class to extract routes from a Flutter application
class VableRouteExtractor {
  /// Extract routes from a routes map (typically from MaterialApp.routes)
  ///
  /// Example:
  /// ```dart
  /// final routes = {
  ///   '/': (context) => HomePage(),
  ///   '/profile': (context) => ProfilePage(),
  ///   '/settings': (context) => SettingsPage(),
  /// };
  ///
  /// final vableRoutes = VableRouteExtractor.fromRoutesMap(routes);
  /// ```
  static List<VableRoute> fromRoutesMap(Map<String, WidgetBuilder> routes) {
    return routes.keys.map((path) {
      // Try to extract a clean name from the path
      final name = _extractNameFromPath(path);
      return VableRoute(path: path, name: name);
    }).toList();
  }

  /// Extract routes from a list of RouteSettings
  ///
  /// This can be used with a custom RouteObserver or route generator
  static List<VableRoute> fromRouteSettings(List<RouteSettings> settings) {
    return settings
        .where((s) => s.name != null)
        .map((s) => VableRoute(path: s.name!, name: s.name))
        .toList();
  }

  /// Manually create a list of routes
  ///
  /// Use this when you want to explicitly define the routes to send to Vable
  ///
  /// Example:
  /// ```dart
  /// final routes = VableRouteExtractor.create([
  ///   VableRoute(path: '/', name: 'Home'),
  ///   VableRoute(path: '/profile', name: 'Profile'),
  ///   VableRoute(path: '/settings', name: 'Settings'),
  /// ]);
  /// ```
  static List<VableRoute> create(List<VableRoute> routes) {
    return routes;
  }

  /// Extract a readable name from a route path
  ///
  /// Examples:
  /// - "/" -> "Home"
  /// - "/profile" -> "Profile"
  /// - "/user/settings" -> "User Settings"
  static String? _extractNameFromPath(String path) {
    if (path == '/') {
      return 'Home';
    }

    // Remove leading slash and split by slashes
    final parts = path.substring(1).split('/');

    // Capitalize first letter of each part and join with spaces
    return parts
        .map((part) {
          if (part.isEmpty) return '';
          // Handle camelCase and snake_case
          final words = part
              .replaceAllMapped(
                RegExp(r'([A-Z])'),
                (match) => ' ${match.group(1)}',
              )
              .replaceAll('_', ' ')
              .split(' ')
              .where((w) => w.isNotEmpty);

          return words
              .map((w) => w[0].toUpperCase() + w.substring(1).toLowerCase())
              .join(' ');
        })
        .join(' ')
        .trim();
  }
}

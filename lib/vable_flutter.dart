import 'package:flutter/material.dart';
import 'package:vable_flutter/src/models/ui_element.dart';
import 'vable_flutter_platform_interface.dart';
import 'src/screen_scanner_manager.dart';
import 'src/models/context_models.dart';
import 'src/route_extractor.dart';

// Export screen scanner for advanced use cases
export 'src/screen_scanner_manager.dart';
export 'src/vable_navigator_observer.dart';
export 'src/models/ui_element.dart';
export 'src/models/context_models.dart';
export 'src/route_extractor.dart';

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
  /// ```
  ///
  /// [publicKey] Your Vable public key for authentication.
  /// [routes] Optional list of app routes to send to the AI agent.
  /// Returns true if initialization was successful.
  /// Throws an Exception if initialization fails.
  static Future<bool> initialize(
    String publicKey, {
    List<VableRoute>? routes,
    String? environment,
  }) async {
    final result = await VableFlutterPlatform.instance.initialize(publicKey, environment: environment);

    debugPrint('Vable initialized with routes ${routes?.length}');
    // If routes are provided, store and send them to the AI agent
    if (result && routes != null && routes.isNotEmpty) {
      _routes = List.of(routes);
      _screenScannerManager.updateRoutes(_routes);
      try {
        await updateIntents(VableContextUpdate(routes: routes));
      } catch (e) {
        // Log error but don't fail initialization
        debugPrint('Warning: Failed to send routes during initialization: $e');
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
    final result = await VableFlutterPlatform.instance.startVoiceChat();

    if (result && context.mounted) {
      // Store the Navigator's context for navigation (never unmounts)
      final navigatorContext = Navigator.maybeOf(context)?.context;
      _navigationContext = navigatorContext ?? context;

      // Start automatic screen scanning when voice chat begins
      _screenScannerManager.startScanning(
        context: context,
        scanInterval: const Duration(seconds: 3),
      );
    }

    return result;
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
    // Stop screen scanning
    _screenScannerManager.stopScanning();

    // Clear navigation context
    _navigationContext = null;

    return VableFlutterPlatform.instance.endVoiceChat();
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
  static Future<bool> updateIntents(VableContextUpdate contextUpdate) {
    return VableFlutterPlatform.instance.updateIntents(contextUpdate.toJson());
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
  static void configureRouter({
    required VableRoutingLibrary library,
    dynamic router,
    bool autoExtractRoutes = true,
  }) {
    try {
      _routingLibrary = library;
      _routerInstance = router;

      debugPrint('[VableFlutter] Router configured: ${library.name}');

      if (library != VableRoutingLibrary.native && router == null) {
        debugPrint('[VableFlutter] ⚠️ Warning: Router instance not provided for ${library.name}');
        debugPrint('[VableFlutter] Navigation will fail until router is set');
      }

      // Basic validation - try to access router without calling methods
      if (router != null) {
        debugPrint('[VableFlutter] ✓ Router instance provided');

        // Auto-extract routes if enabled
        if (autoExtractRoutes) {
          _autoExtractAndSendRoutes(library, router);
        } else {
          debugPrint('[VableFlutter] Route auto-extraction disabled');
        }
      }
    } catch (e) {
      debugPrint('[VableFlutter] ❌ Error configuring router: $e');
      debugPrint('[VableFlutter] This usually means the router is not initialized yet');
      debugPrint('[VableFlutter] Ensure your router/DI is set up before calling configureRouter()');

      // Reset to native to prevent crashes
      _routingLibrary = VableRoutingLibrary.native;
      _routerInstance = null;
    }
  }

  /// Automatically extract routes from router instance and send to AI
  static void _autoExtractAndSendRoutes(VableRoutingLibrary library, dynamic router) {
    try {
      debugPrint('[VableFlutter] Attempting to auto-extract routes from ${library.name}...');

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
          debugPrint('[VableFlutter] Native router - routes should be provided in initialize()');
          break;
      }

      if (extractedRoutes != null && extractedRoutes.isNotEmpty) {
        debugPrint('[VableFlutter] ✓ Extracted ${extractedRoutes.length} routes');

        // Store globally, sync to scanner manager, and send to AI
        _routes = List.of(extractedRoutes);
        _screenScannerManager.updateRoutes(_routes);
        updateIntents(VableContextUpdate(routes: extractedRoutes)).then((_) {
          debugPrint('[VableFlutter] ✓ Routes sent to AI agent');
        }).catchError((e) {
          debugPrint('[VableFlutter] ⚠️ Failed to send routes to AI: $e');
        });
      } else {
        debugPrint('[VableFlutter] No routes extracted - you may need to provide them manually');
      }
    } catch (e) {
      debugPrint('[VableFlutter] ⚠️ Failed to auto-extract routes: $e');
      debugPrint('[VableFlutter] You can provide routes manually in initialize()');
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
        debugPrint('[VableFlutter] routes property not accessible: ${e.toString().split('\n')[0]}');
      }

      // Method 2: Try accessing config
      try {
        final config = router.config;
        if (config != null && config.routes != null) {
          return _parseAutoRouteConfig(config.routes);
        }
      } catch (e) {
        debugPrint('[VableFlutter] config.routes not accessible: ${e.toString().split('\n')[0]}');
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
        debugPrint('[VableFlutter] matcher.routes not accessible: ${e.toString().split('\n')[0]}');
      }

      debugPrint('[VableFlutter] Could not extract routes from AutoRoute router');
      return null;
    } catch (e) {
      debugPrint('[VableFlutter] Error extracting AutoRoute routes: $e');
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

                debugPrint('[VableFlutter] Extracted route: $fullPath ${name != null ? "($name)" : ""}');
              }

              // Recursively extract child routes
              if (_hasChildren(route)) {
                try {
                  final children = route.children;
                  if (children != null) {
                    final childRoutes = _parseAutoRouteConfig(children.routes, parentPath: fullPath);
                    vableRoutes.addAll(childRoutes);
                  }
                } catch (e) {
                  debugPrint('[VableFlutter] Could not extract children: ${e.toString().split('\n')[0]}');
                }
              }
            }
          } catch (e) {
            // Skip this route if we can't parse it
            debugPrint('[VableFlutter] Could not parse route: ${e.toString().split('\n')[0]}');
          }
        }
      }
    } catch (e) {
      debugPrint('[VableFlutter] Error parsing route config: $e');
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

      debugPrint('[VableFlutter] Could not extract routes from GoRouter');
      return null;
    } catch (e) {
      debugPrint('[VableFlutter] Error extracting GoRouter routes: $e');
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

              debugPrint('[VableFlutter] Extracted GoRouter route: $path ${name != null ? "($name)" : ""}');

              // Recursively extract child routes
              if (route.routes != null && route.routes is List) {
                final childRoutes = _parseGoRouterConfig(route.routes);
                vableRoutes.addAll(childRoutes);
              }
            }
          } catch (e) {
            debugPrint('[VableFlutter] Could not parse GoRouter route: ${e.toString().split('\n')[0]}');
          }
        }
      }
    } catch (e) {
      debugPrint('[VableFlutter] Error parsing GoRouter config: $e');
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
    debugPrint('[VableFlutter] Navigation callback ${callback != null ? "registered" : "unregistered"}');
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
    debugPrint('[VableFlutter] Navigation context updated');
  }

  /// Internal method to handle navigation events from the native side.
  /// Called by the platform implementation when the AI agent requests navigation.
  static void handleNavigationEvent(String url) async {
    debugPrint('[VableFlutter] Navigation event received: $url');

    // Priority 1: Custom callback (complete override)
    if (_navigationCallback != null) {
      debugPrint('[VableFlutter] Using custom navigation callback');
      try {
        _navigationCallback!(url);
        debugPrint('[VableFlutter] ✓ Successfully navigated to $url');
      } catch (e) {
        debugPrint('[VableFlutter] ❌ Error in custom navigation callback: $e');
      }
      return;
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
      default:
      navigated = _navigateWithNativeRouter(url);
        break;
    }

    await Future.delayed(Duration(seconds: 1));
    sendToolResult(toolName: "navigate", result: "Navigated: $navigated");
  }

  /// Navigate using GoRouter (go_router package)
  static bool _navigateWithGoRouter(String url) {
    debugPrint('[VableFlutter] Using GoRouter for navigation');

    if (_routerInstance == null) {
      debugPrint('[VableFlutter] ❌ GoRouter instance not configured');
      debugPrint('[VableFlutter] Call: Vable.configureRouter(library: VableRoutingLibrary.goRouter, router: yourRouter)');
      return false;
    }

    try {
      // Try using go() method (preferred for GoRouter)
      _routerInstance.go(url);
      debugPrint('[VableFlutter] ✓ Successfully navigated to $url using GoRouter.go()');
      return true;
    } catch (e) {
      // Fallback to push() method
      try {
        _routerInstance.push(url);
        debugPrint('[VableFlutter] ✓ Successfully navigated to $url using GoRouter.push()');
        return true;
      } catch (e2) {
        debugPrint('[VableFlutter] ❌ Error navigating with GoRouter: $e');
        debugPrint('[VableFlutter] Ensure your GoRouter has route "$url" defined');
      }

      return false;
    }
  }

  /// Navigate using AutoRoute (auto_route package)
  static Future<bool> _navigateWithAutoRoute(String url) async {
    debugPrint('[VableFlutter] Using AutoRoute for navigation');

    if (_routerInstance == null) {
      debugPrint('[VableFlutter] ❌ AutoRoute instance not configured');
      debugPrint('[VableFlutter] ');
      debugPrint('[VableFlutter] AutoRoute requires special setup. Use callback instead:');
      debugPrint('[VableFlutter] ');
      debugPrint('[VableFlutter] // After DI is configured');
      debugPrint('[VableFlutter] Vable.setNavigationCallback((url) {');
      debugPrint('[VableFlutter]   final router = getIt<AppRouter>(); // or your DI method');
      debugPrint('[VableFlutter]   switch (url) {');
      debugPrint('[VableFlutter]     case "/account":');
      debugPrint('[VableFlutter]       router.push(const AccountRoute());');
      debugPrint('[VableFlutter]       break;');
      debugPrint('[VableFlutter]   }');
      debugPrint('[VableFlutter] });');
      return false;
    }

    if (_navigationContext == null || !_navigationContext!.mounted) {
      debugPrint('[VableFlutter] ❌ Navigation context unavailable for AutoRoute');
      debugPrint('[VableFlutter] Ensure startVoiceChat() was called with a valid context');
      return false;
    }

    // Wrap all AutoRoute navigation attempts in a big try-catch to prevent freezing
    try {
      bool navigated = false;

      // Try method 1: navigateNamed with onFailure callback
      if (!navigated) {
        try {
          bool failed = false;
          await _routerInstance.navigateNamed(
            url,
            onFailure: (failure) {
              debugPrint('[VableFlutter] navigateNamed() failed: $failure');
              failed = true;
            },
          );
          if (!failed) {
            debugPrint('[VableFlutter] ✓ Successfully navigated to $url using AutoRoute.navigateNamed().');
            navigated = true;
          }
        } catch (e) {
          // Method not available or failed, continue
          debugPrint('[VableFlutter] navigateNamed() not available: ${e.toString().split('\n')[0]}');
        }
      }

      // Try method 2: pushNamed (more common in AutoRoute)
      if (!navigated) {
        try {
          final result = _routerInstance.pushNamed(url);
          if (result != null) {
            debugPrint('[VableFlutter] ✓ Successfully navigated to $url using AutoRoute.pushNamed()');
            navigated = true;
          }
        } catch (e) {
          debugPrint('[VableFlutter] pushNamed() not available: ${e.toString().split('\n')[0]}');
        }
      }

      // Try method 3: push with path string (fallback)
      if (!navigated) {
        try {
          final result = _routerInstance.push(url);
          if (result != null) {
            debugPrint('[VableFlutter] ✓ Successfully navigated to $url using AutoRoute.push()');
            navigated = true;
          }
        } catch (e) {
          debugPrint('[VableFlutter] push() not available: ${e.toString().split('\n')[0]}');
        }
      }

      // If all methods fail, provide helpful error
      if (!navigated) {
        debugPrint('[VableFlutter] ❌ Could not navigate with AutoRoute');
        debugPrint('[VableFlutter] ');
        debugPrint('[VableFlutter] AutoRoute uses code generation and doesn\'t support string-based navigation well.');
        debugPrint('[VableFlutter] Use a custom callback instead:');
        debugPrint('[VableFlutter] ');
        debugPrint('[VableFlutter] Vable.setNavigationCallback((url) {');
        debugPrint('[VableFlutter]   final router = getIt<AppRouter>();');
        debugPrint('[VableFlutter]   switch (url) {');
        debugPrint('[VableFlutter]     case "/account":');
        debugPrint('[VableFlutter]       router.push(const AccountRoute());');
        debugPrint('[VableFlutter]       break;');
        debugPrint('[VableFlutter]   }');
        debugPrint('[VableFlutter] });');
      }
      return navigated;
    } catch (e, stackTrace) {
      debugPrint('[VableFlutter] ❌ Fatal error navigating with AutoRoute: $e');
      debugPrint('[VableFlutter] This might be a router initialization issue');
      debugPrint('[VableFlutter] Stack trace: ${stackTrace.toString().split('\n').take(3).join('\n')}');
      return false;
    }
  }

  /// Navigate using native Flutter Navigator
  static bool _navigateWithNativeRouter(String url) {
    debugPrint('[VableFlutter] Using native Flutter Navigator');

    if (_navigationContext == null || !_navigationContext!.mounted) {
      debugPrint('[VableFlutter] ❌ Navigation context unavailable');
      debugPrint('[VableFlutter] Ensure startVoiceChat() was called with a valid context');
      return false;
    }

    try {
      Navigator.of(_navigationContext!).pushNamed(url);
      debugPrint('[VableFlutter] ✓ Successfully navigated to $url');
      return true;
    } catch (e) {
      debugPrint('[VableFlutter] ❌ Error navigating to $url: $e');
      debugPrint('[VableFlutter] ');
      debugPrint('[VableFlutter] 📋 To fix this, choose one of these options:');
      debugPrint('[VableFlutter] ');
      debugPrint('[VableFlutter] Option 1 - Configure routes in MaterialApp:');
      debugPrint('[VableFlutter] MaterialApp(');
      debugPrint('[VableFlutter]   routes: {');
      debugPrint('[VableFlutter]     "$url": (context) => YourPage(),');
      debugPrint('[VableFlutter]   },');
      debugPrint('[VableFlutter] )');
      debugPrint('[VableFlutter] ');
      debugPrint('[VableFlutter] Option 2 - Use onGenerateRoute:');
      debugPrint('[VableFlutter] MaterialApp(');
      debugPrint('[VableFlutter]   onGenerateRoute: (settings) {');
      debugPrint('[VableFlutter]     if (settings.name == "$url") {');
      debugPrint('[VableFlutter]       return MaterialPageRoute(builder: (_) => YourPage());');
      debugPrint('[VableFlutter]     }');
      debugPrint('[VableFlutter]   },');
      debugPrint('[VableFlutter] )');
      debugPrint('[VableFlutter] ');
      debugPrint('[VableFlutter] Option 3 - Configure routing library (GoRouter/AutoRoute):');
      debugPrint('[VableFlutter] Vable.configureRouter(');
      debugPrint('[VableFlutter]   library: VableRoutingLibrary.goRouter,');
      debugPrint('[VableFlutter]   router: yourGoRouter,');
      debugPrint('[VableFlutter] );');
      return false;
    }
  }
}

# AI-Driven Navigation Guide

This guide explains how to enable AI-driven navigation in your Flutter app using the Vable SDK. The AI agent can automatically navigate your app based on voice commands.

## Table of Contents

- [Overview](#overview)
- [How It Works](#how-it-works)
- [Setup by Routing Library](#setup-by-routing-library)
  - [Native Flutter Navigator (Default)](#1-native-flutter-navigator-default)
  - [GoRouter](#2-gorouter)
  - [AutoRoute](#3-autoroute)
  - [Custom Callback](#4-custom-callback-any-router)
- [Providing Routes to the AI](#providing-routes-to-the-ai)
- [Testing Navigation](#testing-navigation)
- [Troubleshooting](#troubleshooting)
- [API Reference](#api-reference)

---

## Overview

When a user speaks to the Vable AI assistant, the AI can understand navigation intents and trigger route changes in your app. For example:

- User says: "Show me my account settings"
- AI understands: Navigate to `/account`
- Your app: Navigates to the AccountPage

The SDK supports multiple routing libraries without requiring them as dependencies.

---

## How It Works

### Flow Diagram

```
User Voice Command
    ↓
AI Agent Processing
    ↓
Navigate Tool Use: {"toolUse":[{"name":"navigate","input":{"url":"/account"}}]}
    ↓
Android Native SDK (VoiceChatController)
    ↓
Flutter Plugin (VableFlutterPlugin)
    ↓
Vable.handleNavigationEvent("/account")
    ↓
[Routing Library Handler]
    ↓
Your App Navigates
```

### Priority System

The SDK uses this priority order for navigation:

1. **Custom Callback** (if set via `setNavigationCallback`)
2. **Configured Router** (set via `configureRouter`)
3. **Native Navigator** (default, uses `Navigator.pushNamed`)

---

## Setup by Routing Library

### 1. Native Flutter Navigator (Default)

**No configuration needed!** Just define your routes in `MaterialApp`.

#### Step 1: Define Routes

```dart
import 'package:flutter/material.dart';
import 'package:vable_flutter/vable_flutter.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Vable
  await Vable.initialize('your-public-key');

  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      routes: {
        '/': (context) => HomePage(),
        '/account': (context) => AccountPage(),
        '/settings': (context) => SettingsPage(),
        '/profile': (context) => ProfilePage(),
      },
      // Optional: Better context tracking for navigation
      navigatorObservers: [VableNavigatorObserver()],
    );
  }
}
```

#### Alternative: Using onGenerateRoute

```dart
MaterialApp(
  onGenerateRoute: (settings) {
    switch (settings.name) {
      case '/':
        return MaterialPageRoute(builder: (_) => HomePage());
      case '/account':
        return MaterialPageRoute(builder: (_) => AccountPage());
      case '/settings':
        return MaterialPageRoute(builder: (_) => SettingsPage());
      default:
        return MaterialPageRoute(builder: (_) => NotFoundPage());
    }
  },
)
```

#### Step 2: Start Voice Chat

```dart
// In your HomePage or wherever you want to enable voice chat
ElevatedButton(
  onPressed: () async {
    await Vable.startVoiceChat(context);
  },
  child: Text('Start Voice Chat'),
)
```

That's it! AI navigation now works automatically.

---

### 2. GoRouter

For apps using the `go_router` package.

#### Step 1: Create Your GoRouter

```dart
import 'package:go_router/go_router.dart';
import 'package:vable_flutter/vable_flutter.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Create your GoRouter
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => HomePage(),
      ),
      GoRoute(
        path: '/account',
        builder: (context, state) => AccountPage(),
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => SettingsPage(),
      ),
      GoRoute(
        path: '/profile',
        builder: (context, state) => ProfilePage(),
      ),
    ],
  );

  // Configure Vable to use GoRouter
  Vable.configureRouter(
    library: VableRoutingLibrary.goRouter,
    router: router,
  );

  // Initialize Vable with routes
  final routes = [
    VableRoute(path: '/', name: 'Home'),
    VableRoute(path: '/account', name: 'Account'),
    VableRoute(path: '/settings', name: 'Settings'),
    VableRoute(path: '/profile', name: 'Profile'),
  ];

  await Vable.initialize('your-public-key', routes: routes);

  runApp(MyApp(router: router));
}
```

#### Step 2: Use GoRouter in MaterialApp

```dart
class MyApp extends StatelessWidget {
  final GoRouter router;

  const MyApp({required this.router});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      routerConfig: router,
    );
  }
}
```

#### Step 3: Start Voice Chat

```dart
await Vable.startVoiceChat(context);
```

The AI will now use `router.go(url)` to navigate!

#### GoRouter Notes

- The SDK tries `router.go(url)` first (replaces current route)
- Falls back to `router.push(url)` if `go()` fails (pushes onto stack)
- Use `go()` for root-level navigation, `push()` for stacked navigation

---

### 3. AutoRoute

For apps using the `auto_route` package.

#### ⚠️ CRITICAL: Initialization Order Issue

**DO NOT use `configureRouter` with AutoRoute if your router comes from dependency injection (GetIt, etc.)!**

This will cause your app to freeze:
```dart
// ❌ BAD - Will freeze if appRouter uses DI
final AppRouter appRouter = getIt<AppRouter>();  // DI not ready yet!

void main() async {
  Vable.configureRouter(                           // Called before DI setup
    library: VableRoutingLibrary.autoRoute,
    router: appRouter,  // ❌ Accessing uninitialized DI - FREEZE!
  );

  configureDependencyInjection();  // Too late!
}
```

**Use custom callback instead** - it's safer and more reliable for AutoRoute.

#### Recommended Approach: Custom Callback with Auto-Extraction

```dart
import 'package:auto_route/auto_route.dart';
import 'package:vable_flutter/vable_flutter.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Vable (no manual routes needed!)
  await Vable.initialize('your-public-key');

  // Configure DI or get your router ready
  configureDependencyInjection(); // If using DI

  final router = getIt<AppRouter>(); // Or however you get your router

  // Configure router - routes are automatically extracted! ✨
  Vable.configureRouter(
    library: VableRoutingLibrary.autoRoute,
    router: router,
    // Routes automatically extracted from your router!
  );

  // Set up navigation callback
  Vable.setNavigationCallback((url) {
    final router = getIt<AppRouter>(); // Get router when navigating

    switch (url) {
      case '/':
        router.push(const HomeRoute());
        break;
      case '/account':
        router.push(const AccountRoute());
        break;
      case '/settings':
        router.push(const SettingsRoute());
        break;
      case '/profile':
        router.push(const ProfileRoute());
        break;
      default:
        debugPrint('Unknown route: $url');
    }
  });

  runApp(MyApp());
}
```

#### Getting Context for Callback

**Option A: Store context from startVoiceChat**

```dart
BuildContext? _appContext;

// When starting voice chat
await Vable.startVoiceChat(context);
_appContext = context;

// In callback
Vable.setNavigationCallback((url) {
  if (_appContext != null) {
    switch (url) {
      case '/account':
        _appContext!.router.push(const AccountRoute());
        break;
      // ...
    }
  }
});
```

**Option B: Use global navigator key (AutoRoute pattern)**

```dart
final appRouter = AppRouter();

void main() {
  Vable.setNavigationCallback((url) {
    switch (url) {
      case '/account':
        appRouter.push(const AccountRoute());
        break;
      // ...
    }
  });

  runApp(MyApp(router: appRouter));
}

class MyApp extends StatelessWidget {
  final AppRouter router;

  MyApp({required this.router});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      routerDelegate: router.delegate(),
      routeInformationParser: router.defaultRouteParser(),
    );
  }
}
```

#### Alternative: configureRouter (May Have Limitations)

If you still want to try `configureRouter`:

```dart
final router = AppRouter();

Vable.configureRouter(
  library: VableRoutingLibrary.autoRoute,
  router: router,
);
```

**Note**: This may not work with all AutoRoute versions due to code generation. The custom callback approach is more reliable.

---

### 4. Custom Callback (Any Router)

For complete control or unsupported routing libraries.

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Vable.initialize('your-public-key');

  // Set up custom navigation handler
  Vable.setNavigationCallback((url) {
    // Your custom navigation logic
    debugPrint('Navigating to: $url');

    // Example: Custom router
    MyCustomRouter.instance.navigateTo(url);

    // Example: Conditional navigation
    if (url.startsWith('/external/')) {
      // Handle external URLs differently
      launchUrl(url);
    } else {
      // Regular app navigation
      MyRouter.push(url);
    }
  });

  runApp(MyApp());
}
```

---

## 🆕 Automatic Route Extraction

**NEW**: Vable can now automatically extract routes from your router instance!

### Supported Routers

- ✅ **AutoRoute** - Extracts routes from router configuration
- ✅ **GoRouter** - Extracts routes including child routes
- ❌ **Native Navigator** - Routes must be provided manually

### How It Works

When you call `Vable.configureRouter()` with a router instance, the SDK:

1. **Accesses** your router's route configuration
2. **Extracts** all route paths (e.g., `/account`, `/settings`)
3. **Generates** human-readable names from paths (e.g., "Account", "Settings")
4. **Sends** the routes to the AI agent automatically

### Example with AutoRoute

```dart
// No manual route definition needed!
await Vable.initialize('your-public-key');

// After your router is initialized
final router = getIt<AppRouter>();

// Routes are automatically extracted and sent to AI
Vable.configureRouter(
  library: VableRoutingLibrary.autoRoute,
  router: router,
);
```

You'll see in logs:
```
[VableFlutter] Attempting to auto-extract routes from autoRoute...
[VableFlutter] Extracted route: /account (Account)
[VableFlutter] Extracted route: /settings (Settings)
[VableFlutter] ✓ Extracted 2 routes
[VableFlutter] ✓ Routes sent to AI agent
```

### Example with GoRouter

```dart
final router = GoRouter(
  routes: [
    GoRoute(path: '/', builder: (_, __) => HomePage()),
    GoRoute(path: '/account', builder: (_, __) => AccountPage()),
  ],
);

// Routes automatically extracted
Vable.configureRouter(
  library: VableRoutingLibrary.goRouter,
  router: router,
);
```

### Disabling Auto-Extraction

If you prefer to provide routes manually:

```dart
Vable.configureRouter(
  library: VableRoutingLibrary.autoRoute,
  router: router,
  autoExtractRoutes: false, // Disable
);

// Provide routes manually instead
await Vable.initialize('key', routes: [
  VableRoute(path: '/account', name: 'Account'),
]);
```

### Benefits

✅ **No duplication** - Don't maintain routes in two places
✅ **Always accurate** - Routes are extracted at runtime
✅ **Less code** - Fewer lines to maintain
✅ **Auto-updates** - Changes to your router are automatically reflected

---

## Providing Routes to the AI

For the AI to navigate effectively, it needs to know your app's routes.

### Define Routes During Initialization

```dart
final routes = [
  VableRoute(path: '/', name: 'Home'),
  VableRoute(path: '/account', name: 'Account Settings'),
  VableRoute(path: '/settings', name: 'App Settings'),
  VableRoute(path: '/profile', name: 'User Profile'),
  VableRoute(path: '/orders', name: 'My Orders'),
  VableRoute(path: '/orders/:id', name: 'Order Details'),
];

await Vable.initialize('your-public-key', routes: routes);
```

### Using VableRouteExtractor

Convert existing route definitions:

```dart
// From a routes map
final routesMap = {
  '/': 'Home',
  '/account': 'Account',
  '/settings': 'Settings',
};
final routes = VableRouteExtractor.fromRoutesMap(routesMap);

await Vable.initialize('your-public-key', routes: routes);
```

### Routes with Parameters

```dart
VableRoute(path: '/product/:id', name: 'Product Details')
VableRoute(path: '/user/:userId/posts', name: 'User Posts')
```

The AI can navigate to: `/product/123`, `/user/456/posts`, etc.

---

## Testing Navigation

### Test Setup

1. **Configure your router** (if not using native Navigator)
2. **Define routes** in your MaterialApp or router
3. **Provide routes** to Vable during initialization
4. **Start voice chat** with `Vable.startVoiceChat(context)`

### Test Commands

Try these voice commands:

- "Show me my account"
- "Take me to settings"
- "Open my profile"
- "Go to the home page"
- "Navigate to account settings"

### Check Logs

Look for these log messages:

```
[VableFlutter] Navigation event received: /account
[VableFlutter] Using GoRouter for navigation
[VableFlutter] ✓ Successfully navigated to /account using GoRouter.go()
```

Or for errors:

```
[VableFlutter] ❌ Error navigating to /account: Navigator.onGenerateRoute was null
[VableFlutter] 📋 To fix this, configure routes in your MaterialApp:
```

---

## Troubleshooting

### Problem: "Navigator.onGenerateRoute was null"

**Solution**: Define routes in your MaterialApp:

```dart
MaterialApp(
  routes: {
    '/account': (context) => AccountPage(),
  },
)
```

### Problem: "Navigation context unavailable"

**Solution**: Ensure `startVoiceChat()` was called before AI navigation:

```dart
await Vable.startVoiceChat(context);
```

### Problem: AutoRoute causes app to freeze

**Solution**: Use custom callback instead of `configureRouter`:

```dart
Vable.setNavigationCallback((url) {
  switch (url) {
    case '/account':
      context.router.push(const AccountRoute());
      break;
  }
});
```

### Problem: GoRouter navigation not working

**Solution**: Ensure router instance is passed to `configureRouter`:

```dart
Vable.configureRouter(
  library: VableRoutingLibrary.goRouter,
  router: yourGoRouterInstance, // Don't forget this!
);
```

### Problem: AI doesn't know about my routes

**Solution**: Provide routes during initialization:

```dart
await Vable.initialize('key', routes: [
  VableRoute(path: '/account', name: 'Account'),
]);
```

---

## API Reference

### VableRoutingLibrary Enum

```dart
enum VableRoutingLibrary {
  native,     // Default Flutter Navigator
  goRouter,   // GoRouter package
  autoRoute,  // AutoRoute package
}
```

### configureRouter()

Configure which routing library to use.

```dart
static void configureRouter({
  required VableRoutingLibrary library,
  dynamic router,
})
```

**Parameters:**
- `library`: The routing library you're using
- `router`: The router instance (e.g., GoRouter, AppRouter)

**Example:**
```dart
Vable.configureRouter(
  library: VableRoutingLibrary.goRouter,
  router: myGoRouter,
);
```

### setNavigationCallback()

Set a custom navigation handler.

```dart
static void setNavigationCallback(VableNavigationCallback? callback)
```

**Parameters:**
- `callback`: Function that receives a URL string and handles navigation

**Example:**
```dart
Vable.setNavigationCallback((url) {
  // Custom navigation logic
  myRouter.navigateTo(url);
});
```

### VableRoute

Model for defining app routes.

```dart
class VableRoute {
  final String path;    // Route path (e.g., "/account")
  final String? name;   // Human-readable name (e.g., "Account Settings")
}
```

**Example:**
```dart
VableRoute(path: '/account', name: 'Account Settings')
```

---

## Best Practices

### 1. Always Provide Routes to the AI

```dart
// Good
await Vable.initialize('key', routes: myRoutes);

// Bad
await Vable.initialize('key'); // AI won't know where it can navigate
```

### 2. Use Descriptive Route Names

```dart
// Good
VableRoute(path: '/account', name: 'Account Settings')

// Less Good
VableRoute(path: '/account', name: 'Account')
```

### 3. Add VableNavigatorObserver for Better Context Tracking

```dart
MaterialApp(
  navigatorObservers: [VableNavigatorObserver()],
  // ...
)
```

### 4. Handle Authentication in Routes

Ensure protected routes check authentication:

```dart
MaterialApp(
  onGenerateRoute: (settings) {
    if (settings.name == '/account' && !isAuthenticated) {
      return MaterialPageRoute(builder: (_) => LoginPage());
    }
    // ... normal routing
  },
)
```

### 5. Test Navigation Before Production

Always test AI navigation with real voice commands in your staging environment.

---

## Examples

### Complete Example: Native Navigator

```dart
import 'package:flutter/material.dart';
import 'package:vable_flutter/vable_flutter.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final routes = [
    VableRoute(path: '/', name: 'Home'),
    VableRoute(path: '/account', name: 'Account'),
  ];

  await Vable.initialize('your-public-key', routes: routes);
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      routes: {
        '/': (context) => HomePage(),
        '/account': (context) => AccountPage(),
      },
      navigatorObservers: [VableNavigatorObserver()],
    );
  }
}

class HomePage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Home')),
      body: Center(
        child: ElevatedButton(
          onPressed: () => Vable.startVoiceChat(context),
          child: Text('Start Voice Chat'),
        ),
      ),
    );
  }
}

class AccountPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Account')),
      body: Center(child: Text('Account Page')),
    );
  }
}
```

### Complete Example: GoRouter

```dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:vable_flutter/vable_flutter.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, __) => HomePage()),
      GoRoute(path: '/account', builder: (_, __) => AccountPage()),
    ],
  );

  Vable.configureRouter(
    library: VableRoutingLibrary.goRouter,
    router: router,
  );

  await Vable.initialize('your-public-key', routes: [
    VableRoute(path: '/', name: 'Home'),
    VableRoute(path: '/account', name: 'Account'),
  ]);

  runApp(MaterialApp.router(routerConfig: router));
}
```

---

## Support

For issues or questions:
- Check the [example app](example/) for working implementations
- Review the [API documentation](https://pub.dev/documentation/vable_flutter/latest/)
- Report issues at [GitHub](https://github.com/vable-ai/vable-flutter/issues)

---

## Summary

- **Native Navigator**: Just define routes, no configuration needed
- **GoRouter**: Use `configureRouter()` with your router instance
- **AutoRoute**: Use `setNavigationCallback()` for best results
- **Custom**: Use `setNavigationCallback()` for full control
- Always provide routes to AI during initialization
- Test with real voice commands before production

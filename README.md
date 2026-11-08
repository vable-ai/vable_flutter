# vable_flutter

A Flutter plugin for integrating Vable AI voice assistant into your Flutter applications. Vable provides real-time AI voice chat capabilities with WebRTC and screen scanning functionality.

## Features

- **Voice Chat**: Enable AI-powered voice conversations in your app
- **AI-Driven Navigation**: Let the AI navigate your app based on voice commands
- **Screen Scanning**: Automatic UI context detection to help the AI understand your app
- **Cross-Activity Overlay**: Persistent voice chat UI that works across different screens
- **Multiple Router Support**: Works with Native Navigator, GoRouter, AutoRoute, and custom routers
- **Easy Integration**: Simple API with just a few methods to get started

## Platform Support

| Platform | Status |
|----------|--------|
| Android  | ✅ API 26 and up |
| iOS      | ✅ iOS 15 and up |

## Installation

Add this to your package's `pubspec.yaml` file:

```yaml
dependencies:
  vable_flutter:
    git:
      url: https://github.com/vable-ai/vable_flutter.git
      ref: v0.0.7
```

## Setup

### Android

Set `minSdk` to at least 26 and add this to `android/app/build.gradle.kts`. Two of the SDK's dependencies ship the same file, and a new app won't build without it:

```kotlin
android {
    packaging {
        resources.excludes.add("META-INF/versions/9/OSGI-INF/MANIFEST.MF")
    }
}
```

The microphone and internet permissions come with the SDK.

### iOS

Add a reason for using the microphone to `ios/Runner/Info.plist`:

```xml
<key>NSMicrophoneUsageDescription</key>
<string>Talk to our assistant</string>
```

The plugin brings the iOS SDK as a Swift package, so keep Flutter's Swift Package Manager support on, as it is by default. If you turned it off, run `flutter config --enable-swift-package-manager`. You don't need to add anything to your Podfile.

## Usage

```dart
import 'package:vable_flutter/vable_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Vable.initialize('your-public-key');

  runApp(const MyApp());
}

// From anywhere below your MaterialApp
await Vable.startVoiceChat(context);
await Vable.endVoiceChat();
```

The SDK asks for the microphone when the first session starts. Add `VableNavigatorObserver()` to your app's `navigatorObservers` so the agent knows which page it's on.

Use `Vable.onVoiceChatEnded` to hear when a session ends, including when the user hangs up or the agent ends the call. `Vable.setMicrophoneMuted(true)` mutes the microphone, during a session or ahead of one.

## Signed-in users

To let the agent know who the user is, and act for them, pass their access token. It's the same token the Vable web widget takes as `accessToken`: a JWT your backend signs with your project's signing key, with the user's id in `sub` and optionally `email`, `firstName` and `lastName`.

```dart
await Vable.initialize('your-public-key', accessToken: token);

// After sign in, sign out or a token refresh
await Vable.setAccessToken(newToken);
await Vable.setAccessToken(null); // the next call is a guest call
```

The token is sent when a call starts. A call that's already running keeps the token it started with, and a new token is used from the next call. Without a token, calls are guest calls. If the token is invalid or has expired, the call won't start, so refresh it before it expires.

## How a call looks

During a call, a soft glow runs round the edges of the screen, in one colour. It moves with the agent's voice and the user's, dims while muted, and never blocks a tap. `Vable.setGlowColor(color)` sets its colour.

There's no status text. A small round end button rests on the right edge, fades back after a few seconds, and can be dragged to either side. Users can also say goodbye. If your app has its own way to end the call through `Vable.endVoiceChat()`, you can hide the button with `Vable.setEndButtonVisible(false)`.

For the older pill, with its status and a hang-up button, call `Vable.setCallStyle(VableCallStyle.pill)` before starting. `Vable.setCallPillPosition(VableCallPillPosition.top)` moves it up if it covers your tabs.

## What the agent can do

The agent reads the screen through Flutter's semantics tree, the same view a screen reader gets. It can tap, type, scroll, move sliders and go back, on the page on top and any dialog over it. Controls need a text label or a tooltip for it to find them, so anything that works with a screen reader works with the agent. A slider or field with no label of its own takes the text just before it, as in a `Row` of `Text('Sugar')` and a `Slider`. A `Slider` reads as a percentage unless you give it a `semanticFormatterCallback`, so give it one when its value means something else, such as a quantity. In debug builds the SDK logs each screen's controls that have no label, so you can find them.

The agent can only pass a path to a route, so routes that need an object can't be opened that way. Leave them out with `excludeRoutes` when you call `configureRouter`. If one comes up empty anyway, the SDK leaves it and tells the agent to tap its way there.

The agent never sees what's typed in password fields, fields inside `VableNoOp`, or fields whose label looks like a card number, CVV, PIN, account number or ID number. It still sees that the field is there.

## Your app's own actions

Give the agent actions by passing intents with an `onIntent` handler. What the handler returns is what the agent hears back, and throwing tells it the action failed.

```dart
await Vable.updateIntents(VableContextUpdate(
  intents: [
    VableIntent(
      name: 'addToCart',
      description: 'Add a product to the cart',
      parameters: {
        'productId': IntentParameter(
          description: 'The product to add',
          type: 'string',
          required: true,
        ),
      },
      onIntent: (parameters) async {
        await cart.add(parameters['productId'] as String);
        return 'Added. The cart now has ${cart.length} items.';
      },
    ),
  ],
  intentStates: [
    VableIntentState(
      name: 'cart',
      description: 'What the user has in their cart',
      value: cart.toJson(),
    ),
  ],
));
```

Each call replaces the intents and states you sent before, so send all of them each time.

## Keeping the agent away from a control

The agent can tap and fill in anything on the screen by default, including inside dialogs. Wrap a control in `VableNoOp` to keep it for your users, such as a delete confirmation or a payment button. The agent will ask the user to do it themselves.

```dart
VableNoOp(
  child: FilledButton(onPressed: deleteAccount, child: const Text('Delete')),
)
```

`VableNoOp` doesn't change your layout or how users interact with the control. Wrap a whole dialog to cover everything inside it.

## Screen frames

Vable can record small pictures of the screen during a call, so your team can see what the user saw next to what the agent did. It only does this when your project has screen frames turned on, which they aren't by default, and never outside a call or while the app is in the background.

Before a picture leaves the device, solid boxes cover every text field you can type in, password fields, fields whose label looks like a card number, PIN or ID number, and anything inside `VableNoOp`. Wrap anything else that should never be recorded, such as a card image or a document, in `VableMask`:

```dart
VableMask(
  child: Image.network(card.imageUrl),
)
```

`VableMask` doesn't change your layout or what the agent can do. Maps, web views and other platform views may come out blank.

## AI-Driven Navigation

Vable can automatically navigate your app based on voice commands! When a user says "show me my account", the AI understands the intent and navigates to your account page.

### Quick Start

**For Native Flutter Navigator (No configuration needed):**

```dart
// Just define your routes
MaterialApp(
  routes: {
    '/account': (context) => AccountPage(),
    '/settings': (context) => SettingsPage(),
  },
)
```

**For GoRouter:**

```dart
final router = GoRouter(routes: [...]);

// Routes automatically extracted!
Vable.configureRouter(
  library: VableRoutingLibrary.goRouter,
  router: router,
);
```

**For AutoRoute (Routes auto-extracted + custom callback):**

```dart
final router = getIt<AppRouter>();

// Routes automatically extracted from your router! ✨
Vable.configureRouter(
  library: VableRoutingLibrary.autoRoute,
  router: router,
  // Pages that need an item passed to them can't be opened by path
  excludeRoutes: ['/order/details'],
);

// Set up navigation callback
Vable.setNavigationCallback((url) {
  final router = getIt<AppRouter>();
  switch (url) {
    case '/account':
      router.push(const AccountRoute());
      break;
  }
});
```

### 🆕 Automatic Route Extraction

The SDK now automatically extracts routes from AutoRoute and GoRouter instances! No need to manually define routes - they're read directly from your router configuration.

📖 **See [AI_NAVIGATION.md](AI_NAVIGATION.md) for complete setup guide for all routing libraries**

## Getting Your Public Key

To use Vable, you need a public key. Contact Vable support or visit [vable.ai](https://vable.ai) to get your API key.

## Troubleshooting

### Voice chat won't start

1. Ensure you've called `initialize()` before `startVoiceChat()`
2. Check that the user allowed the microphone
3. Verify your public key is correct, and that `environment` matches it
4. Check your internet connection

### "Not initialized" error

Make sure you call `initialize()` with your public key before using any other methods.

### Build errors

1. Ensure your Android `minSdk` is at least 26
2. Add the `packaging` block from the Android setup if the build fails on a duplicate `MANIFEST.MF`
3. Ensure your iOS deployment target is at least 15.0
4. With Xcode 27, use Flutter 3.47 or later. Older Flutter fails iOS simulator builds with `does not contain architectures "arm64 x86_64"`
5. Try running `flutter clean` and rebuilding

## Sample App

[vable-flutter-sample](https://github.com/vable-ai/vable-flutter-sample) is an app that uses every feature of the SDK.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Support

For issues, questions, or feature requests, please file an issue on our [GitHub repository](https://github.com/vable-ai/vable_flutter).

For Vable platform support, visit [vable.ai](https://vable.ai)

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
| Android  | ✅     |
| iOS      | 🚧 Coming soon |

## Installation

Add this to your package's `pubspec.yaml` file:

```yaml
dependencies:
  vable_flutter:
    git:
      url: https://github.com/vable-ai/vable-flutter.git
      ref: v0.0.1
```

## Setup

### Android

1. Add required permissions to your `android/app/src/main/AndroidManifest.xml`:

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <!-- Required for Vable voice chat -->
    <uses-permission android:name="android.permission.RECORD_AUDIO" />
    <uses-permission android:name="android.permission.INTERNET" />

    <application>
        ...
    </application>
</manifest>
```

2. Ensure your `android/build.gradle` has the minimum SDK version set to at least 24:

```gradle
android {
    defaultConfig {
        minSdkVersion 24
    }
}
```

## Usage

### Basic Example

```dart
import 'package:vable_flutter/vable_flutter.dart';

// Create an instance
final vable = VableFlutter();

// Initialize with your public key
await vable.initialize('your-public-key-here');

// Start voice chat
await vable.startVoiceChat();

// Check if voice chat is active
bool isActive = await vable.isVoiceChatActive();

// End voice chat
await vable.endVoiceChat();
```

### Complete Example

```dart
import 'package:flutter/material.dart';
import 'package:vable_flutter/vable_flutter.dart';

class VoiceAssistantPage extends StatefulWidget {
  @override
  State<VoiceAssistantPage> createState() => _VoiceAssistantPageState();
}

class _VoiceAssistantPageState extends State<VoiceAssistantPage> {
  final _vable = VableFlutter();
  bool _isInitialized = false;
  bool _isActive = false;

  @override
  void initState() {
    super.initState();
    _initializeVable();
  }

  Future<void> _initializeVable() async {
    try {
      // Initialize Vable with your public key
      await _vable.initialize('your-public-key-here');
      setState(() {
        _isInitialized = true;
      });
    } catch (e) {
      print('Failed to initialize Vable: $e');
    }
  }

  Future<void> _toggleVoiceChat() async {
    try {
      if (_isActive) {
        await _vable.endVoiceChat();
      } else {
        await _vable.startVoiceChat();
      }
      final isActive = await _vable.isVoiceChatActive();
      setState(() {
        _isActive = isActive;
      });
    } catch (e) {
      print('Error toggling voice chat: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Voice Assistant'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _isActive ? Icons.mic : Icons.mic_off,
              size: 64,
              color: _isActive ? Colors.green : Colors.grey,
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: _isInitialized ? _toggleVoiceChat : null,
              child: Text(_isActive ? 'End Voice Chat' : 'Start Voice Chat'),
            ),
          ],
        ),
      ),
    );
  }
}
```

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

## API Reference

### `initialize(String publicKey)`

Initialize the Vable SDK with your public key. This must be called before any other Vable methods.

**Parameters:**
- `publicKey`: Your Vable public key for authentication

**Returns:** `Future<bool>` - Returns true if initialization was successful

**Throws:** `Exception` if initialization fails

### `startVoiceChat()`

Start a voice chat session. This will display the Vable voice chat overlay and initialize WebRTC and NATS connections.

**Note:** On Android, `RECORD_AUDIO` permission is required. Ensure you request this permission before calling this method.

**Returns:** `Future<bool>` - Returns true if voice chat started successfully

**Throws:** `Exception` if Vable is not initialized or if starting fails

### `endVoiceChat()`

End the current voice chat session. This will close all connections and remove the voice chat overlay.

**Returns:** `Future<bool>` - Returns true if voice chat ended successfully

**Throws:** `Exception` if ending fails

### `isVoiceChatActive()`

Check if a voice chat session is currently active.

**Returns:** `Future<bool>` - Returns true if voice chat is active, false otherwise

### `getPlatformVersion()`

Get the platform version (for debugging purposes).

**Returns:** `Future<String?>` - The platform version string

## Permissions

### Android

The following permissions are required and must be added to your `AndroidManifest.xml`:

- `RECORD_AUDIO`: Required for voice chat functionality
- `INTERNET`: Required for connecting to Vable servers

You should request the `RECORD_AUDIO` permission at runtime before starting voice chat:

```dart
import 'package:permission_handler/permission_handler.dart';

Future<void> requestMicrophonePermission() async {
  final status = await Permission.microphone.request();
  if (status.isGranted) {
    // Permission granted, you can start voice chat
    await vable.startVoiceChat();
  } else {
    // Permission denied
    print('Microphone permission denied');
  }
}
```

## Getting Your Public Key

To use Vable, you need a public key. Contact Vable support or visit [vable.ai](https://vable.ai) to get your API key.

## Troubleshooting

### Voice chat won't start

1. Ensure you've called `initialize()` before `startVoiceChat()`
2. Check that `RECORD_AUDIO` permission is granted
3. Verify your public key is correct
4. Check your internet connection

### "Not initialized" error

Make sure you call `initialize()` with your public key before using any other methods.

### Build errors

1. Ensure your Android `minSdkVersion` is at least 24
2. Make sure all permissions are added to AndroidManifest.xml
3. Try running `flutter clean` and rebuilding

## Example App

See the `example` directory for a complete sample application demonstrating all features of the plugin.

To run the example:

```bash
cd example
flutter run
```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Support

For issues, questions, or feature requests, please file an issue on our [GitHub repository](https://github.com/vable-ai/vable_flutter).

For Vable platform support, visit [vable.ai](https://vable.ai)

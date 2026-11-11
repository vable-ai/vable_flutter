import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The version of this package, sent with the SDK's logs.
const String vableFlutterVersion = '0.0.8';

/// Controls whether Vable SDK debug logs are printed, and forwards every log
/// line to the native SDK.
///
/// - [VableLogger.debug] — verbose output, printed only when [enabled] is true.
/// - [VableLogger.info] — always printed; use for key lifecycle events.
/// - [VableLogger.warn] — always printed; something went wrong but carried on.
/// - [VableLogger.error] — always printed; use for errors.
///
/// Whatever [enabled] is, every line also goes to the native SDK. When the
/// project's client log level asks for them (set per project in Vable's
/// admin), the native SDK sends them to Vable with its own, so they can be read
/// beside the server's logs for the same room.
///
/// Enable verbose console output for internal debugging:
/// ```dart
/// VableLogger.enabled = true;
/// ```
class VableLogger {
  /// Set to `true` to print verbose debug logging to the console.
  static bool enabled = false;

  static const MethodChannel _channel = MethodChannel('vable_flutter');

  /// False once the platform has no native SDK to forward to, such as on web
  /// or in tests.
  static bool _forwarding = true;

  /// Verbose debug output — only printed when [enabled] is true.
  static void debug(String message, {String tag = 'flutter', Map<String, String>? fields}) {
    if (enabled) {
      debugPrint(message);
    }
    _forward('debug', message, tag, fields);
  }

  /// Key lifecycle events — always printed.
  static void info(String message, {String tag = 'flutter', Map<String, String>? fields}) {
    debugPrint(message);
    _forward('info', message, tag, fields);
  }

  /// Something went wrong, but the SDK carried on — always printed.
  static void warn(String message, {String tag = 'flutter', Map<String, String>? fields}) {
    debugPrint(message);
    _forward('warn', message, tag, fields);
  }

  /// Errors — always printed.
  static void error(String message, {String tag = 'flutter', Map<String, String>? fields}) {
    debugPrint(message);
    _forward('error', message, tag, fields);
  }

  /// Sends a line to the native SDK's logger without waiting for it. A failure
  /// here is never logged through [VableLogger], so it can't loop.
  static void _forward(String level, String message, String tag, Map<String, String>? fields) {
    if (!_forwarding) return;
    if (kIsWeb) {
      _forwarding = false;
      return;
    }
    final args = <String, dynamic>{
      'level': level,
      'message': message,
      'tag': tag,
      if (fields != null && fields.isNotEmpty) 'fields': fields,
    };
    try {
      unawaited(_channel.invokeMethod<void>('log', args).catchError((Object e) {
        if (e is MissingPluginException) {
          _forwarding = false;
        }
      }));
    } catch (_) {
      // Logged before Flutter's bindings were ready; this line stays local.
    }
  }
}

import 'package:flutter/foundation.dart';

/// Controls whether Vable SDK debug logs are printed.
///
/// - [VableLogger.debug] — verbose output, suppressed unless [enabled] is true.
/// - [VableLogger.info] — always printed; use for key lifecycle events.
/// - [VableLogger.error] — always printed; use for errors and warnings.
///
/// Enable verbose logging for internal debugging:
/// ```dart
/// VableLogger.enabled = true;
/// ```
class VableLogger {
  /// Set to `true` to enable verbose debug logging.
  /// Should only be set internally for debugging purposes.
  static bool enabled = false;

  /// Verbose debug output — only printed when [enabled] is true.
  static void debug(String message) {
    if (enabled) {
      debugPrint(message);
    }
  }

  /// Key lifecycle events — always printed.
  static void info(String message) {
    debugPrint(message);
  }

  /// Errors and warnings — always printed.
  static void error(String message) {
    debugPrint(message);
  }
}

# Example app ProGuard rules
# Rules for the Vable Flutter plugin and its Android SDK are automatically
# merged from the library's consumer-rules.pro.

# Flutter-specific rules
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

# Preserve Flutter GeneratedPluginRegistrant
-keep class io.flutter.plugins.GeneratedPluginRegistrant { *; }

# Keep the example app's Application/Activity classes
-keep class ai.vable.sdk.flutter.vable_flutter_example.** { *; }

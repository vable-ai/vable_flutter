# Vable Flutter Plugin - Consumer ProGuard Rules
# These rules are automatically applied to any app that depends on this library.

# Keep the Flutter plugin entry point (registered by class name via Flutter engine)
-keep class ai.vable.sdk.flutter.vable_flutter.VableFlutterPlugin { *; }

# Keep Flutter plugin infrastructure
-keep class io.flutter.plugin.common.** { *; }
-keep interface io.flutter.plugin.common.** { *; }
-keep class io.flutter.embedding.engine.plugins.** { *; }
-keep interface io.flutter.embedding.engine.plugins.** { *; }

# Keep Vable Android SDK public API (required for runtime reflection and JNI)
-keep class ai.vable.mobile.** { *; }
-keep interface ai.vable.mobile.** { *; }
-keepclassmembers class ai.vable.mobile.** { *; }

# Keep enums used by the Vable SDK
-keepclassmembers enum ai.vable.mobile.** {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}

# Preserve serialization/deserialization (JSON parsing in plugin)
-keepclassmembers class * {
    public <init>(org.json.JSONObject);
}

# Preserve method names used via MethodChannel (called by Flutter engine via reflection)
-keepclassmembers class ai.vable.sdk.flutter.vable_flutter.VableFlutterPlugin {
    public void onMethodCall(io.flutter.plugin.common.MethodCall, io.flutter.plugin.common.MethodChannel$Result);
    public void onAttachedToEngine(io.flutter.embedding.engine.plugins.FlutterPlugin$FlutterPluginBinding);
    public void onDetachedFromEngine(io.flutter.embedding.engine.plugins.FlutterPlugin$FlutterPluginBinding);
}

# Suppress warnings for missing classes from optional dependencies
-dontwarn ai.vable.mobile.**
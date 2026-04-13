package ai.vable.sdk.flutter.vable_flutter

import ai.vable.mobile.ClientType
import ai.vable.mobile.Logger
import ai.vable.mobile.Vable
import ai.vable.mobile.VableEventCallback
import org.json.JSONObject
import android.app.Application
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import android.app.Activity
import android.os.Handler
import android.os.Looper

/** VableFlutterPlugin */
class VableFlutterPlugin: FlutterPlugin, MethodCallHandler, ActivityAware {
  /// The MethodChannel that will the communication between Flutter and native Android
  ///
  /// This local reference serves to register the plugin with the Flutter Engine and unregister it
  /// when the Flutter Engine is detached from the Activity
  private lateinit var channel : MethodChannel
  private var activity: Activity? = null
  private var application: Application? = null
  private val mainHandler = Handler(Looper.getMainLooper())

  private val logger = Logger.createLogger("FlutterPlugin")

  override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    channel = MethodChannel(flutterPluginBinding.binaryMessenger, "vable_flutter")
    channel.setMethodCallHandler(this)
    application = flutterPluginBinding.applicationContext as? Application

    // Register navigation callback to receive navigation events from Vable SDK
    Vable.setEventCallback(object : VableEventCallback {
      override fun onNavigateRequested(url: String) {
        // Invoke method on Flutter side using the method channel
        // Must be called on main thread
        mainHandler.post {
          try {
            val args = mapOf("url" to url)
            channel.invokeMethod("onNavigate", args)
            logger.d("Navigation event sent to Flutter: $url")
          } catch (e: Exception) {
            logger.e("Failed to send navigation event to Flutter", e)
          }
        }
      }

      override fun onIntent(id: String, parameters: JSONObject) {
        logger.d("onIntent received: id=$id, parameters=$parameters")
        mainHandler.post {
          try {
            val parametersMap = parameters.keys().asSequence()
              .associateWith { parameters.get(it) }
            val args = mapOf(
              "id" to id,
              "parameters" to parametersMap
            )
            channel.invokeMethod("onIntent", args)
            logger.d("onIntent forwarded to Flutter: id=$id")
          } catch (e: Exception) {
            logger.e("Failed to forward onIntent to Flutter", e)
          }
        }
      }
    })
  }

  override fun onMethodCall(call: MethodCall, result: Result) {
    when (call.method) {
      "getPlatformVersion" -> {
        result.success("Android ${android.os.Build.VERSION.RELEASE}")
      }
      "initialize" -> {
        val publicKey = call.argument<String>("publicKey")
        if (publicKey == null) {
          result.error("MISSING_ARGUMENT", "publicKey is required", null)
          return
        }
        if (application == null) {
          result.error("NO_APPLICATION", "Application context not available", null)
          return
        }
        val debugLogging = call.argument<Boolean>("debugLogging") ?: false
        Logger.setDebugEnabled(debugLogging)
        try {
          // Pass the current activity to ensure ActivityTracker captures FlutterActivity immediately
          // This is critical for screen scanning to work right away, even if initialize is called
          // after the activity has already started
          Vable.initialize(publicKey, application!!, ClientType.Flutter)
          result.success(true)
        } catch (e: Exception) {
          result.error("INITIALIZATION_ERROR", e.message, null)
        }
      }
      "startVoiceChat" -> {
        try {
          val context = activity ?: application
          if (context == null) {
            result.error("NO_CONTEXT", "Context not available", null)
            return
          }
          Vable.startVoiceChat(context)
          result.success(true)
        } catch (e: IllegalStateException) {
          result.error("NOT_INITIALIZED", e.message, null)
        } catch (e: Exception) {
          result.error("START_ERROR", e.message, null)
        }
      }
      "endVoiceChat" -> {
        try {
          Vable.endVoiceChat()
          result.success(true)
        } catch (e: IllegalStateException) {
          result.error("NOT_INITIALIZED", e.message, null)
        } catch (e: Exception) {
          result.error("END_ERROR", e.message, null)
        }
      }
      "isVoiceChatActive" -> {
        try {
          val isActive = Vable.isVoiceChatActive()
          result.success(isActive)
        } catch (e: IllegalStateException) {
          result.error("NOT_INITIALIZED", e.message, null)
        } catch (e: Exception) {
          result.error("CHECK_ERROR", e.message, null)
        }
      }
      "updateFlutterScreenContext" -> {
        try {
          val screenContext = call.argument<Map<String, Any>>("screenContext")
          if (screenContext == null) {
            result.error("MISSING_ARGUMENT", "screenContext is required", null)
            return
          }

          // Pass Flutter screen context to the Vable SDK
          Vable.updateFlutterScreenContext(screenContext)
          result.success(true)

          logger.d("Flutter screen context received: ${screenContext["elementCount"]} elements")
        } catch (e: Exception) {
          logger.e("Error updating Flutter screen context", e)
          result.error("UPDATE_CONTEXT_ERROR", e.message, null)
        }
      }
      "updateIntents" -> {
        try {
          val contextUpdateMap = call.argument<Map<String, Any>>("contextUpdate")
          if (contextUpdateMap == null) {
            result.error("MISSING_ARGUMENT", "contextUpdate is required", null)
            return
          }

          // Extract data from the context update map
          val intentsList = contextUpdateMap["intents"] as? List<Map<String, Any>> ?: emptyList()
          val intentStatesList = contextUpdateMap["intentStates"] as? List<Map<String, Any>> ?: emptyList()
          val intentPromptsList = contextUpdateMap["intentPrompts"] as? List<Map<String, Any>> ?: emptyList()
          val routesList = contextUpdateMap["routes"] as? List<Map<String, Any>> ?: emptyList()

          // Convert to native models
          val intents = intentsList.map { intentMap ->
            @Suppress("UNCHECKED_CAST")
            val rawParams = intentMap["parameters"] as? Map<String, Map<String, Any>>
            val parameters = rawParams?.mapValues { (_, paramMap) ->
              ai.vable.mobile.IntentParameterDefinition(
                type = paramMap["type"] as String,
                description = paramMap["description"] as String,
                options = paramMap["options"] as? List<Any>,
                required = paramMap["required"] as? Boolean
              )
            } ?: emptyMap()
            ai.vable.mobile.Intent(
              name = intentMap["name"] as String,
              description = intentMap["description"] as? String,
              parameters = parameters
            )
          }

          val intentStates = intentStatesList.map { stateMap ->
            ai.vable.mobile.IntentState(
              name = stateMap["name"] as String,
              description = stateMap["description"] as String,
              value = stateMap["value"] ?: ""
            )
          }

          val intentPrompts = intentPromptsList.map { promptMap ->
            ai.vable.mobile.IntentPrompt(
              intentId = promptMap["intentId"] as String,
              prompt = promptMap["prompt"] as String,
              context = promptMap["context"] as? String
            )
          }

          val routes = routesList.map { routeMap ->
            ai.vable.mobile.FlutterRoute(
              path = routeMap["path"] as String,
              name = routeMap["name"] as? String
            )
          }

          // Create context update and send to Vable SDK
          val contextUpdate = ai.vable.mobile.ContextUpdate(
            intents = intents,
            intentStates = intentStates,
            intentPrompts = intentPrompts,
            routes = routes
          )

          Vable.updateIntents(contextUpdate)
          result.success(true)

          logger.d("Context update received: ${routes.size} routes, ${intents.size} intents")
        } catch (e: Exception) {
          logger.e("Error updating intents", e)
          result.error("UPDATE_INTENTS_ERROR", e.message, null)
        }
      }
      "sendToolResult" -> {
        try {
          val toolName = call.argument<String>("toolName")
          if (toolName == null) {
            result.error("MISSING_ARGUMENT", "toolName is required", null)
            return
          }
          val toolId = call.argument<String>("toolId")
          val toolResult = call.argument<String>("result")
          if (toolResult == null) {
            result.error("MISSING_ARGUMENT", "result is required", null)
            return
          }
          Vable.sendToolResult(toolName, toolId, toolResult)
          result.success(true)
          logger.d("Tool result sent: tool=$toolName, id=$toolId")
        } catch (e: IllegalStateException) {
          result.error("NOT_INITIALIZED", e.message, null)
        } catch (e: Exception) {
          logger.e("Error sending tool result", e)
          result.error("SEND_TOOL_RESULT_ERROR", e.message, null)
        }
      }
      else -> {
        result.notImplemented()
      }
    }
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    channel.setMethodCallHandler(null)
    // Unregister navigation callback
    Vable.setEventCallback(null)
  }

  override fun onAttachedToActivity(binding: ActivityPluginBinding) {
    activity = binding.activity
  }

  override fun onDetachedFromActivityForConfigChanges() {
    activity = null
  }

  override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
    activity = binding.activity
  }

  override fun onDetachedFromActivity() {
    activity = null
  }
}

package ai.vable.sdk.flutter.vable_flutter

import ai.vable.mobile.CallPillPosition
import ai.vable.mobile.CallStyle
import ai.vable.mobile.ClientType
import ai.vable.mobile.Logger
import ai.vable.mobile.ScreenFramePayload
import ai.vable.mobile.Vable
import ai.vable.mobile.VableChatListener
import ai.vable.mobile.VableChatMessage
import ai.vable.mobile.VableEnvironment
import ai.vable.mobile.VableToolEventCallback
import org.json.JSONArray
import org.json.JSONObject
import android.app.Application
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.PluginRegistry
import android.app.Activity
import android.graphics.Bitmap
import android.os.Handler
import android.os.Looper
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/** VableFlutterPlugin */
class VableFlutterPlugin: FlutterPlugin, MethodCallHandler, ActivityAware, PluginRegistry.RequestPermissionsResultListener {
  /// The MethodChannel that will the communication between Flutter and native Android
  ///
  /// This local reference serves to register the plugin with the Flutter Engine and unregister it
  /// when the Flutter Engine is detached from the Activity
  private lateinit var channel : MethodChannel
  private var activity: Activity? = null
  private var activityBinding: ActivityPluginBinding? = null
  private var application: Application? = null
  private val mainHandler = Handler(Looper.getMainLooper())
  /** Encodes screen frames off the main thread, one at a time */
  private var frameEncoder: ExecutorService? = null

  private val logger = Logger.createLogger("FlutterPlugin")

  override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    channel = MethodChannel(flutterPluginBinding.binaryMessenger, "vable_flutter")
    channel.setMethodCallHandler(this)
    application = flutterPluginBinding.applicationContext as? Application

    // Register navigation callback to receive navigation events from Vable SDK.
    // It hears the ID of each tool call too, which Dart sends back with its result.
    Vable.setEventCallback(object : VableToolEventCallback {
      override fun onNavigateRequested(url: String) = onNavigateRequested(url, null)

      override fun onNavigateRequested(url: String, toolId: String?) {
        // Invoke method on Flutter side using the method channel
        // Must be called on main thread
        mainHandler.post {
          try {
            val args = mapOf("url" to url, "toolId" to toolId)
            channel.invokeMethod("onNavigate", args)
            logger.d("Navigation event sent to Flutter: $url")
          } catch (e: Exception) {
            logger.e("Failed to send navigation event to Flutter", e)
          }
        }
      }

      override fun onIntent(id: String, parameters: JSONObject) = onIntent(id, parameters, null)

      override fun onIntent(id: String, parameters: JSONObject, toolId: String?) {
        logger.d("onIntent received: id=$id, toolId=$toolId, parameters=$parameters")
        mainHandler.post {
          try {
            val args = mapOf(
              "id" to id,
              "toolId" to toolId,
              "parameters" to toPlatformValue(parameters)
            )
            channel.invokeMethod("onIntent", args)
            logger.d("onIntent forwarded to Flutter: id=$id")
          } catch (e: Exception) {
            logger.e("Failed to forward onIntent to Flutter", e)
          }
        }
      }

      override fun onVoiceChatEnded() {
        mainHandler.post { channel.invokeMethod("onVoiceChatEnded", null) }
      }

      override fun onVoiceChatStarted() {
        mainHandler.post { channel.invokeMethod("onVoiceChatStarted", null) }
      }

      override fun onAssistantText(text: String, isFinal: Boolean) {
        mainHandler.post {
          channel.invokeMethod("onAssistantText", mapOf("text" to text, "isFinal" to isFinal))
        }
      }

      // Vable calls these on the main thread
      override fun onAgentState(state: String) {
        channel.invokeMethod("onAgentState", mapOf("state" to state))
      }

      override fun onUserTranscript(text: String, isFinal: Boolean) {
        channel.invokeMethod("onUserTranscript", mapOf("text" to text, "isFinal" to isFinal))
      }

      override fun onUserSpeechStarted() {
        channel.invokeMethod("onUserSpeechStarted", null)
      }

      override fun onUserInterrupted() {
        channel.invokeMethod("onUserInterrupted", null)
      }

      override fun onVoiceLevels(agent: Float, user: Float) {
        mainHandler.post {
          channel.invokeMethod("onVoiceLevels", mapOf("agent" to agent.toDouble(), "user" to user.toDouble()))
        }
      }
    })

    // The chat's lines, failures, opening and closing, for Dart
    Vable.setChatListener(object : VableChatListener {
      override fun onMessagesChanged(messages: List<VableChatMessage>) {
        val maps = messages.map { it.toMap() }
        mainHandler.post { channel.invokeMethod("onChatUpdated", mapOf("messages" to maps)) }
      }

      override fun onError(code: String) {
        mainHandler.post { channel.invokeMethod("onChatError", mapOf("code" to code)) }
      }

      override fun onChatOpened() {
        mainHandler.post { channel.invokeMethod("onChatOpened", null) }
      }

      override fun onChatClosed() {
        mainHandler.post { channel.invokeMethod("onChatClosed", null) }
      }
    })
  }

  /** The method channel can't carry JSON types, and intent parameters can nest. */
  private fun toPlatformValue(value: Any?): Any? = when (value) {
    is JSONObject -> value.keys().asSequence().associateWith { toPlatformValue(value.get(it)) }
    is JSONArray -> (0 until value.length()).map { toPlatformValue(value.get(it)) }
    JSONObject.NULL -> null
    else -> value
  }

  override fun onMethodCall(call: MethodCall, result: Result) {
    when (call.method) {
      "log" -> {
        // A line from the Dart side's VableLogger. Recorded for the client logs only; Dart has
        // already printed it.
        val message = call.argument<String>("message")
        if (message != null) {
          val level = when (call.argument<String>("level")) {
            "debug" -> Logger.Level.DEBUG
            "warn" -> Logger.Level.WARN
            "error" -> Logger.Level.ERROR
            else -> Logger.Level.INFO
          }
          Logger.record(
            level,
            message,
            call.argument<String>("tag") ?: "flutter",
            call.argument<Map<String, String>>("fields") ?: emptyMap(),
          )
        }
        result.success(null)
      }
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
        call.argument<String>("wrapperVersion")?.let { Logger.setWrapper("flutter", it) }
        try {
          // Pass the current activity to ensure ActivityTracker captures FlutterActivity immediately
          // This is critical for screen scanning to work right away, even if initialize is called
          // after the activity has already started
          val environment = if (call.argument<String>("environment") == "dev") {
            VableEnvironment.Development
          } else {
            VableEnvironment.Production
          }
          Vable.initialize(
            publicKey,
            application!!,
            ClientType.Flutter,
            environment,
            call.argument<String>("accessToken")
          )
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
          // Answer once it's connected, as iOS does, so a request made straight
          // after starting isn't lost
          Vable.startVoiceChat(context, listener = { started, error ->
            mainHandler.post {
              if (started) result.success(true)
              else result.error("START_ERROR", error ?: "Voice chat couldn't start", null)
            }
          })
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
      "setAccessToken" -> {
        Vable.setAccessToken(call.argument<String>("accessToken"))
        result.success(true)
      }
      "setMicrophoneMuted" -> {
        Vable.setMicrophoneMuted(call.argument<Boolean>("muted") ?: false)
        result.success(true)
      }
      "setCallPillPosition" -> {
        Vable.setCallPillPosition(
          if (call.argument<String>("position") == "top") CallPillPosition.Top else CallPillPosition.Bottom
        )
        result.success(true)
      }
      "cancelTurn" -> {
        Vable.cancelTurn()
        result.success(true)
      }
      "say" -> {
        Vable.say(call.argument<String>("text") ?: "")
        result.success(true)
      }
      "setCallStyle" -> {
        Vable.setCallStyle(
          when (call.argument<String>("style")) {
            "pill" -> CallStyle.Pill
            "none" -> CallStyle.None
            else -> CallStyle.Glow
          }
        )
        result.success(true)
      }
      "setGlowColor" -> {
        // Dart sends ARGB as a positive number, which can overflow an Int into a Long
        val color = call.argument<Number>("color")
        if (color != null) Vable.setGlowColor(color.toLong().toInt())
        result.success(true)
      }
      "setEndButtonVisible" -> {
        Vable.setEndButtonVisible(call.argument<Boolean>("visible") ?: true)
        result.success(true)
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
      "getScreenFrames" -> {
        result.success(Vable.getScreenFramesConfig()?.toMap())
      }
      "sendScreenFrame" -> sendScreenFrame(call, result)
      "openChat" -> {
        try {
          Vable.openChat(activity)
          result.success(true)
        } catch (e: Exception) {
          result.error("NOT_INITIALIZED", e.message, null)
        }
      }
      "closeChat" -> {
        Vable.closeChat()
        result.success(true)
      }
      "isChatOpen" -> result.success(Vable.isChatOpen())
      "sendChatMessage" -> {
        val text = call.argument<String>("text")
        if (text == null) {
          result.error("MISSING_ARGUMENT", "text is required", null)
          return
        }
        Vable.sendMessage(text) { error ->
          mainHandler.post {
            if (error == null) result.success(true)
            else result.error("SEND_ERROR", error.message, null)
          }
        }
      }
      "getChatMessages" -> result.success(Vable.chatMessages().map { it.toMap() })
      "startNewChat" -> {
        Vable.startNewChat()
        result.success(true)
      }
      "setChatButtonVisible" -> {
        Vable.setChatButtonVisible(call.argument<Boolean>("visible") ?: true)
        result.success(true)
      }
      else -> {
        result.notImplemented()
      }
    }
  }

  /**
   * Encodes Dart's masked RGBA frame as JPEG off the main thread, and sends it through the
   * SDK. Answers once it's handed over, so Dart keeps one frame in flight.
   */
  private fun sendScreenFrame(call: MethodCall, result: Result) {
    val rgba = call.argument<ByteArray>("rgba")
    val width = call.argument<Int>("width") ?: 0
    val height = call.argument<Int>("height") ?: 0
    val header = call.argument<String>("header")
    if (rgba == null || header == null || width <= 0 || height <= 0 || rgba.size < width * height * 4) {
      result.error("MISSING_ARGUMENT", "rgba, width, height and header are required", null)
      return
    }
    val encoder = frameEncoder ?: Executors.newSingleThreadExecutor().also { frameEncoder = it }
    encoder.execute {
      val sent = try {
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        // ARGB_8888 is laid out as RGBA bytes, so Dart's bytes copy straight in
        bitmap.copyPixelsFromBuffer(ByteBuffer.wrap(rgba, 0, width * height * 4))
        val jpeg = ByteArrayOutputStream().use { out ->
          bitmap.compress(Bitmap.CompressFormat.JPEG, 50, out)
          out.toByteArray()
        }
        bitmap.recycle()
        Vable.sendScreenFrame(ScreenFramePayload.build(header, jpeg))
      } catch (e: Exception) {
        logger.e("Failed to encode screen frame", e)
        false
      }
      mainHandler.post { result.success(sent) }
    }
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    channel.setMethodCallHandler(null)
    frameEncoder?.shutdown()
    frameEncoder = null
    // Unregister navigation callback
    Vable.setEventCallback(null)
    Vable.setChatListener(null)
  }

  override fun onAttachedToActivity(binding: ActivityPluginBinding) {
    attachTo(binding)
  }

  override fun onDetachedFromActivityForConfigChanges() {
    detachFromActivity()
  }

  override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
    attachTo(binding)
  }

  override fun onDetachedFromActivity() {
    detachFromActivity()
  }

  private fun attachTo(binding: ActivityPluginBinding) {
    activity = binding.activity
    activityBinding = binding
    binding.addRequestPermissionsResultListener(this)
  }

  private fun detachFromActivity() {
    activityBinding?.removeRequestPermissionsResultListener(this)
    activityBinding = null
    activity = null
  }

  // Without this the session stops at the permission prompt, because the SDK
  // never hears the answer. The Activity belongs to Flutter, so only a plugin can pass it on.
  override fun onRequestPermissionsResult(
    requestCode: Int,
    permissions: Array<out String>,
    grantResults: IntArray
  ): Boolean {
    if (requestCode != MICROPHONE_REQUEST_CODE) return false
    @Suppress("UNCHECKED_CAST")
    Vable.onPermissionResult(requestCode, permissions as Array<String>, grantResults)
    return true
  }

  private companion object {
    const val MICROPHONE_REQUEST_CODE = 1001
  }
}

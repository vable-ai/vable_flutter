import Flutter
import UIKit
// VableAI sources are included directly in this module via podspec
import VableAI

public class VableFlutterPlugin: NSObject, FlutterPlugin, VableNavigationDelegate {

  // MARK: - Properties

  private var channel: FlutterMethodChannel?
  private var registrar: FlutterPluginRegistrar?
  private var isInitialized = false

  // MARK: - Plugin Registration

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "vable_flutter",
      binaryMessenger: registrar.messenger()
    )
    let instance = VableFlutterPlugin()
    instance.channel = channel
    instance.registrar = registrar

    registrar.addMethodCallDelegate(instance, channel: channel)

    // Set navigation delegate immediately
    Vable.shared.setNavigationDelegate(instance)

    print("[VableFlutterPlugin] Plugin registered")
  }

  // MARK: - Method Call Handler

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getPlatformVersion":
      handleGetPlatformVersion(result: result)

    case "initialize":
      handleInitialize(call: call, result: result)

    case "startVoiceChat":
      handleStartVoiceChat(result: result)

    case "endVoiceChat":
      handleEndVoiceChat(result: result)

    case "isVoiceChatActive":
      handleIsVoiceChatActive(result: result)

    case "updateFlutterScreenContext":
      handleUpdateFlutterScreenContext(call: call, result: result)

    case "updateIntents":
      handleUpdateIntents(call: call, result: result)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Method Handlers

  private func handleGetPlatformVersion(result: @escaping FlutterResult) {
    result("iOS " + UIDevice.current.systemVersion)
  }

  private func handleInitialize(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
          let publicKey = args["publicKey"] as? String else {
      result(FlutterError(
        code: "MISSING_ARGUMENT",
        message: "publicKey is required",
        details: nil
      ))
      return
    }

    do {
      try Vable.shared.initialize(publicKey: publicKey)
      isInitialized = true
      print("[VableFlutterPlugin] Vable SDK initialized")
      result(true)
    } catch {
      result(FlutterError(
        code: "INITIALIZATION_ERROR",
        message: error.localizedDescription,
        details: nil
      ))
    }
  }

  private func handleStartVoiceChat(result: @escaping FlutterResult) {
    guard isInitialized else {
      result(FlutterError(
        code: "NOT_INITIALIZED",
        message: "Vable SDK not initialized. Call initialize() first.",
        details: nil
      ))
      return
    }

    // Get root view controller
    guard let viewController = getRootViewController() else {
      result(FlutterError(
        code: "NO_VIEW_CONTROLLER",
        message: "Unable to get root view controller",
        details: nil
      ))
      return
    }

    // Start voice chat asynchronously
    Task {
      do {
        try await Vable.shared.startVoiceChat(
          from: viewController,
          config: Vable.VoiceChatConfig()
        )

        // Return success on main thread
        await MainActor.run {
          print("[VableFlutterPlugin] Voice chat started successfully")
          result(true)
        }
      } catch let error as VableError {
        await MainActor.run {
          result(FlutterError(
            code: self.errorCodeFromVableError(error),
            message: error.localizedDescription,
            details: nil
          ))
        }
      } catch {
        await MainActor.run {
          result(FlutterError(
            code: "START_ERROR",
            message: error.localizedDescription,
            details: nil
          ))
        }
      }
    }
  }

  private func handleEndVoiceChat(result: @escaping FlutterResult) {
    guard isInitialized else {
      result(FlutterError(
        code: "NOT_INITIALIZED",
        message: "Vable SDK not initialized",
        details: nil
      ))
      return
    }

    Vable.shared.endVoiceChat()
    print("[VableFlutterPlugin] Voice chat ended")
    result(true)
  }

  private func handleIsVoiceChatActive(result: @escaping FlutterResult) {
    guard isInitialized else {
      result(FlutterError(
        code: "NOT_INITIALIZED",
        message: "Vable SDK not initialized",
        details: nil
      ))
      return
    }

    result(Vable.shared.isVoiceChatActive())
  }

  private func handleUpdateFlutterScreenContext(
    call: FlutterMethodCall,
    result: @escaping FlutterResult
  ) {
    guard let args = call.arguments as? [String: Any],
          let screenContext = args["screenContext"] as? [String: Any] else {
      result(FlutterError(
        code: "MISSING_ARGUMENT",
        message: "screenContext is required",
        details: nil
      ))
      return
    }

    Vable.shared.updateFlutterScreenContext(screenContext)
    result(true)
  }

  private func handleUpdateIntents(
    call: FlutterMethodCall,
    result: @escaping FlutterResult
  ) {
    guard let args = call.arguments as? [String: Any],
          let contextUpdateMap = args["contextUpdate"] as? [String: Any] else {
      result(FlutterError(
        code: "MISSING_ARGUMENT",
        message: "contextUpdate is required",
        details: nil
      ))
      return
    }

    do {
      let contextUpdate = try parseContextUpdate(from: contextUpdateMap)
      Vable.shared.updateIntents(contextUpdate)
      result(true)
    } catch {
      result(FlutterError(
        code: "UPDATE_INTENTS_ERROR",
        message: error.localizedDescription,
        details: nil
      ))
    }
  }

  // MARK: - VableNavigationDelegate

  public func onNavigateRequested(url: String) {
    // Must be called on main thread
    DispatchQueue.main.async { [weak self] in
      guard let self = self, let channel = self.channel else { return }

      let args: [String: Any] = ["url": url]
      channel.invokeMethod("onNavigate", arguments: args)

      print("[VableFlutterPlugin] Navigation event sent to Flutter: \(url)")
    }
  }

  // MARK: - Helper Methods

  private func getRootViewController() -> UIViewController? {
    // iOS 13+ method
    if #available(iOS 13.0, *) {
      let scene = UIApplication.shared.connectedScenes
        .first(where: { $0.activationState == .foregroundActive })
        as? UIWindowScene
      return scene?.windows.first?.rootViewController
    } else {
      // Fallback for iOS 12 (if supported)
      return UIApplication.shared.keyWindow?.rootViewController
    }
  }

  private func errorCodeFromVableError(_ error: VableError) -> String {
    switch error {
    case .notInitialized:
      return "NOT_INITIALIZED"
    case .invalidPublicKey:
      return "INVALID_PUBLIC_KEY"
    case .microphonePermissionDenied:
      return "MICROPHONE_PERMISSION_DENIED"
    case .voiceChatAlreadyActive:
      return "VOICE_CHAT_ALREADY_ACTIVE"
    case .connectionFailed:
      return "CONNECTION_ERROR"
    case .webRTCError:
      return "WEBRTC_ERROR"
    case .natsError:
      return "NATS_ERROR"
    }
  }

  private func parseContextUpdate(from dict: [String: Any]) throws -> ContextUpdate {
    // Extract arrays
    let intentsList = dict["intents"] as? [[String: Any]] ?? []
    let intentStatesList = dict["intentStates"] as? [[String: Any]] ?? []
    let intentPromptsList = dict["intentPrompts"] as? [[String: Any]] ?? []
    let routesList = dict["routes"] as? [[String: Any]] ?? []

    // Parse intents
    let intents = try intentsList.map { intentMap -> VableIntent in
      guard let id = intentMap["id"] as? String,
            let name = intentMap["name"] as? String else {
        throw NSError(
          domain: "VableFlutterPlugin",
          code: -1,
          userInfo: [NSLocalizedDescriptionKey: "Invalid intent format"]
        )
      }
      let description = intentMap["description"] as? String
      return VableIntent(id: id, name: name, description: description)
    }

    // Parse intent states
    let intentStates = try intentStatesList.map { stateMap -> IntentState in
      guard let intentId = stateMap["intentId"] as? String,
            let state = stateMap["state"] as? String else {
        throw NSError(
          domain: "VableFlutterPlugin",
          code: -1,
          userInfo: [NSLocalizedDescriptionKey: "Invalid intent state format"]
        )
      }
      let metadata = stateMap["metadata"] as? [String: Any]
      return IntentState(intentId: intentId, state: state, metadata: metadata)
    }

    // Parse intent prompts
    let intentPrompts = try intentPromptsList.map { promptMap -> IntentPrompt in
      guard let intentId = promptMap["intentId"] as? String,
            let prompt = promptMap["prompt"] as? String else {
        throw NSError(
          domain: "VableFlutterPlugin",
          code: -1,
          userInfo: [NSLocalizedDescriptionKey: "Invalid intent prompt format"]
        )
      }
      let context = promptMap["context"] as? String
      return IntentPrompt(intentId: intentId, prompt: prompt, context: context)
    }

    // Parse routes
    let routes = try routesList.map { routeMap -> FlutterRoute in
      guard let path = routeMap["path"] as? String else {
        throw NSError(
          domain: "VableFlutterPlugin",
          code: -1,
          userInfo: [NSLocalizedDescriptionKey: "Invalid route format"]
        )
      }
      let name = routeMap["name"] as? String
      return FlutterRoute(path: path, name: name)
    }

    return ContextUpdate(
      intents: intents,
      intentStates: intentStates,
      intentPrompts: intentPrompts,
      routes: routes
    )
  }

  // MARK: - Cleanup

  public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
    channel?.setMethodCallHandler(nil)
    channel = nil
    Vable.shared.setNavigationDelegate(nil)
    print("[VableFlutterPlugin] Plugin detached")
  }
}

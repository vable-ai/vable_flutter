import Flutter
import UIKit
import VableAI

public class VableFlutterPlugin: NSObject, FlutterPlugin, VableNavigationDelegate {

  // MARK: - Properties

  private var channel: FlutterMethodChannel?
  private var isInitialized = false

  // MARK: - Plugin Registration

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "vable_flutter",
      binaryMessenger: registrar.messenger()
    )
    let instance = VableFlutterPlugin()
    instance.channel = channel
    registrar.addMethodCallDelegate(instance, channel: channel)
    Vable.shared.setNavigationDelegate(instance)
    Logger.shared.debug("Plugin registered")
  }

  // MARK: - Method Call Handler

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getPlatformVersion":
      result("iOS " + UIDevice.current.systemVersion)

    case "initialize":
      handleInitialize(call: call, result: result)

    case "startVoiceChat":
      handleStartVoiceChat(result: result)

    case "endVoiceChat":
      handleEndVoiceChat(result: result)

    case "isVoiceChatActive":
      result(Vable.shared.isVoiceChatActive())

    case "updateFlutterScreenContext":
      handleUpdateFlutterScreenContext(call: call, result: result)

    case "updateIntents":
      handleUpdateIntents(call: call, result: result)

    case "sendToolResult":
      handleSendToolResult(call: call, result: result)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Method Handlers

  private func handleInitialize(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
          let publicKey = args["publicKey"] as? String else {
      result(FlutterError(code: "MISSING_ARGUMENT", message: "publicKey is required", details: nil))
      return
    }
    let debugLogging = args["debugLogging"] as? Bool ?? false
    Logger.shared.isDebugEnabled = debugLogging

    let environment: Vable.VableEnvironment
    if let envString = args["environment"] as? String, envString == "dev" {
      environment = .development
    } else {
      environment = .production
    }
    do {
      try Vable.shared.initialize(publicKey: publicKey, environment: environment)
      isInitialized = true
      Logger.shared.info("Vable SDK initialized (\(environment.rawValue))")
      result(true)
    } catch {
      result(FlutterError(code: "INITIALIZATION_ERROR", message: error.localizedDescription, details: nil))
    }
  }

  private func handleStartVoiceChat(result: @escaping FlutterResult) {
    guard isInitialized else {
      result(FlutterError(code: "NOT_INITIALIZED", message: "Vable SDK not initialized. Call initialize() first.", details: nil))
      return
    }
    guard let viewController = rootViewController() else {
      result(FlutterError(code: "NO_VIEW_CONTROLLER", message: "Unable to get root view controller", details: nil))
      return
    }
    Task {
      do {
        try await Vable.shared.startVoiceChat(from: viewController)
        await MainActor.run {
          Logger.shared.info("Voice chat started successfully")
          result(true)
        }
      } catch let error as VableError {
        await MainActor.run {
          result(FlutterError(code: vableErrorCode(error), message: error.localizedDescription, details: nil))
        }
      } catch {
        await MainActor.run {
          result(FlutterError(code: "START_ERROR", message: error.localizedDescription, details: nil))
        }
      }
    }
  }

  private func handleEndVoiceChat(result: @escaping FlutterResult) {
    Task { @MainActor in
      Vable.shared.endVoiceChat()
      Logger.shared.info("Voice chat ended")
      result(true)
    }
  }

  private func handleUpdateFlutterScreenContext(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
          let screenContext = args["screenContext"] as? [String: Any] else {
      result(FlutterError(code: "MISSING_ARGUMENT", message: "screenContext is required", details: nil))
      return
    }
    Vable.shared.updateFlutterScreenContext(screenContext)
    result(true)
  }

  private func handleUpdateIntents(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
          let contextUpdateMap = args["contextUpdate"] as? [String: Any] else {
      result(FlutterError(code: "MISSING_ARGUMENT", message: "contextUpdate is required", details: nil))
      return
    }
    do {
      let contextUpdate = try parseContextUpdate(from: contextUpdateMap)
      Vable.shared.updateIntents(contextUpdate)
      result(true)
    } catch {
      result(FlutterError(code: "UPDATE_INTENTS_ERROR", message: error.localizedDescription, details: nil))
    }
  }

  private func handleSendToolResult(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
          let toolName = args["toolName"] as? String,
          let toolResult = args["result"] as? String else {
      result(FlutterError(code: "MISSING_ARGUMENT", message: "toolName and result are required", details: nil))
      return
    }
    Vable.shared.sendToolResult(toolName: toolName, toolId: args["toolId"] as? String, result: toolResult)
    result(true)
  }

  // MARK: - VableNavigationDelegate

  public func onNavigateRequested(url: String) {
    DispatchQueue.main.async { [weak self] in
      self?.channel?.invokeMethod("onNavigate", arguments: ["url": url])
    }
  }

  public func onIntent(id: String, parameters: [String: Any]) {
    DispatchQueue.main.async { [weak self] in
      self?.channel?.invokeMethod("onIntent", arguments: ["id": id, "parameters": parameters])
    }
  }

  // MARK: - Cleanup

  public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
    channel?.setMethodCallHandler(nil)
    channel = nil
    Vable.shared.setNavigationDelegate(nil)
    Logger.shared.debug("Plugin detached")
  }

  // MARK: - Helpers

  private func rootViewController() -> UIViewController? {
    let scene = UIApplication.shared.connectedScenes
      .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
    var vc = scene?.windows.first(where: { $0.isKeyWindow })?.rootViewController
    while let presented = vc?.presentedViewController { vc = presented }
    return vc
  }

  private func vableErrorCode(_ error: VableError) -> String {
    switch error {
    case .notInitialized:           return "NOT_INITIALIZED"
    case .invalidPublicKey:         return "INVALID_PUBLIC_KEY"
    case .microphonePermissionDenied: return "MICROPHONE_PERMISSION_DENIED"
    case .voiceChatAlreadyActive:   return "VOICE_CHAT_ALREADY_ACTIVE"
    case .connectionFailed:         return "CONNECTION_ERROR"
    case .webRTCError:              return "WEBRTC_ERROR"
    case .natsError:                return "NATS_ERROR"
    }
  }

  private func parseContextUpdate(from dict: [String: Any]) throws -> ContextUpdate {
    let intents = try (dict["intents"] as? [[String: Any]] ?? []).map { d -> VableIntent in
      guard let id = d["id"] as? String, let name = d["name"] as? String else {
        throw NSError(domain: "VableFlutterPlugin", code: -1,
                      userInfo: [NSLocalizedDescriptionKey: "Invalid intent format"])
      }
      return VableIntent(id: id, name: name, description: d["description"] as? String)
    }
    let intentStates = try (dict["intentStates"] as? [[String: Any]] ?? []).map { d -> IntentState in
      guard let intentId = d["intentId"] as? String, let state = d["state"] as? String else {
        throw NSError(domain: "VableFlutterPlugin", code: -1,
                      userInfo: [NSLocalizedDescriptionKey: "Invalid intent state format"])
      }
      return IntentState(intentId: intentId, state: state, metadata: d["metadata"] as? [String: Any])
    }
    let intentPrompts = try (dict["intentPrompts"] as? [[String: Any]] ?? []).map { d -> IntentPrompt in
      guard let intentId = d["intentId"] as? String, let prompt = d["prompt"] as? String else {
        throw NSError(domain: "VableFlutterPlugin", code: -1,
                      userInfo: [NSLocalizedDescriptionKey: "Invalid intent prompt format"])
      }
      return IntentPrompt(intentId: intentId, prompt: prompt, context: d["context"] as? String)
    }
    let routes = try (dict["routes"] as? [[String: Any]] ?? []).map { d -> FlutterRoute in
      guard let path = d["path"] as? String else {
        throw NSError(domain: "VableFlutterPlugin", code: -1,
                      userInfo: [NSLocalizedDescriptionKey: "Invalid route format"])
      }
      return FlutterRoute(path: path, name: d["name"] as? String)
    }
    return ContextUpdate(intents: intents, intentStates: intentStates,
                         intentPrompts: intentPrompts, routes: routes)
  }
}

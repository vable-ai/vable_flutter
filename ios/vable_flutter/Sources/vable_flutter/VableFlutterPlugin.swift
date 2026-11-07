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

    case "setAccessToken":
      Vable.shared.setAccessToken((call.arguments as? [String: Any])?["accessToken"] as? String)
      result(true)

    case "setMicrophoneMuted":
      Vable.shared.setMicrophoneMuted((call.arguments as? [String: Any])?["muted"] as? Bool ?? false)
      result(true)

    case "setCallPillPosition":
      let position = (call.arguments as? [String: Any])?["position"] as? String
      Vable.shared.setCallPillPosition(position == "top" ? .top : .bottom)
      result(true)

    case "setCallStyle":
      let style = (call.arguments as? [String: Any])?["style"] as? String
      Vable.shared.setCallStyle(style == "pill" ? .pill : .glow)
      result(true)

    case "setGlowColor":
      if let argb = ((call.arguments as? [String: Any])?["color"] as? NSNumber)?.uint32Value {
        Vable.shared.setGlowColor(UIColor(
          red: CGFloat((argb >> 16) & 0xFF) / 255,
          green: CGFloat((argb >> 8) & 0xFF) / 255,
          blue: CGFloat(argb & 0xFF) / 255,
          alpha: CGFloat((argb >> 24) & 0xFF) / 255
        ))
      }
      result(true)

    case "setEndButtonVisible":
      Vable.shared.setEndButtonVisible((call.arguments as? [String: Any])?["visible"] as? Bool ?? true)
      result(true)

    case "updateFlutterScreenContext":
      handleUpdateFlutterScreenContext(call: call, result: result)

    case "updateIntents":
      handleUpdateIntents(call: call, result: result)

    case "sendToolResult":
      handleSendToolResult(call: call, result: result)

    case "getScreenFrames":
      result(Vable.shared.screenFramesConfig?.dictionary)

    case "sendScreenFrame":
      handleSendScreenFrame(call: call, result: result)

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
      try Vable.shared.initialize(
        publicKey: publicKey,
        environment: environment,
        accessToken: args["accessToken"] as? String
      )
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
        // Flutter scans its own widget tree. The UIKit scanner would overwrite it
        // with the single view Flutter renders into.
        try await Vable.shared.startVoiceChat(
          from: viewController,
          config: Vable.VoiceChatConfig(autoStartScreenScanning: false)
        )
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
    // Sent as is. Parsing it dropped intent parameters, so the agent never got
    // element ids, and rejected the intent states Dart sends. The server takes
    // routes as plain paths, and refuses the whole update if they aren't.
    var context = contextUpdateMap
    context["routes"] = (contextUpdateMap["routes"] as? [[String: Any]] ?? []).compactMap { $0["path"] as? String }
    Vable.shared.updateIntents(ContextUpdate(rawJson: context))
    result(true)
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

  /// Encodes Dart's masked RGBA frame as JPEG off the main thread, and sends it through the
  /// SDK. Answers once it's handed over, so Dart keeps one frame in flight.
  private func handleSendScreenFrame(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
          let rgba = (args["rgba"] as? FlutterStandardTypedData)?.data,
          let width = args["width"] as? Int,
          let height = args["height"] as? Int,
          let header = args["header"] as? String,
          width > 0, height > 0, rgba.count >= width * height * 4 else {
      result(FlutterError(code: "MISSING_ARGUMENT", message: "rgba, width, height and header are required", details: nil))
      return
    }
    DispatchQueue.global(qos: .utility).async {
      let jpeg = Self.jpeg(rgba: rgba, width: width, height: height)
      DispatchQueue.main.async {
        guard let jpeg = jpeg else {
          result(false)
          return
        }
        let payload = VableScreenFrame.payload(header: Data(header.utf8), jpeg: jpeg)
        result(Vable.shared.sendScreenFrame(payload))
      }
    }
  }

  /// The frame is opaque, so its alpha is skipped.
  private static func jpeg(rgba: Data, width: Int, height: Int) -> Data? {
    guard let provider = CGDataProvider(data: rgba as CFData),
          let space = CGColorSpace(name: CGColorSpace.sRGB),
          let image = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: space,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
          ) else { return nil }
    return UIImage(cgImage: image).jpegData(compressionQuality: 0.5)
  }

  // MARK: - VableNavigationDelegate

  public func onNavigateRequested(url: String) {
    onNavigateRequested(url: url, toolId: nil)
  }

  // The SDK calls these with the ID of the agent's tool call, which Dart sends back with
  // its result. Against an SDK without them, the methods above are called instead.
  public func onNavigateRequested(url: String, toolId: String?) {
    var args: [String: Any] = ["url": url]
    if let toolId = toolId { args["toolId"] = toolId }
    DispatchQueue.main.async { [weak self] in
      self?.channel?.invokeMethod("onNavigate", arguments: args)
    }
  }

  public func onIntent(id: String, parameters: [String: Any]) {
    onIntent(id: id, parameters: parameters, toolId: nil)
  }

  public func onIntent(id: String, parameters: [String: Any], toolId: String?) {
    var args: [String: Any] = ["id": id, "parameters": parameters]
    if let toolId = toolId { args["toolId"] = toolId }
    DispatchQueue.main.async { [weak self] in
      self?.channel?.invokeMethod("onIntent", arguments: args)
    }
  }

  public func onVoiceChatEnded() {
    DispatchQueue.main.async { [weak self] in
      self?.channel?.invokeMethod("onVoiceChatEnded", arguments: nil)
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
}

import Flutter
import UIKit
import VableAI

public class VableFlutterPlugin: NSObject, FlutterPlugin, VableNavigationDelegate, VableChatDelegate {

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
    Vable.shared.setChatDelegate(instance)
    Logger.shared.debug("Plugin registered")
  }

  // MARK: - Method Call Handler

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getPlatformVersion":
      result("iOS " + UIDevice.current.systemVersion)

    case "initialize":
      handleInitialize(call: call, result: result)

    case "log":
      handleLog(call: call, result: result)

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

    case "cancelTurn":
      Task { @MainActor in Vable.shared.cancelTurn() }
      result(true)

    case "say":
      let text = (call.arguments as? [String: Any])?["text"] as? String ?? ""
      Task { @MainActor in Vable.shared.say(text) }
      result(true)

    case "setCallStyle":
      let style = (call.arguments as? [String: Any])?["style"] as? String
      Vable.shared.setCallStyle(VableCallStyle(rawValue: style ?? "") ?? .glow)
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

    case "openChat":
      guard isInitialized else {
        result(FlutterError(code: "NOT_INITIALIZED", message: "Vable SDK not initialized. Call initialize() first.", details: nil))
        return
      }
      Task { @MainActor in
        // Flutter scans its own widget tree, as for calls
        Vable.shared.openChat(config: Vable.VoiceChatConfig(autoStartScreenScanning: false))
        result(true)
      }

    case "closeChat":
      Task { @MainActor in
        Vable.shared.closeChat()
        result(true)
      }

    case "isChatOpen":
      result(Vable.shared.isChatOpen)

    case "sendChatMessage":
      guard let text = (call.arguments as? [String: Any])?["text"] as? String else {
        result(FlutterError(code: "MISSING_ARGUMENT", message: "text is required", details: nil))
        return
      }
      Task { @MainActor in
        do {
          try await Vable.shared.sendMessage(text)
          result(true)
        } catch let error as VableError {
          result(FlutterError(code: self.vableErrorCode(error), message: error.localizedDescription, details: nil))
        } catch {
          result(FlutterError(code: "CONNECTION_ERROR", message: error.localizedDescription, details: nil))
        }
      }

    case "getChatMessages":
      result(Vable.shared.chatMessages.map { $0.toDictionary() })

    case "startNewChat":
      Task { @MainActor in
        Vable.shared.startNewChat()
        result(true)
      }

    case "setChatButtonVisible":
      Vable.shared.setChatButtonVisible((call.arguments as? [String: Any])?["visible"] as? Bool ?? true)
      result(true)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Method Handlers

  /// A line from the Dart side's VableLogger. Recorded for the client logs only; Dart has
  /// already printed it.
  private func handleLog(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
          let message = args["message"] as? String else {
      result(nil)
      return
    }
    let level = VableLogLevel(rawValue: args["level"] as? String ?? "") ?? .info
    let tag = args["tag"] as? String ?? "flutter"
    let fields = args["fields"] as? [String: String] ?? [:]
    Logger.shared.record(level: level, message: message, tag: tag, fields: fields)
    result(nil)
  }

  private func handleInitialize(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
          let publicKey = args["publicKey"] as? String else {
      result(FlutterError(code: "MISSING_ARGUMENT", message: "publicKey is required", details: nil))
      return
    }
    let debugLogging = args["debugLogging"] as? Bool ?? false
    Logger.shared.isDebugEnabled = debugLogging
    if let wrapperVersion = args["wrapperVersion"] as? String {
      Logger.shared.setWrapper(name: "flutter", version: wrapperVersion)
    }

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
          // A call hung up while it connected returns without starting. Reporting it as
          // started told Dart a call had begun that was already over.
          let started = Vable.shared.isVoiceChatActive()
          Logger.shared.info(started ? "Voice chat started successfully" : "Voice chat ended before it started")
          result(started)
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

  public func onVoiceChatStarted() {
    DispatchQueue.main.async { [weak self] in
      self?.channel?.invokeMethod("onVoiceChatStarted", arguments: nil)
    }
  }

  public func onAssistantText(_ text: String, isFinal: Bool) {
    DispatchQueue.main.async { [weak self] in
      self?.channel?.invokeMethod("onAssistantText", arguments: ["text": text, "isFinal": isFinal])
    }
  }

  public func onAgentState(_ state: String) {
    channel?.invokeMethod("onAgentState", arguments: ["state": state])
  }

  public func onUserTranscript(_ text: String, isFinal: Bool) {
    channel?.invokeMethod("onUserTranscript", arguments: ["text": text, "isFinal": isFinal])
  }

  public func onUserSpeechStarted() {
    channel?.invokeMethod("onUserSpeechStarted", arguments: nil)
  }

  public func onUserInterrupted() {
    channel?.invokeMethod("onUserInterrupted", arguments: nil)
  }

  public func onVoiceLevels(agent: Float, user: Float) {
    DispatchQueue.main.async { [weak self] in
      self?.channel?.invokeMethod("onVoiceLevels", arguments: ["agent": agent, "user": user])
    }
  }

  // MARK: - VableChatDelegate

  public func vableChatDidUpdate(_ messages: [VableChatMessage]) {
    let maps = messages.map { $0.toDictionary() }
    DispatchQueue.main.async { [weak self] in
      self?.channel?.invokeMethod("onChatUpdated", arguments: ["messages": maps])
    }
  }

  public func vableChatDidFail(_ code: String) {
    DispatchQueue.main.async { [weak self] in
      self?.channel?.invokeMethod("onChatError", arguments: ["code": code])
    }
  }

  public func vableChatDidOpen() {
    DispatchQueue.main.async { [weak self] in
      self?.channel?.invokeMethod("onChatOpened", arguments: nil)
    }
  }

  public func vableChatDidClose() {
    DispatchQueue.main.async { [weak self] in
      self?.channel?.invokeMethod("onChatClosed", arguments: nil)
    }
  }

  // MARK: - Cleanup

  public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
    channel?.setMethodCallHandler(nil)
    channel = nil
    Vable.shared.setNavigationDelegate(nil)
    Vable.shared.setChatDelegate(nil)
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
    case .chatTurnInProgress:       return "CHAT_BUSY"
    }
  }
}

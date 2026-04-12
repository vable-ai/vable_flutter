import Flutter
import UIKit
import VableAI

public class VableFlutterPlugin: NSObject, FlutterPlugin {

    private var channel: FlutterMethodChannel?

    // MARK: - Registration

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "vable_flutter", binaryMessenger: registrar.messenger())
        let instance = VableFlutterPlugin()
        instance.channel = channel
        registrar.addMethodCallDelegate(instance, channel: channel)

        // Register event callback to forward SDK events back to Flutter
        Vable.shared.setNavigationDelegate(instance)
    }

    // MARK: - Method Channel Handler

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {

        case "getPlatformVersion":
            result("iOS " + UIDevice.current.systemVersion)

        case "initialize":
            guard let args = call.arguments as? [String: Any],
                  let publicKey = args["publicKey"] as? String else {
                result(FlutterError(code: "MISSING_ARGUMENT", message: "publicKey is required", details: nil))
                return
            }
            let environment: Vable.VableEnvironment
            if let envString = args["environment"] as? String, envString == "dev" {
                environment = .development
            } else {
                environment = .production
            }
            do {
                try Vable.shared.initialize(publicKey: publicKey, environment: environment)
                result(true)
            } catch {
                result(FlutterError(code: "INITIALIZATION_ERROR", message: error.localizedDescription, details: nil))
            }

        case "startVoiceChat":
            guard let viewController = topViewController() else {
                result(FlutterError(code: "NO_VIEW_CONTROLLER", message: "No view controller available", details: nil))
                return
            }
            Task {
                do {
                    try await Vable.shared.startVoiceChat(from: viewController)
                    DispatchQueue.main.async { result(true) }
                } catch {
                    DispatchQueue.main.async {
                        result(FlutterError(code: "START_ERROR", message: error.localizedDescription, details: nil))
                    }
                }
            }

        case "endVoiceChat":
            Task { @MainActor in
                Vable.shared.endVoiceChat()
                result(true)
            }

        case "isVoiceChatActive":
            result(Vable.shared.isVoiceChatActive())

        case "updateFlutterScreenContext":
            guard let args = call.arguments as? [String: Any],
                  let screenContext = args["screenContext"] as? [String: Any] else {
                result(FlutterError(code: "MISSING_ARGUMENT", message: "screenContext is required", details: nil))
                return
            }
            Vable.shared.updateFlutterScreenContext(screenContext)
            result(true)

        case "updateIntents":
            guard let args = call.arguments as? [String: Any],
                  let contextUpdateMap = args["contextUpdate"] as? [String: Any] else {
                result(FlutterError(code: "MISSING_ARGUMENT", message: "contextUpdate is required", details: nil))
                return
            }
            Vable.shared.updateIntents(parseContextUpdate(from: contextUpdateMap))
            result(true)

        case "sendToolResult":
            guard let args = call.arguments as? [String: Any],
                  let toolName = args["toolName"] as? String,
                  let toolResult = args["result"] as? String else {
                result(FlutterError(code: "MISSING_ARGUMENT", message: "toolName and result are required", details: nil))
                return
            }
            Vable.shared.sendToolResult(toolName: toolName, toolId: args["toolId"] as? String, result: toolResult)
            result(true)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Private Helpers

    /// Walks up the presentation stack to find the topmost view controller
    private func topViewController() -> UIViewController? {
        let keyWindow = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first(where: { $0.isKeyWindow })

        var vc = keyWindow?.rootViewController
        while let presented = vc?.presentedViewController {
            vc = presented
        }
        return vc
    }

    /// Parses the Flutter contextUpdate map into a native ContextUpdate model
    private func parseContextUpdate(from map: [String: Any]) -> ContextUpdate {
        let intents = (map["intents"] as? [[String: Any]] ?? []).compactMap { d -> VableIntent? in
            guard let name = d["name"] as? String else { return nil }
            return VableIntent(id: d["id"] as? String ?? name, name: name, description: d["description"] as? String)
        }

        let intentStates = (map["intentStates"] as? [[String: Any]] ?? []).compactMap { d -> IntentState? in
            guard let intentId = d["intentId"] as? String,
                  let state = d["state"] as? String else { return nil }
            return IntentState(intentId: intentId, state: state, metadata: d["metadata"] as? [String: Any])
        }

        let intentPrompts = (map["intentPrompts"] as? [[String: Any]] ?? []).compactMap { d -> IntentPrompt? in
            guard let intentId = d["intentId"] as? String,
                  let prompt = d["prompt"] as? String else { return nil }
            return IntentPrompt(intentId: intentId, prompt: prompt, context: d["context"] as? String)
        }

        let routes = (map["routes"] as? [[String: Any]] ?? []).compactMap { d -> FlutterRoute? in
            guard let path = d["path"] as? String else { return nil }
            return FlutterRoute(path: path, name: d["name"] as? String)
        }

        return ContextUpdate(intents: intents, intentStates: intentStates, intentPrompts: intentPrompts, routes: routes)
    }
}

// MARK: - VableNavigationDelegate

extension VableFlutterPlugin: VableNavigationDelegate {

    /// Forwards navigate tool use events from the AI to the Flutter layer
    public func onNavigateRequested(url: String) {
        DispatchQueue.main.async { [weak self] in
            self?.channel?.invokeMethod("onNavigate", arguments: ["url": url])
        }
    }

    /// Forwards custom intent tool use events from the AI to the Flutter layer
    public func onIntent(id: String, parameters: [String: Any]) {
        DispatchQueue.main.async { [weak self] in
            self?.channel?.invokeMethod("onIntent", arguments: ["id": id, "parameters": parameters])
        }
    }
}

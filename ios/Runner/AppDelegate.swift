import Flutter
import UIKit
import Vision

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private(set) var layoutChannel: FlutterMethodChannel?
  private(set) var roomToolbarActions: [String: Bool] = [:]

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let layout = FlutterMethodChannel(
      name: "donglgewi/layout",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    layoutChannel = layout
    layout.setMethodCallHandler { [weak self] call, result in
      let controller = self?.roomController
      switch call.method {
      case "roomToolbarVisible":
        result(controller?.roomToolbarVisible ?? false)
      case "roomToolbarActions":
        self?.roomToolbarActions = call.arguments as? [String: Bool] ?? [:]
        controller?.updateRoomToolbar()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    let channel = FlutterMethodChannel(
      name: "donglgewi/photos",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      guard call.method == "analyze" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let path = call.arguments as? String else {
        result(FlutterError(code: "invalid_path", message: "An image path is required.", details: nil))
        return
      }
      DispatchQueue.global(qos: .userInitiated).async {
        let findings = Self.classifyPhoto(at: URL(fileURLWithPath: path))
        DispatchQueue.main.async { result(findings) }
      }
    }
  }

  private var roomController: DonglgewiViewController? {
    UIApplication.shared.connectedScenes.compactMap { scene in
      let navigation = (scene as? UIWindowScene)?.keyWindow?.rootViewController as? UINavigationController
      return navigation?.topViewController as? DonglgewiViewController
    }.first
  }

  private static func classifyPhoto(at url: URL) -> Any {
    let source = VNImageRequestHandler(url: url, options: [:])
    let classification = VNClassifyImageRequest()
    do {
      try source.perform([classification])
      return (classification.results ?? [])
        .filter { $0.confidence >= 0.35 }
        .sorted { $0.confidence > $1.confidence }
        .prefix(5)
        .map { $0.identifier.replacingOccurrences(of: "_", with: " ") }
    } catch {
      return FlutterError(code: "analysis_failed", message: "Image analysis failed.", details: nil)
    }
  }
}

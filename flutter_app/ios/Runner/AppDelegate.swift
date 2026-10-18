import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // iOS relaunched the app in the background because of a location event
    // (the ride was in progress when the system closed the app).
    if launchOptions?[.location] != nil {
      MotoDashNativeBridge.shared.resumeRelaunchMonitor()
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "MotoDashNativeBridge") {
      MotoDashNativeBridge.shared.register(messenger: registrar.messenger())
    }
  }
}

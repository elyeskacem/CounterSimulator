import SwiftUI

/// Runs on every launch, including the background relaunch iOS performs after a
/// significant location change. Touching the engine here makes it resume tracking
/// even when no screen is ever shown.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        _ = RideEngine.shared
        return true
    }
}

@main
struct MotoDashApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var engine = RideEngine.shared

    var body: some Scene {
        WindowGroup {
            DashboardView()
                .environmentObject(engine)
                .preferredColorScheme(.dark)
        }
    }
}

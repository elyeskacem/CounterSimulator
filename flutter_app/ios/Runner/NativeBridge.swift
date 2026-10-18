import Flutter
import UIKit
import CoreLocation
import ActivityKit

/// The Swift half of the Flutter app. Dart talks to it through the
/// "motodash/native" channel (see lib/native_bridge.dart) for the things Flutter
/// can't do on its own:
///   - the Dynamic Island / Lock Screen Live Activity (ActivityKit)
///   - the "Always" location permission
///   - waking the app up again after iOS terminated it (significant-change monitor)
final class MotoDashNativeBridge: NSObject, CLLocationManagerDelegate {
    static let shared = MotoDashNativeBridge()

    private var channel: FlutterMethodChannel?
    private var activity: Activity<RideActivityAttributes>?
    private let locationManager = CLLocationManager()

    private override init() {
        super.init()
        locationManager.delegate = self
    }

    func register(messenger: FlutterBinaryMessenger) {
        let channel = FlutterMethodChannel(name: "motodash/native", binaryMessenger: messenger)
        channel.setMethodCallHandler { [weak self] call, result in
            self?.handle(call, result: result)
        }
        self.channel = channel

        // The ↻ button in the expanded Dynamic Island runs inside this process.
        IntentBridge.onCycle = { [weak self] in
            DispatchQueue.main.async {
                self?.channel?.invokeMethod("cycleMode", arguments: nil)
            }
        }
        adoptExistingActivity()
    }

    /// Called from AppDelegate when iOS relaunched the app because of a location event.
    func resumeRelaunchMonitor() {
        if CLLocationManager.significantLocationChangeMonitoringAvailable() {
            locationManager.startMonitoringSignificantLocationChanges()
        }
    }

    // MARK: - Channel

    private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any] ?? [:]
        switch call.method {
        case "activityStart":
            let started = (args["startedAt"] as? NSNumber)?.doubleValue ?? Date().timeIntervalSince1970 * 1000
            let state = contentState(args["state"] as? [String: Any] ?? [:])
            result(startActivity(startedAt: Date(timeIntervalSince1970: started / 1000), state: state))

        case "activityUpdate":
            let state = contentState(args["state"] as? [String: Any] ?? [:])
            if let activity = activity {
                Task { await activity.update(ActivityContent(state: state, staleDate: nil)) }
            }
            result(nil)

        case "activityEnd":
            let state = contentState(args["state"] as? [String: Any] ?? [:])
            if let activity = activity {
                self.activity = nil
                Task { await activity.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: .immediate) }
            }
            result(nil)

        case "activityIsActive":
            adoptExistingActivity()
            result(activity?.activityState == .active)

        case "requestAlways":
            locationManager.requestAlwaysAuthorization()
            result(nil)

        case "setRelaunchMonitor":
            let enabled = args["enabled"] as? Bool ?? false
            if enabled {
                resumeRelaunchMonitor()
            } else {
                locationManager.stopMonitoringSignificantLocationChanges()
            }
            result(nil)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Live Activity

    private func contentState(_ d: [String: Any]) -> RideActivityAttributes.ContentState {
        func int(_ key: String) -> Int { (d[key] as? NSNumber)?.intValue ?? 0 }
        func dbl(_ key: String) -> Double { (d[key] as? NSNumber)?.doubleValue ?? 0 }
        return RideActivityAttributes.ContentState(
            speedKmh: int("speedKmh"),
            rideKm: dbl("rideKm"),
            tripKm: dbl("tripKm"),
            odoKm: dbl("odoKm"),
            fuelLeftKm: int("fuelLeftKm"),
            oilLeftKm: int("oilLeftKm"),
            mode: IslandMode(rawValue: d["mode"] as? String ?? "") ?? .rideKm
        )
    }

    private func startActivity(startedAt: Date, state: RideActivityAttributes.ContentState) -> [String: Any] {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            return ["ok": false, "message": "Turn on Live Activities in iOS Settings > MotoDash to see the ride in the Dynamic Island."]
        }
        for old in Activity<RideActivityAttributes>.activities {
            Task { await old.end(nil, dismissalPolicy: .immediate) }
        }
        activity = nil
        do {
            activity = try Activity.request(
                attributes: RideActivityAttributes(startedAt: startedAt),
                content: ActivityContent(state: state, staleDate: nil),
                pushType: nil
            )
            return ["ok": true]
        } catch {
            return ["ok": false, "message": error.localizedDescription]
        }
    }

    /// After a relaunch the activity from the previous run may still be on screen.
    private func adoptExistingActivity() {
        if activity == nil {
            activity = Activity<RideActivityAttributes>.activities.first { $0.activityState == .active }
        }
    }

    // MARK: - CLLocationManagerDelegate (only here to wake the app up)

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {}

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}

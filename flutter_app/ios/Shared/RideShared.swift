import Foundation
import ActivityKit
import AppIntents

// Compiled into BOTH the app and the Live Activity extension.
// Keep this file free of SwiftUI and of anything that only exists in one target.

/// What the Dynamic Island / Lock Screen shows as its main value.
enum IslandMode: String, Codable, CaseIterable, Identifiable, Hashable {
    case rideKm      // km since the last "Start ride" (default)
    case speed
    case tripKm      // the manual trip meter
    case odometer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rideKm: return "Ride distance"
        case .speed: return "Speed"
        case .tripKm: return "Trip"
        case .odometer: return "Odometer"
        }
    }

    var detail: String {
        switch self {
        case .rideKm: return "km since you tapped Start ride"
        case .speed: return "current speed in km/h"
        case .tripKm: return "your trip meter"
        case .odometer: return "total km on the bike"
        }
    }

    var symbol: String {
        switch self {
        case .rideKm: return "road.lanes"
        case .speed: return "speedometer"
        case .tripKm: return "flag.checkered"
        case .odometer: return "gauge"
        }
    }

    var unit: String {
        return self == .speed ? "km/h" : "km"
    }

    var next: IslandMode {
        let all = IslandMode.allCases
        let index = all.firstIndex(of: self) ?? 0
        return all[(index + 1) % all.count]
    }
}

struct RideActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var speedKmh: Int
        var rideKm: Double
        var tripKm: Double
        var odoKm: Double
        var fuelLeftKm: Int
        var oilLeftKm: Int
        var mode: IslandMode
    }

    var startedAt: Date
}

extension RideActivityAttributes.ContentState {
    var primaryText: String {
        switch mode {
        case .rideKm: return String(format: "%.1f", rideKm)
        case .speed: return "\(speedKmh)"
        case .tripKm: return String(format: "%.1f", tripKm)
        case .odometer: return String(format: "%.0f", odoKm)
        }
    }

    var speedText: String { "\(speedKmh)" }
    var rideText: String { String(format: "%.1f", rideKm) }
    var tripText: String { String(format: "%.1f", tripKm) }
    var odoText: String { String(format: "%.0f", odoKm) }
}

/// Bridge so the Live Activity button (which runs inside the app process,
/// because the intent is a LiveActivityIntent) can reach the ride engine.
enum IntentBridge {
    static var onCycle: (() -> Void)?
}

/// Button in the expanded Dynamic Island: switches what the island shows.
struct CycleIslandModeIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Change display"

    init() {}

    func perform() async throws -> some IntentResult {
        IntentBridge.onCycle?()
        return .result()
    }
}

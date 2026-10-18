import Foundation

// All structs decode with defaults, so adding a field in a later version
// never makes an older saved file unreadable.

extension KeyedDecodingContainer {
    func value<T: Decodable>(_ key: Key, _ fallback: T) -> T {
        return (try? decodeIfPresent(T.self, forKey: key)) ?? fallback
    }
}

struct Trip: Codable, Equatable {
    var km = 0.0
    var movingMs = 0.0
    var maxKmh = 0.0
    var startedAt = Date()

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        km = c.value(.km, 0.0)
        movingMs = c.value(.movingMs, 0.0)
        maxKmh = c.value(.maxKmh, 0.0)
        startedAt = c.value(.startedAt, Date())
    }
}

struct Flags: Codable, Equatable {
    var milestone = 10               // last 1000-km milestone already announced
    var oilWarnTarget: Double? = nil // "oil soon" already sent for this odometer target
    var oilDueTarget: Double? = nil  // "oil due" already sent for this odometer target
    var oilOverdueStep = 0
    var fuelWarned = false
    var fuelEmpty = false

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        milestone = c.value(.milestone, 10)
        oilWarnTarget = (try? c.decodeIfPresent(Double.self, forKey: .oilWarnTarget)) ?? nil
        oilDueTarget = (try? c.decodeIfPresent(Double.self, forKey: .oilDueTarget)) ?? nil
        oilOverdueStep = c.value(.oilOverdueStep, 0)
        fuelWarned = c.value(.fuelWarned, false)
        fuelEmpty = c.value(.fuelEmpty, false)
    }
}

struct Settings: Codable, Equatable {
    var oilInterval = 1000.0
    var oilWarn = 100.0
    var fuelPerFill = 220.0
    var fuelPrice = 20.0
    var fuelWarn = 20.0
    var sound = true
    var keepScreenOn = false
    var gapFill = true
    var sim = false
    var simMul = 1.0
    var islandMode = IslandMode.rideKm

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        oilInterval = c.value(.oilInterval, 1000.0)
        oilWarn = c.value(.oilWarn, 100.0)
        fuelPerFill = c.value(.fuelPerFill, 220.0)
        fuelPrice = c.value(.fuelPrice, 20.0)
        fuelWarn = c.value(.fuelWarn, 20.0)
        sound = c.value(.sound, true)
        keepScreenOn = c.value(.keepScreenOn, false)
        gapFill = c.value(.gapFill, true)
        sim = c.value(.sim, false)
        simMul = c.value(.simMul, 1.0)
        islandMode = c.value(.islandMode, IslandMode.rideKm)
    }
}

/// Last accepted GPS position of the current ride. Saved so that, if iOS
/// terminates the app and relaunches it, the distance covered in between
/// can be estimated instead of lost.
struct Anchor: Codable, Equatable {
    var lat: Double
    var lon: Double
    var time: Date
}

struct AppState: Codable, Equatable {
    var odoKm = 10820.0        // total km on the bike
    var fuelKm = 150.0         // estimated range left in the tank
    var kmSinceFill = 0.0
    var lastOilKm = 10000.0    // odometer at last oil change -> next at 11 000
    var appKm = 0.0            // distance measured by this app
    var fuelSpent = 0.0        // DT
    var rideKm = 0.0           // km since the last "Start ride"
    var rideStartedAt: Date? = nil
    var isRiding = false
    var anchor: Anchor? = nil
    var trip = Trip()
    var flags = Flags()
    var settings = Settings()

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        odoKm = c.value(.odoKm, 10820.0)
        fuelKm = c.value(.fuelKm, 150.0)
        kmSinceFill = c.value(.kmSinceFill, 0.0)
        lastOilKm = c.value(.lastOilKm, 10000.0)
        appKm = c.value(.appKm, 0.0)
        fuelSpent = c.value(.fuelSpent, 0.0)
        rideKm = c.value(.rideKm, 0.0)
        rideStartedAt = (try? c.decodeIfPresent(Date.self, forKey: .rideStartedAt)) ?? nil
        isRiding = c.value(.isRiding, false)
        anchor = (try? c.decodeIfPresent(Anchor.self, forKey: .anchor)) ?? nil
        trip = c.value(.trip, Trip())
        flags = c.value(.flags, Flags())
        settings = c.value(.settings, Settings())
    }

    var nextOilKm: Double { lastOilKm + settings.oilInterval }
    var oilLeftKm: Double { nextOilKm - odoKm }
}

struct RideEvent: Codable, Identifiable, Hashable {
    enum Kind: String, Codable {
        case fuel, oil, trip, milestone, gap, edit, ride, other
        case importBackup = "import"
    }

    var id = UUID()
    var at = Date()
    var kind: Kind
    var odo: Double?
    var note: String
}

enum AlertLevel {
    case ok, info, warn, danger
}

struct Toast: Identifiable {
    let id = UUID()
    let title: String
    let body: String
    let level: AlertLevel
}

enum GPSStatus {
    case off, searching, good, weak, denied, sim
}

// MARK: - Formatting

enum Fmt {
    private static let grouping: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.usesGroupingSeparator = true
        f.groupingSeparator = " "
        f.maximumFractionDigits = 0
        return f
    }()

    /// 11000 -> "11 000"
    static func int(_ v: Double) -> String {
        return grouping.string(from: NSNumber(value: v.rounded())) ?? "\(Int(v.rounded()))"
    }

    static func km1(_ v: Double) -> String {
        return String(format: "%.1f", v)
    }

    /// 1:52h for long, 12:05 for short
    static func duration(ms: Double) -> String {
        let totalSeconds = Int(ms / 1000)
        let minutes = totalSeconds / 60
        let hours = minutes / 60
        if hours > 0 {
            return String(format: "%d:%02dh", hours, minutes % 60)
        }
        return String(format: "%d:%02d", minutes, totalSeconds % 60)
    }
}

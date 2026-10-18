import Foundation

/// Backup file format. It is the SAME format as the web app's "Export backup",
/// so you can move your odometer, fuel and history between the website and
/// this app in either direction.
enum BackupCodec {
    enum BackupError: LocalizedError {
        case notABackup

        var errorDescription: String? {
            return "This file is not a MotoDash backup."
        }
    }

    // MARK: Export

    static func encode(state s: AppState, events: [RideEvent]) throws -> Data {
        var trip: [String: Any] = [:]
        trip["km"] = s.trip.km
        trip["movingMs"] = s.trip.movingMs
        trip["maxKmh"] = s.trip.maxKmh
        trip["startedAt"] = s.trip.startedAt.timeIntervalSince1970 * 1000

        var flags: [String: Any] = [:]
        flags["milestone"] = s.flags.milestone
        flags["oilWarnTarget"] = s.flags.oilWarnTarget ?? NSNull()
        flags["oilDueTarget"] = s.flags.oilDueTarget ?? NSNull()
        flags["oilOverdueStep"] = s.flags.oilOverdueStep
        flags["fuelWarned"] = s.flags.fuelWarned
        flags["fuelEmpty"] = s.flags.fuelEmpty

        var settings: [String: Any] = [:]
        settings["oilInterval"] = s.settings.oilInterval
        settings["oilWarn"] = s.settings.oilWarn
        settings["fuelPerFill"] = s.settings.fuelPerFill
        settings["fuelPrice"] = s.settings.fuelPrice
        settings["fuelWarn"] = s.settings.fuelWarn
        settings["sound"] = s.settings.sound
        settings["gapFill"] = s.settings.gapFill
        settings["islandMode"] = s.settings.islandMode.rawValue

        var state: [String: Any] = [:]
        state["version"] = 1
        state["odoKm"] = s.odoKm
        state["fuelKm"] = s.fuelKm
        state["kmSinceFill"] = s.kmSinceFill
        state["lastOilKm"] = s.lastOilKm
        state["appKm"] = s.appKm
        state["fuelSpent"] = s.fuelSpent
        state["trip"] = trip
        state["flags"] = flags
        state["settings"] = settings

        var eventList: [[String: Any]] = []
        for e in events.reversed() { // oldest first, like the web app
            var d: [String: Any] = [:]
            d["at"] = e.at.timeIntervalSince1970 * 1000
            d["type"] = e.kind.rawValue
            d["odo"] = e.odo ?? NSNull()
            d["note"] = e.note
            eventList.append(d)
        }

        var root: [String: Any] = [:]
        root["app"] = "motodash"
        root["exportedAt"] = ISO8601DateFormatter().string(from: Date())
        root["state"] = state
        root["events"] = eventList

        return try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
    }

    // MARK: Import

    static func decode(_ data: Data) throws -> (state: AppState, events: [RideEvent]) {
        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            root["app"] as? String == "motodash",
            let st = root["state"] as? [String: Any]
        else { throw BackupError.notABackup }

        var s = AppState()
        s.odoKm = number(st["odoKm"], s.odoKm)
        s.fuelKm = number(st["fuelKm"], s.fuelKm)
        s.kmSinceFill = number(st["kmSinceFill"], s.kmSinceFill)
        s.lastOilKm = number(st["lastOilKm"], s.lastOilKm)
        s.appKm = number(st["appKm"], s.appKm)
        s.fuelSpent = number(st["fuelSpent"], s.fuelSpent)

        if let t = st["trip"] as? [String: Any] {
            s.trip.km = number(t["km"], 0)
            s.trip.movingMs = number(t["movingMs"], 0)
            s.trip.maxKmh = number(t["maxKmh"], 0)
            let started = number(t["startedAt"], Date().timeIntervalSince1970 * 1000)
            s.trip.startedAt = Date(timeIntervalSince1970: started / 1000)
        }

        if let f = st["flags"] as? [String: Any] {
            s.flags.milestone = Int(number(f["milestone"], Double(s.flags.milestone)))
            s.flags.oilWarnTarget = optionalNumber(f["oilWarnTarget"])
            s.flags.oilDueTarget = optionalNumber(f["oilDueTarget"])
            s.flags.oilOverdueStep = Int(number(f["oilOverdueStep"], 0))
            s.flags.fuelWarned = (f["fuelWarned"] as? Bool) ?? false
            s.flags.fuelEmpty = (f["fuelEmpty"] as? Bool) ?? false
        } else {
            s.flags.milestone = Int(floor(s.odoKm / 1000))
        }

        if let c = st["settings"] as? [String: Any] {
            s.settings.oilInterval = number(c["oilInterval"], s.settings.oilInterval)
            s.settings.oilWarn = number(c["oilWarn"], s.settings.oilWarn)
            s.settings.fuelPerFill = number(c["fuelPerFill"], s.settings.fuelPerFill)
            s.settings.fuelPrice = number(c["fuelPrice"], s.settings.fuelPrice)
            s.settings.fuelWarn = number(c["fuelWarn"], s.settings.fuelWarn)
            s.settings.sound = (c["sound"] as? Bool) ?? true
            s.settings.gapFill = (c["gapFill"] as? Bool) ?? true
            if let raw = c["islandMode"] as? String, let mode = IslandMode(rawValue: raw) {
                s.settings.islandMode = mode
            }
        }

        var events: [RideEvent] = []
        if let list = root["events"] as? [[String: Any]] {
            for d in list {
                let at = number(d["at"], Date().timeIntervalSince1970 * 1000)
                let kind = RideEvent.Kind(rawValue: (d["type"] as? String) ?? "") ?? .other
                events.append(RideEvent(
                    at: Date(timeIntervalSince1970: at / 1000),
                    kind: kind,
                    odo: optionalNumber(d["odo"]),
                    note: (d["note"] as? String) ?? ""
                ))
            }
        }
        events.sort { $0.at > $1.at } // newest first in the app

        return (s, events)
    }

    private static func number(_ any: Any?, _ fallback: Double) -> Double {
        return (any as? NSNumber)?.doubleValue ?? fallback
    }

    private static func optionalNumber(_ any: Any?) -> Double? {
        return (any as? NSNumber)?.doubleValue
    }
}

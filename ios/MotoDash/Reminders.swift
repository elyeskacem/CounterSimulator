import Foundation

struct PendingAlert {
    let title: String
    let body: String
    let level: AlertLevel
    let id: String
}

struct ReminderResult {
    var alerts: [PendingAlert] = []
    var events: [RideEvent] = []
}

/// The fuel / oil / 1000-km rules. Pure logic: mutates the flags inside the
/// state it is given and returns what should be announced.
enum Reminders {
    static let overdueRepeatKm = 50.0

    static func check(_ s: inout AppState) -> ReminderResult {
        var result = ReminderResult()
        let st = s.settings

        // 1000-km milestones on the odometer
        var milestoneKm: Int? = nil
        let reached = Int(floor(s.odoKm / 1000))
        if reached > s.flags.milestone {
            s.flags.milestone = reached
            milestoneKm = reached * 1000
            result.events.append(RideEvent(
                kind: .milestone,
                odo: Double(reached * 1000),
                note: "\(Fmt.int(Double(reached * 1000))) km reached"
            ))
        }

        // Oil change (vidange)
        let nextOil = s.nextOilKm
        let oilLeft = nextOil - s.odoKm
        if oilLeft <= 0 {
            let step = Int(floor(-oilLeft / overdueRepeatKm))
            let first = s.flags.oilDueTarget != nextOil
            if first || step > s.flags.oilOverdueStep {
                s.flags.oilDueTarget = nextOil
                s.flags.oilWarnTarget = nextOil
                s.flags.oilOverdueStep = step

                let title: String
                if let m = milestoneKm {
                    title = "\(Fmt.int(Double(m))) km: oil change time!"
                } else if first {
                    title = "Oil change due (vidange)"
                } else {
                    title = "Oil change overdue by \(Int(-oilLeft)) km"
                }
                result.alerts.append(PendingAlert(
                    title: title,
                    body: "Total: \(Fmt.int(s.odoKm)) km. Change the oil, then tap “Oil changed”.",
                    level: .danger,
                    id: "oil"
                ))
                milestoneKm = nil // already announced inside the oil alert
            }
        } else if oilLeft <= st.oilWarn && s.flags.oilWarnTarget != nextOil {
            s.flags.oilWarnTarget = nextOil
            result.alerts.append(PendingAlert(
                title: "Oil change soon",
                body: "\(Int(ceil(oilLeft))) km left. Vidange at \(Fmt.int(nextOil)) km.",
                level: .warn,
                id: "oil"
            ))
        }

        if let m = milestoneKm {
            result.alerts.append(PendingAlert(
                title: "\(Fmt.int(Double(m))) km reached",
                body: "Total distance on the bike: \(Fmt.int(s.odoKm)) km.",
                level: .ok,
                id: "milestone"
            ))
        }

        // Fuel: one fill (220 km) = 20 DT
        let price = Fmt.int(st.fuelPrice)
        if s.fuelKm <= 0 && !s.flags.fuelEmpty {
            s.flags.fuelEmpty = true
            s.flags.fuelWarned = true
            result.alerts.append(PendingAlert(
                title: "Fuel: pay \(price) DT",
                body: "\(Int(s.kmSinceFill.rounded())) km since the last fill. Time to refuel.",
                level: .danger,
                id: "fuel"
            ))
        } else if s.fuelKm > 0 && s.fuelKm <= st.fuelWarn && !s.flags.fuelWarned {
            s.flags.fuelWarned = true
            result.alerts.append(PendingAlert(
                title: "Fuel low",
                body: "About \(Int(ceil(s.fuelKm))) km left. Plan to pay \(price) DT soon.",
                level: .warn,
                id: "fuel"
            ))
        }

        return result
    }

    /// Call after the fuel level or its thresholds were edited by hand.
    static func resetFuelFlags(_ s: inout AppState) {
        s.flags.fuelEmpty = s.fuelKm <= 0
        s.flags.fuelWarned = s.fuelKm <= s.settings.fuelWarn
    }

    /// Call after the oil interval / last change / warning distance were edited.
    static func resetOilFlags(_ s: inout AppState) {
        s.flags.oilWarnTarget = nil
        s.flags.oilDueTarget = nil
        s.flags.oilOverdueStep = 0
    }
}

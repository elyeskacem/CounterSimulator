import SwiftUI

/// Refuels, oil changes, rides, trips and milestones, newest first.
struct HistoryView: View {
    @EnvironmentObject var engine: RideEngine

    var body: some View {
        if engine.events.isEmpty {
            VStack(spacing: 6) {
                Spacer()
                Image(systemName: "clock.arrow.circlepath").font(.system(size: 32)).foregroundColor(Theme.muted)
                Text("No events yet").font(.headline)
                Text("Refuels, oil changes and rides will appear here.")
                    .font(.footnote).foregroundColor(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else {
            List(engine.events) { event in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: icon(for: event.kind))
                        .frame(width: 34, height: 34)
                        .background(Theme.panel2)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(title(for: event.kind)).font(.system(size: 15, weight: .semibold))
                            Spacer()
                            if let odo = event.odo {
                                Text("\(Fmt.int(odo)) km")
                                    .font(.system(size: 13, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                        }
                        Text(event.note).font(.system(size: 13)).foregroundColor(.secondary)
                        Text(event.at.formatted(date: .abbreviated, time: .shortened))
                            .font(.system(size: 12)).foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func icon(for kind: RideEvent.Kind) -> String {
        switch kind {
        case .fuel: return "fuelpump"
        case .oil: return "drop"
        case .trip: return "flag.checkered"
        case .ride: return "road.lanes"
        case .milestone: return "trophy"
        case .gap: return "antenna.radiowaves.left.and.right"
        case .edit: return "pencil"
        case .importBackup: return "square.and.arrow.down"
        case .other: return "circle"
        }
    }

    private func title(for kind: RideEvent.Kind) -> String {
        switch kind {
        case .fuel: return "Refuel"
        case .oil: return "Oil change"
        case .trip: return "Trip saved"
        case .ride: return "Ride"
        case .milestone: return "Milestone"
        case .gap: return "GPS gap"
        case .edit: return "Manual edit"
        case .importBackup: return "Backup restored"
        case .other: return "Event"
        }
    }
}

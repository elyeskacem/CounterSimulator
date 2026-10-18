import SwiftUI
import WidgetKit
import ActivityKit
import AppIntents

@main
struct MotoDashWidgetsBundle: WidgetBundle {
    var body: some Widget {
        RideLiveActivity()
    }
}

private let accent = Color(red: 0.17, green: 0.88, blue: 0.63)

struct RideLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RideActivityAttributes.self) { context in
            // Lock Screen / notification banner
            LockScreenRideView(state: context.state, startedAt: context.attributes.startedAt)
                .activityBackgroundTint(Color.black.opacity(0.85))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                // Long-press the island to get this expanded view.
                DynamicIslandExpandedRegion(.leading) {
                    StatBlock(title: context.state.mode.title.uppercased(),
                              value: context.state.primaryText,
                              unit: context.state.mode.unit,
                              big: true)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if context.state.mode == .speed {
                        StatBlock(title: "RIDE", value: context.state.rideText, unit: "km", big: false)
                    } else {
                        StatBlock(title: "SPEED", value: context.state.speedText, unit: "km/h", big: false)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 14) {
                        MiniStat(title: "TRIP", value: context.state.tripText, unit: "km")
                        MiniStat(title: "ODO", value: context.state.odoText, unit: "km")
                        MiniStat(title: "FUEL", value: "\(context.state.fuelLeftKm)", unit: "km")
                        MiniStat(title: "OIL", value: "\(context.state.oilLeftKm)", unit: "km")
                        Spacer(minLength: 0)
                        Button(intent: CycleIslandModeIntent()) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(accent)
                    }
                }
            } compactLeading: {
                Image(systemName: context.state.mode.symbol)
                    .foregroundStyle(accent)
            } compactTrailing: {
                Text(context.state.primaryText)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(maxWidth: 52, alignment: .trailing)
            } minimal: {
                Text(context.state.primaryText)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            .keylineTint(accent)
        }
    }
}

private struct StatBlock: View {
    let title: String
    let value: String
    let unit: String
    let big: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: big ? 34 : 24, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(unit)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct MiniStat: View {
    let title: String
    let value: String
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

private struct LockScreenRideView: View {
    let state: RideActivityAttributes.ContentState
    let startedAt: Date

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: state.mode.symbol).foregroundStyle(accent)
                    Text(state.mode.title.uppercased())
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text(state.primaryText)
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(state.mode.unit)
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 4) {
                row("Speed", "\(state.speedText) km/h")
                row("Ride", "\(state.rideText) km")
                row("Fuel", "\(state.fuelLeftKm) km")
                row("Oil", "\(state.oilLeftKm) km")
            }
        }
        .padding(16)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Text(label).font(.system(size: 12)).foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
    }
}

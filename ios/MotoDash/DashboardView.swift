import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var engine: RideEngine
    @Environment(\.scenePhase) private var scenePhase
    @State private var showSettings = false

    var body: some View {
        let s = engine.state

        ZStack(alignment: .top) {
            Theme.bg.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 12) {
                    statusBar(s)
                    banners(s)
                    GaugeView(speed: engine.speedKmh)
                    odometer(s)
                    tripCard(s)
                    HStack(alignment: .top, spacing: 12) {
                        fuelCard(s)
                        oilCard(s)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
            .scrollIndicators(.hidden)
            .safeAreaInset(edge: .bottom) { rideButton(s) }

            ToastOverlay()
        }
        .sheet(isPresented: $showSettings) {
            SettingsView().environmentObject(engine)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                engine.refreshNotificationStatus()
                engine.ensureLiveActivity()
            case .background:
                engine.flushToDisk()
            default:
                break
            }
            applyIdleTimer()
        }
        .onChange(of: s.settings.keepScreenOn) { _, _ in applyIdleTimer() }
        .onAppear { applyIdleTimer() }
    }

    private func applyIdleTimer() {
        UIApplication.shared.isIdleTimerDisabled = engine.state.settings.keepScreenOn && scenePhase == .active
    }

    // MARK: Status bar

    private func statusBar(_ s: AppState) -> some View {
        HStack {
            HStack(spacing: 8) {
                Circle().fill(gpsColor).frame(width: 9, height: 9)
                Text(engine.gpsText).font(.system(size: 13)).foregroundColor(Theme.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(context.date, format: .dateTime.hour().minute())
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
            }

            Button { showSettings = true } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 20))
                    .foregroundColor(Theme.muted)
                    .frame(width: 44, height: 44)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(minHeight: 44)
    }

    private var gpsColor: Color {
        switch engine.gpsStatus {
        case .off: return Color(hex: 0x3A4350)
        case .searching, .weak: return Theme.warn
        case .good: return Theme.accent
        case .denied: return Theme.danger
        case .sim: return Theme.info
        }
    }

    // MARK: Banners

    @ViewBuilder
    private func banners(_ s: AppState) -> some View {
        if s.oilLeftKm <= 0 {
            banner("Oil change (vidange) due: \(overdueText(s.oilLeftKm))")
        }
        if s.fuelKm <= 0 {
            banner("Fuel: pay \(Fmt.int(s.settings.fuelPrice)) DT now")
        }
    }

    private func overdueText(_ left: Double) -> String {
        return left <= -1 ? "\(Int(floor(-left))) km overdue" : "now"
    }

    private func banner(_ text: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(text).font(.system(size: 14, weight: .semibold))
            Spacer(minLength: 0)
        }
        .foregroundColor(Color(hex: 0xFF8080))
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Theme.danger.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.danger.opacity(0.5), lineWidth: 1))
    }

    // MARK: Odometer

    private func odometer(_ s: AppState) -> some View {
        let tenths = Int(floor(s.odoKm * 10))
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("ODO").font(.system(size: 12, design: .monospaced)).foregroundColor(Theme.muted)
            Text(String(format: "%06d", tenths / 10))
                .font(.system(size: 26, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
            Text(".\(tenths % 10)")
                .font(.system(size: 18, design: .monospaced))
                .foregroundColor(Theme.muted)
            Text("km").font(.system(size: 12)).foregroundColor(Theme.muted)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.line, lineWidth: 1))
    }

    // MARK: Trip

    private func tripCard(_ s: AppState) -> some View {
        let t = s.trip
        let avg = t.movingMs > 10_000 ? Int((t.km / (t.movingMs / 3_600_000)).rounded()) : 0
        return Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    cardTitle("TRIP")
                    Spacer()
                    ConfirmButton(armedTitle: "Tap again", action: { engine.resetTrip() }) {
                        Text("Reset")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                HStack(alignment: .lastTextBaseline) {
                    HStack(alignment: .lastTextBaseline, spacing: 6) {
                        Text(Fmt.km1(t.km)).font(.system(size: 34, weight: .bold, design: .monospaced))
                        Text("km").font(.system(size: 13)).foregroundColor(Theme.muted)
                    }
                    Spacer()
                    HStack(spacing: 18) {
                        stat("Time", Fmt.duration(ms: t.movingMs))
                        stat("Avg", "\(avg)")
                        stat("Max", "\(Int(t.maxKmh.rounded()))")
                    }
                }
                HStack {
                    Image(systemName: "road.lanes").foregroundColor(Theme.muted)
                    Text("This ride").font(.system(size: 12)).foregroundColor(Theme.muted)
                    Spacer()
                    Text("\(Fmt.km1(s.rideKm)) km")
                        .font(.system(size: 15, weight: .semibold, design: .monospaced))
                }
            }
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(label).font(.system(size: 11)).foregroundColor(Theme.muted)
            Text(value).font(.system(size: 17, weight: .semibold, design: .monospaced))
        }
    }

    private func cardTitle(_ text: String, icon: String? = nil) -> some View {
        HStack(spacing: 6) {
            if let icon = icon { Image(systemName: icon).font(.system(size: 12)) }
            Text(text).font(.system(size: 12, weight: .bold)).tracking(1.5)
        }
        .foregroundColor(Theme.muted)
    }

    // MARK: Fuel

    private func fuelCard(_ s: AppState) -> some View {
        let st = s.settings
        let left = max(0, s.fuelKm)
        let isEmpty = s.fuelKm <= 0
        let isLow = !isEmpty && s.fuelKm <= st.fuelWarn
        let tone = isEmpty ? Theme.danger : (isLow ? Theme.warn : Theme.accent)

        return Card(border: isEmpty ? Theme.danger.opacity(0.7) : (isLow ? Theme.warn.opacity(0.55) : Theme.line)) {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    cardTitle("FUEL", icon: "fuelpump")
                    Text("since fill \(Int(s.kmSinceFill.rounded())) km")
                        .font(.system(size: 12)).foregroundColor(Theme.muted)
                }
                Meter(fraction: left / max(1, st.fuelPerFill), color: tone)
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(Int(left.rounded(.down)))")
                        .font(.system(size: 26, weight: .bold, design: .monospaced))
                        .foregroundColor(isEmpty || isLow ? tone : .white)
                    Text("km left").font(.system(size: 13)).foregroundColor(Theme.muted)
                }
                ConfirmButton(armedTitle: "Confirm paid?", action: { engine.refuel() }) {
                    Text("Paid \(Fmt.int(st.fuelPrice)) DT")
                }
                .buttonStyle(ActionStyle())
            }
        }
    }

    // MARK: Oil

    private func oilCard(_ s: AppState) -> some View {
        let st = s.settings
        let left = s.oilLeftKm
        let isDue = left <= 0
        let isSoon = !isDue && left <= st.oilWarn
        let tone = isDue ? Theme.danger : (isSoon ? Theme.warn : Theme.accent)
        let leftText = left > -1 ? "\(max(0, Int(floor(left))))" : "−\(Int(floor(-left)))"

        return Card(border: isDue ? Theme.danger.opacity(0.7) : (isSoon ? Theme.warn.opacity(0.55) : Theme.line)) {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    cardTitle("OIL · VIDANGE", icon: "drop")
                    Text("next at \(Fmt.int(s.nextOilKm)) km")
                        .font(.system(size: 12)).foregroundColor(Theme.muted)
                }
                Meter(fraction: left / max(1, st.oilInterval), color: tone)
                VStack(alignment: .leading, spacing: 0) {
                    Text(leftText)
                        .font(.system(size: 26, weight: .bold, design: .monospaced))
                        .foregroundColor(isDue || isSoon ? tone : .white)
                    Text(left > -1 ? "km to change" : "km overdue")
                        .font(.system(size: 13)).foregroundColor(Theme.muted)
                }
                ConfirmButton(armedTitle: "Confirm?", action: { engine.oilChanged() }) {
                    Text("Oil changed")
                }
                .buttonStyle(ActionStyle())
            }
        }
    }

    // MARK: Ride button

    private func rideButton(_ s: AppState) -> some View {
        Button {
            if s.isRiding { engine.stopRide() } else { engine.startRide() }
        } label: {
            HStack(spacing: 10) {
                if s.isRiding {
                    RoundedRectangle(cornerRadius: 3).fill(Theme.danger).frame(width: 12, height: 12)
                } else {
                    Circle().fill(Color(hex: 0x04120C)).frame(width: 12, height: 12)
                }
                Text(s.isRiding ? "Stop ride" : (s.settings.sim ? "Start simulated ride" : "Start ride"))
                    .font(.system(size: 18, weight: .heavy))
            }
            .frame(maxWidth: .infinity, minHeight: 58)
            .foregroundColor(s.isRiding ? Color(hex: 0xFF8080) : Color(hex: 0x04120C))
            .background(s.isRiding ? Color(hex: 0x2A1416) : Theme.accent)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(s.isRiding ? Theme.danger.opacity(0.5) : Color.clear, lineWidth: 1)
            )
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .background(Theme.bg.opacity(0.92))
    }
}

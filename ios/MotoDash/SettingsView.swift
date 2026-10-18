import SwiftUI
import UIKit
import UserNotifications
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject var engine: RideEngine
    @Environment(\.dismiss) private var dismiss
    @State private var tab = 0
    @State private var exportFile: ExportFile?
    @State private var showImporter = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $tab) {
                    Text("Settings").tag(0)
                    Text("History").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                if tab == 0 {
                    settingsForm
                } else {
                    HistoryView()
                }
            }
            .navigationTitle(tab == 0 ? "Settings" : "History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
        .sheet(item: $exportFile) { file in
            ShareSheet(items: [file.url])
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
            if case .success(let url) = result {
                engine.importBackup(from: url)
            }
        }
    }

    private var settingsForm: some View {
        Form {
            displaySection
            alertsSection
            countersSection
            oilSection
            fuelSection
            gpsSection
            dataSection
            Section {
                Text("MotoDash · data stays on this phone")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
            }
            .listRowBackground(Color.clear)
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                                    to: nil, from: nil, for: nil)
                }
            }
        }
    }

    // MARK: Sections

    private var displaySection: some View {
        Section {
            Picker("Shows", selection: Binding(
                get: { engine.state.settings.islandMode },
                set: { engine.setIslandMode($0) }
            )) {
                ForEach(IslandMode.allCases) { mode in
                    VStack(alignment: .leading) {
                        Text(mode.title)
                        Text(mode.detail).font(.caption).foregroundColor(.secondary)
                    }
                    .tag(mode)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } header: {
            Text("Dynamic Island & Lock Screen")
        } footer: {
            Text("This is what the Dynamic Island shows while you ride. You can also change it without opening the app: touch and hold the Dynamic Island and tap the arrows button.")
        }
    }

    private var alertsSection: some View {
        Section("Alerts") {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Notifications")
                    Text(notificationHint).font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                if engine.notificationStatus == .notDetermined {
                    Button("Enable") { engine.requestNotifications() }
                } else if engine.notificationStatus == .denied {
                    Button("Open Settings") { openSystemSettings() }
                }
            }
            toggle("Sound on alerts", \.sound)
            toggle("Keep screen on while the app is open", \.keepScreenOn)
        }
    }

    private var countersSection: some View {
        Section("Counters") {
            NumberRow(title: "Odometer (km)", value: engine.value(of: .odometer)) { engine.set(.odometer, to: $0) }
            NumberRow(title: "Fuel range left (km)", value: engine.value(of: .fuelKm)) { engine.set(.fuelKm, to: $0) }
            NumberRow(title: "Last oil change at (km)", value: engine.value(of: .lastOil)) { engine.set(.lastOil, to: $0) }
        }
    }

    private var oilSection: some View {
        Section("Oil (vidange)") {
            NumberRow(title: "Change every (km)", value: engine.value(of: .oilInterval)) { engine.set(.oilInterval, to: $0) }
            NumberRow(title: "Warn when (km) left", value: engine.value(of: .oilWarn)) { engine.set(.oilWarn, to: $0) }
        }
    }

    private var fuelSection: some View {
        Section("Fuel") {
            NumberRow(title: "One fill = (km)", value: engine.value(of: .fuelPerFill)) { engine.set(.fuelPerFill, to: $0) }
            NumberRow(title: "One fill costs (DT)", value: engine.value(of: .fuelPrice)) { engine.set(.fuelPrice, to: $0) }
            NumberRow(title: "Warn when (km) left", value: engine.value(of: .fuelWarn)) { engine.set(.fuelWarn, to: $0) }
        }
    }

    private var gpsSection: some View {
        Section {
            toggle("Estimate distance during GPS gaps", \.gapFill)
            Toggle("Simulation mode (fake ride)", isOn: Binding(
                get: { engine.state.settings.sim },
                set: { engine.setSimulation($0) }
            ))
            Picker("Simulation speed-up", selection: Binding(
                get: { engine.state.settings.simMul },
                set: { v in engine.updateSettings { $0.simMul = v } }
            )) {
                Text("1×").tag(1.0)
                Text("10×").tag(10.0)
                Text("60×").tag(60.0)
                Text("300×").tag(300.0)
            }
            HStack {
                Text("Location permission")
                Spacer()
                Text(locationText).foregroundColor(.secondary)
            }
            if engine.locationAuth != .authorizedAlways {
                Button("Open Settings to choose “Always”") { openSystemSettings() }
            }
        } header: {
            Text("GPS")
        } footer: {
            Text("“Always” lets MotoDash restart itself and keep counting if iOS closes it while you ride.")
        }
    }

    private var dataSection: some View {
        Section("Data") {
            HStack {
                Text("Fuel spent total")
                Spacer()
                Text("\(Fmt.int(engine.state.fuelSpent)) DT").foregroundColor(.secondary)
            }
            HStack {
                Text("Distance tracked by the app")
                Spacer()
                Text("\(Fmt.km1(engine.state.appKm)) km").foregroundColor(.secondary)
            }
            Button("Export backup") {
                if let url = try? engine.exportBackupFile() {
                    exportFile = ExportFile(url: url)
                }
            }
            Button("Import backup (from this app or the website)") { showImporter = true }
            ConfirmButton(armedTitle: "Tap again to erase everything", action: { engine.factoryReset() }) {
                Text("Factory reset")
            }
            .foregroundColor(Theme.danger)
        }
    }

    // MARK: Helpers

    private func toggle(_ title: String, _ keyPath: WritableKeyPath<Settings, Bool>) -> some View {
        Toggle(title, isOn: Binding(
            get: { engine.state.settings[keyPath: keyPath] },
            set: { value in engine.updateSettings { $0[keyPath: keyPath] = value } }
        ))
    }

    private var notificationHint: String {
        switch engine.notificationStatus {
        case .authorized, .provisional, .ephemeral: return "Enabled"
        case .denied: return "Blocked: allow it in iOS Settings"
        default: return "Not enabled yet"
        }
    }

    private var locationText: String {
        switch engine.locationAuth {
        case .authorizedAlways: return "Always"
        case .authorizedWhenInUse: return "While Using"
        case .denied: return "Denied"
        case .restricted: return "Restricted"
        default: return "Not asked yet"
        }
    }

    private func openSystemSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}

import SwiftUI
import UIKit

enum Theme {
    static let bg = Color(hex: 0x07090C)
    static let panel = Color(hex: 0x10141A)
    static let panel2 = Color(hex: 0x161B23)
    static let line = Color(hex: 0x232A35)
    static let muted = Color(hex: 0x7D8896)
    static let accent = Color(hex: 0x2BE0A0)
    static let warn = Color(hex: 0xFFC83D)
    static let danger = Color(hex: 0xFF4D4D)
    static let info = Color(hex: 0x4DB8FF)

    static func color(for level: AlertLevel) -> Color {
        switch level {
        case .ok: return accent
        case .info: return info
        case .warn: return warn
        case .danger: return danger
        }
    }
}

extension Color {
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

/// Rounded dark panel used by Trip, Fuel and Oil.
struct Card<Content: View>: View {
    var border: Color = Theme.line
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.panel)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(border, lineWidth: 1)
            )
    }
}

/// Horizontal progress bar.
struct Meter: View {
    var fraction: Double
    var color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color(hex: 0x1A2029))
                Capsule()
                    .fill(color)
                    .frame(width: max(0, min(1, fraction)) * geo.size.width)
            }
        }
        .frame(height: 10)
    }
}

/// A button that needs two taps (it asks "sure?" for 3 seconds), so a bump or a
/// glove can't trigger a refuel, an oil change or a reset by accident.
struct ConfirmButton<Label: View>: View {
    let armedTitle: String
    let action: () -> Void
    @ViewBuilder var label: () -> Label
    @State private var armed = false

    var body: some View {
        Button {
            if armed {
                armed = false
                action()
            } else {
                armed = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { armed = false }
            }
        } label: {
            if armed {
                Text(armedTitle).fontWeight(.bold)
            } else {
                label()
            }
        }
        .tint(armed ? Theme.danger : nil)
    }
}

/// Pill-shaped action button style used on the cards.
struct ActionStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(configuration.isPressed ? Color(hex: 0x1F2631) : Theme.panel2)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.line, lineWidth: 1))
            .foregroundColor(.white)
    }
}

/// Numeric text field that commits when you leave it.
struct NumberRow: View {
    let title: String
    let value: Double
    let onCommit: (Double) -> Void

    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0", text: $text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(.system(size: 17, design: .monospaced))
                .frame(width: 120)
                .focused($focused)
                .onAppear { text = Self.format(value) }
                .onChange(of: focused) { _, isFocused in
                    if !isFocused { commit() }
                }
                .onChange(of: value) { _, newValue in
                    if !focused { text = Self.format(newValue) }
                }
        }
    }

    private func commit() {
        let cleaned = text.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)
        if let v = Double(cleaned), v.isFinite, v >= 0 {
            if v != value { onCommit(v) }
            text = Self.format(v)
        } else {
            text = Self.format(value)
        }
    }

    private static func format(_ v: Double) -> String {
        if v.rounded() == v { return String(Int(v)) }
        return String(format: "%.1f", v)
    }
}

/// System share sheet (used to export the backup file).
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        return UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

struct ExportFile: Identifiable {
    let id = UUID()
    let url: URL
}

/// Banners that slide in from the top for reminders and confirmations.
struct ToastOverlay: View {
    @EnvironmentObject var engine: RideEngine

    var body: some View {
        VStack(spacing: 8) {
            ForEach(engine.toasts) { toast in
                VStack(alignment: .leading, spacing: 2) {
                    Text(toast.title).font(.system(size: 15, weight: .bold))
                    if !toast.body.isEmpty {
                        Text(toast.body).font(.system(size: 13)).foregroundColor(Theme.muted)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(.ultraThickMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(alignment: .leading) {
                    Capsule().fill(Theme.color(for: toast.level)).frame(width: 4).padding(.vertical, 8)
                }
                .shadow(color: .black.opacity(0.4), radius: 10, y: 4)
                .onTapGesture { engine.dismissToast(toast.id) }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .animation(.easeOut(duration: 0.25), value: engine.toasts.count)
        .frame(maxWidth: 480)
    }
}

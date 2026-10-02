import AppKit
import SwiftUI
import WakefulCore

extension Color {
    /// Wakeful's accent: a warm coffee caramel that reads on light and dark backgrounds.
    static let wakeful = Color(red: 0.78, green: 0.47, blue: 0.22)
}

extension SessionMode {
    var symbol: String {
        switch self {
        case .awake: "cup.and.saucer.fill"
        case .awakeLidClosed: "laptopcomputer"
        }
    }
}

enum ShortDuration {
    /// "15m", "1h".
    static func label(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        return minutes < 60 ? "\(minutes)m" : "\(minutes / 60)h"
    }
}

struct PopoverView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            Divider()
            StatusSection(model: model)
                .padding(16)
            Divider()
            StartSection(model: model)
                .padding(16)
        }
        .frame(width: 320)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "cup.and.saucer.fill")
                .foregroundStyle(Color.wakeful)
            Text("Wakeful")
                .font(.headline)
            Spacer()
            Menu {
                Button("Settings…") { model.openSettings() }
                    .keyboardShortcut(",")
                Divider()
                Button("Quit Wakeful") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            } label: {
                Image(systemName: "gearshape")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Settings")
        }
    }
}

// MARK: - Status

private struct StatusSection: View {
    let model: AppModel

    var body: some View {
        if let session = model.session {
            active(session)
        } else {
            idle
        }
    }

    private var idle: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .strokeBorder(.quaternary, lineWidth: 6)
                Image(systemName: "cup.and.saucer")
                    .font(.system(size: 24))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 76, height: 76)
            VStack(alignment: .leading, spacing: 3) {
                Text("Off")
                    .font(.title2.weight(.semibold))
                Text("Your Mac sleeps normally.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    private func active(_ session: Session) -> some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                CountdownRing(fraction: model.fractionRemaining, text: DurationFormat.countdown(model.remaining))
                    .frame(width: 76, height: 76)
                VStack(alignment: .leading, spacing: 3) {
                    Label(session.mode.displayName, systemImage: session.mode.symbol)
                        .font(.headline)
                    Text("Ends at \(session.expiresAt.formatted(date: .omitted, time: .shortened))")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    if session.keepDisplayAwake {
                        Text("Display stays on")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                Button {
                    // Only the jump from +15 min animates. A per-second animation here kept
                    // SwiftUI rendering at full frame rate for the whole session.
                    withAnimation(.easeOut(duration: 0.35)) { model.extend() }
                } label: {
                    Label("15 min", systemImage: "plus")
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(!model.canExtend)
                .help("Add 15 minutes")

                Button {
                    model.stop()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .buttonStyle(SecondaryButtonStyle(foreground: .red))
            }
        }
    }
}

private struct CountdownRing: View {
    let fraction: Double
    let text: String

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.wakeful.opacity(0.18), lineWidth: 6)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(Color.wakeful, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(text)
                .font(.system(size: text.count > 5 ? 13 : 16, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
    }
}

// MARK: - Start

private struct StartSection: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(model.session == nil ? "Keep awake" : "Start a new session")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            HStack(spacing: 10) {
                ModeCard(
                    mode: .awake, title: "Awake", subtitle: "Stops idle sleep",
                    selected: model.selectedMode == .awake, enabled: true
                ) { model.selectedMode = .awake }
                ModeCard(
                    mode: .awakeLidClosed, title: "Lid closed",
                    subtitle: model.lidPermitted ? "Stays on when shut" : "Needs setup",
                    selected: model.selectedMode == .awakeLidClosed, enabled: model.lidPermitted
                ) { model.selectedMode = .awakeLidClosed }
            }

            if !model.lidPermitted {
                Text("Lid-closed mode needs a one-time setup. Run scripts/install.sh.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 6) {
                ForEach(Presets.durations, id: \.self) { duration in
                    DurationChip(
                        label: ShortDuration.label(duration), selected: model.selectedDuration == duration
                    ) { model.selectedDuration = duration }
                }
            }

            Button {
                model.start()
            } label: {
                Text("\(model.session == nil ? "Start" : "Start new") · \(DurationFormat.label(model.selectedDuration))")
            }
            .buttonStyle(PrimaryButtonStyle())
            .keyboardShortcut(.defaultAction)

            if let message = model.errorMessage {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct ModeCard: View {
    let mode: SessionMode
    let title: String
    let subtitle: String
    let selected: Bool
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: mode.symbol)
                        .font(.title3)
                        .foregroundStyle(selected ? Color.wakeful : .secondary)
                    Spacer()
                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.wakeful)
                    }
                }
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(selected ? Color.wakeful.opacity(0.14) : Color.primary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(selected ? Color.wakeful : Color.primary.opacity(0.08), lineWidth: selected ? 1.5 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.5)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct DurationChip: View {
    let label: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.callout.weight(.medium))
                .monospacedDigit()
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity)
                .background(Capsule().fill(selected ? Color.wakeful : Color.primary.opacity(0.06)))
                .foregroundStyle(selected ? Color.white : Color.primary)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Button styles

private struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.wakeful.opacity(configuration.isPressed ? 0.75 : 1))
            )
            .opacity(isEnabled ? 1 : 0.5)
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

private struct SecondaryButtonStyle: ButtonStyle {
    var foreground: Color = .primary
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .foregroundStyle(foreground)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.12 : 0.06))
            )
            .opacity(isEnabled ? 1 : 0.4)
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

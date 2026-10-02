import SwiftUI
import WakefulCore

struct SettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Section("General") {
                Picker("Default duration", selection: $model.settings.defaultDuration) {
                    ForEach(Presets.durations, id: \.self) { duration in
                        Text(DurationFormat.label(duration)).tag(duration)
                    }
                }
                Toggle("Keep the display awake", isOn: $model.settings.keepDisplayAwake)
                Toggle(
                    "Launch at login",
                    isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
            }

            Section {
                Picker("Stop at battery level", selection: $model.settings.batteryFloor) {
                    ForEach(Presets.batteryFloors, id: \.self) { floor in
                        Text("\(floor)%").tag(floor)
                    }
                }
                Toggle("Stop when Low Power Mode turns on", isOn: $model.settings.stopOnLowPowerMode)
                Toggle("Stop when the Mac runs hot", isOn: $model.settings.stopOnThermalPressure)
            } header: {
                Text("Lid-closed safety")
            } footer: {
                Text("These end a lid-closed session early. The battery level only applies while on battery.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Section("Lid-closed mode") {
                LabeledContent("Status") {
                    if model.lidPermitted {
                        Label("Ready", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Label("Needs setup", systemImage: "exclamationmark.circle.fill")
                            .foregroundStyle(.orange)
                    }
                }
                if !model.lidPermitted {
                    Text("Run scripts/install.sh from the Wakeful source folder. It asks for your admin password once.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            if let message = model.errorMessage {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
        .tint(Color.wakeful)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
    }
}

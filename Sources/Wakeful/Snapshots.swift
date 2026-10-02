#if DEBUG
    import AppKit
    import SwiftUI
    import WakefulCore

    /// Renders the popover and Settings window in their main states to PNGs, for checking the
    /// design without clicking through the app. Run a debug build with WAKEFUL_SNAPSHOT_DIR set.
    @MainActor
    enum Snapshots {
        private final class NoopPreventer: IdleSleepPreventing {
            func begin(keepDisplayAwake: Bool) throws {}
            func end() {}
        }

        private struct NoopLid: LidSleepControlling {
            func isSleepDisabled() throws -> Bool { false }
            func setSleepDisabled(_ disabled: Bool) throws {}
        }

        static func render(to dir: URL) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                save(PopoverView(model: model(mode: nil)), "popover-idle-\(name)", appearance, dir)
                save(PopoverView(model: model(mode: nil, permitted: false)), "popover-setup-\(name)", appearance, dir)
                save(PopoverView(model: model(mode: .awake)), "popover-awake-\(name)", appearance, dir)
                save(PopoverView(model: model(mode: .awakeLidClosed)), "popover-lid-\(name)", appearance, dir)
                save(SettingsView(model: model(mode: nil)), "settings-\(name)", appearance, dir)
            }
        }

        private static func model(mode: SessionMode?, permitted: Bool = true) -> AppModel {
            let store = LidSessionStore(
                url: FileManager.default.temporaryDirectory.appendingPathComponent("wakeful-snapshot.json"))
            // Started 17 minutes ago, so the ring shows partly elapsed.
            let controller = SessionController(
                preventer: NoopPreventer(), lidControl: NoopLid(), store: store, pid: 1
            ) { Date().addingTimeInterval(-17 * 60 - 43) }
            let model = AppModel(
                controller: controller, hasLidPermission: { permitted },
                settingsStore: SettingsStore(defaults: UserDefaults(suiteName: "wakeful-snapshots")!),
                notifier: Notifier())
            if let mode {
                model.selectedMode = mode
                model.start()
                model.refresh()
            }
            return model
        }

        private static func save(_ view: some View, _ name: String, _ appearance: NSAppearance.Name, _ dir: URL) {
            let scheme: ColorScheme = appearance == .darkAqua ? .dark : .light
            let host = NSHostingView(
                rootView: view.background(Color(nsColor: .windowBackgroundColor)).environment(\.colorScheme, scheme))
            host.appearance = NSAppearance(named: appearance)
            host.frame.size = host.fittingSize
            let window = NSWindow(
                contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: appearance)
            window.backgroundColor = appearance == .darkAqua ? NSColor(white: 0.16, alpha: 1) : NSColor(white: 0.96, alpha: 1)
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            host.display()

            guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
            host.cacheDisplay(in: host.bounds, to: rep)
            let url = dir.appendingPathComponent("\(name).png")
            try? rep.representation(using: .png, properties: [:])?.write(to: url)
        }
    }
#endif

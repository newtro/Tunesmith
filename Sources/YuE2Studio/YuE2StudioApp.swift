import SwiftUI

@main
struct YuE2StudioApp: App {
    @State private var model = StudioModel()

    var body: some Scene {
        WindowGroup("YuE2 Studio") {
            ContentView()
                .environment(model)
                .frame(minWidth: 900, minHeight: 620)
        }
        .defaultSize(width: 1040, height: 700)
        .commands {
            CommandMenu("Library") {
                Button("New Song") { model.newSong() }
                    .keyboardShortcut("n", modifiers: .command)
                Divider()
                Button("New Library…") { model.askNewLibrary = true }
                    .keyboardShortcut("l", modifiers: [.command, .shift])
                Button("New Category…") { model.askNewCategory = true }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                Button("New Playlist…") { model.askNewPlaylist = true }
                    .keyboardShortcut("p", modifiers: [.command, .shift])
                Divider()
                Button("Refresh Library") { model.refreshLibrary() }
                    .keyboardShortcut("r", modifiers: .command)
            }
        }

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}

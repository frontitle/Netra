import SwiftUI

@main
struct NetraApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var preferences = AppPreferences()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(preferences)
                .environment(\.theme, preferences.themeColors)
                .preferredColorScheme(preferences.preferredColorScheme)
                .frame(minWidth: 1180, minHeight: 760)
                .task { await preferences.checkForUpdates(userInitiated: false) }
        }
        .windowStyle(.automatic)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}

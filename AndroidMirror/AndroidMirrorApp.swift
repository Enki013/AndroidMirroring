import SwiftUI

@main
struct AndroidMirrorApp: App {
    @StateObject private var settings = AppSettings.shared
    @StateObject private var deviceList = DeviceListViewModel()
    @StateObject private var mirrorSession = MirrorSessionViewModel()
    @StateObject private var fileTransfer = FileTransferService()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(settings)
                .environmentObject(deviceList)
                .environmentObject(mirrorSession)
                .environmentObject(fileTransfer)
                .frame(minWidth: 320, minHeight: 320)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)

        Settings {
            SettingsView()
                .environmentObject(settings)
                .environmentObject(mirrorSession)
        }

        Window("About Android Mirror", id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)
    }
}

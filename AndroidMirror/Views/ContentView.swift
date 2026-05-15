import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var deviceList: DeviceListViewModel
    @EnvironmentObject private var mirrorSession: MirrorSessionViewModel
    @EnvironmentObject private var fileTransfer: FileTransferService

    @State private var showConnectionSheet = false
    @State private var showOnboarding = false

    var body: some View {
        mainLayout
        .onAppear {
            if !settings.hasCompletedOnboarding {
                showOnboarding = true
            }
            deviceList.startPolling()
        }
        .onDisappear {
            deviceList.stopPolling()
            mirrorSession.stopMirroring()
        }
        .sheet(isPresented: $showConnectionSheet) {
            ConnectionSheet()
                .environmentObject(deviceList)
        }
        .sheet(isPresented: $showOnboarding) {
            OnboardingView(isPresented: $showOnboarding)
        }
    }

    private var mainLayout: some View {
        NavigationSplitView {
            SidebarView(showConnectionSheet: $showConnectionSheet)
        } detail: {
            MirrorView()
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if mirrorSession.isMirroring {
                    Button {
                        mirrorSession.stopMirroring()
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                    }
                }

                Button {
                    showConnectionSheet = true
                } label: {
                    Label("Connect", systemImage: "antenna.radiowaves.left.and.right")
                }
            }
        }
        .overlay(alignment: .bottom) {
            TransferToastView()
                .padding()
        }
    }
}

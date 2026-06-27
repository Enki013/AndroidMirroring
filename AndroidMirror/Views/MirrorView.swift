import SwiftUI

struct MirrorView: View {
    @EnvironmentObject private var deviceList: DeviceListViewModel
    @EnvironmentObject private var mirrorSession: MirrorSessionViewModel
    @EnvironmentObject private var settings: AppSettings

    @State private var mirrorFrame: CGRect = .zero
    @State private var showControls = false
    @State private var showHoverChrome = false
    @State private var hideHoverChromeWorkItem: DispatchWorkItem?
    @State private var isRotating = false

    var body: some View {
        ZStack {
            // Clean dark background
            Color(red: 0.06, green: 0.06, blue: 0.07)
                .ignoresSafeArea()

            if let device = deviceList.selectedDevice, device.isReady {
                activeMirror(device: device)
            } else {
                emptyState
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if mirrorSession.isMirroring {
                    // Settings toggle
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            showControls.toggle()
                        }
                    } label: {
                        Label("Settings", systemImage: showControls ? "slider.horizontal.3" : "slider.horizontal.3")
                    }
                    .help("Show Controls")
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .startMirroring)) { _ in
            startMirror()
        }
    }

    // MARK: - Active Mirror (Phone Only)

    private func activeMirror(device: AndroidDevice) -> some View {
        GeometryReader { proxy in
            let frame = proxy.frame(in: .global)

            ZStack {
                // Phone frame — centered, fills available space
                phoneView(device: device)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Floating controls panel — slides in from right
                if showControls {
                    controlsPanel(device: device)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .onAppear {
                DispatchQueue.main.async { mirrorFrame = frame }
                updateWindowFrame(for: mirrorSession.metalRenderer.videoSize)
            }
            .onChange(of: frame) { _, newFrame in
                DispatchQueue.main.async {
                    mirrorFrame = newFrame
                    mirrorSession.updateMirrorFrame(newFrame)
                }
            }
            .onChange(of: mirrorSession.metalRenderer.videoSize) { oldSize, newSize in
                guard oldSize != .zero, newSize != .zero else { return }
                let oldIsLandscape = oldSize.width > oldSize.height
                let newIsLandscape = newSize.width > newSize.height
                if oldIsLandscape != newIsLandscape {
                    isRotating = true
                    updateWindowFrame(for: newSize)
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            isRotating = false
                        }
                    }
                }
            }
        }
    }

    private func phoneView(device: AndroidDevice) -> some View {
        let size = mirrorSession.metalRenderer.videoSize
        let ratio = size.width > 0 && size.height > 0 ? (size.width / size.height) : (9 / 19.5)
        
        return ZStack(alignment: .top) {
            DeviceChrome(aspectRatio: ratio, isChromeVisible: showHoverChrome) {
                hoverChromeTitlebar
                    .onHover { hovering in
                        hovering ? revealHoverChrome() : scheduleHideHoverChrome()
                    }
            } content: {
                ZStack {
                    if mirrorSession.isMirroring {
                        MetalVideoView(renderer: mirrorSession.metalRenderer)
                    } else {
                        placeholder(device: device)
                    }
                    
                    if isRotating {
                        ZStack {
                            Color.black
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 48, weight: .medium))
                                .foregroundStyle(.white)
                        }
                        .transition(.opacity)
                    }
                }
            }

            VStack(spacing: 0) {
                Color.clear
                    .frame(height: 76)
                    .contentShape(Rectangle())
                    .allowsHitTesting(!showHoverChrome)
                    .onHover { hovering in
                        hovering ? revealHoverChrome() : scheduleHideHoverChrome()
                    }
                Spacer(minLength: 0)
            }
        }
        .fileDropOverlay(device: device)
        .padding(.horizontal, 0)
        .padding(.vertical, 8)
    }

    private var hoverChromeTitlebar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 7) {
                trafficLight(color: .red.opacity(0.95))
                trafficLight(color: .yellow.opacity(0.95))
                trafficLight(color: .green.opacity(0.95))
            }
            .padding(.leading, 6)

            Spacer(minLength: 18)

            hoverChromeButton("Home Screen", icon: "square.grid.3x3.fill") {
                mirrorSession.metalRenderer.controlChannel.sendKeyPress(.home)
            }

            hoverChromeButton("App Switcher", icon: "rectangle.on.rectangle") {
                mirrorSession.metalRenderer.controlChannel.sendKeyPress(.appSwitch)
            }

            hoverChromeButton("Controls", icon: "slider.horizontal.3") {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    showControls.toggle()
                }
            }
        }
        .frame(height: 58)
        .padding(.horizontal, 13)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(.white.opacity(0.10))
                .frame(height: 1)
        }
    }

    private func trafficLight(color: Color) -> some View {
        Circle()
            .fill(color)
            .frame(width: 11, height: 11)
            .overlay(Circle().stroke(.black.opacity(0.16), lineWidth: 0.5))
    }

    private func hoverChromeButton(_ label: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: 32, height: 28)
                .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }

    private func revealHoverChrome() {
        hideHoverChromeWorkItem?.cancel()
        hideHoverChromeWorkItem = nil
        withAnimation(.spring(response: 0.24, dampingFraction: 0.86)) {
            showHoverChrome = true
        }
    }

    private func scheduleHideHoverChrome() {
        hideHoverChromeWorkItem?.cancel()
        let item = DispatchWorkItem {
            withAnimation(.easeOut(duration: 0.18)) {
                showHoverChrome = false
            }
        }
        hideHoverChromeWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9, execute: item)
    }

    private func updateWindowFrame(for size: CGSize) {
        DispatchQueue.main.async {
            if let window = NSApp.windows.first(where: { $0.isKeyWindow }) ?? NSApp.windows.first {
                let ratio = size.width > 0 && size.height > 0 ? (size.width / size.height) : (9 / 19.5)
                let isLandscape = ratio >= 1
                let targetWidth = isLandscape ? (420 * ratio) : 420
                let targetHeight = isLandscape ? (420 + 16) : (420 / ratio + 16)
                
                let contentRect = NSRect(x: 0, y: 0, width: targetWidth, height: targetHeight)
                let windowRect = window.frameRect(forContentRect: contentRect)
                
                var frame = window.frame
                let center = CGPoint(x: frame.midX, y: frame.midY)
                frame.size = windowRect.size
                frame.origin = CGPoint(x: center.x - windowRect.width / 2, y: center.y - windowRect.height / 2)
                
                window.contentAspectRatio = NSSize(width: targetWidth, height: targetHeight)
                window.setFrame(frame, display: true, animate: true)
            }
        }
    }

    // MARK: - Controls Panel

    private func controlsPanel(device: AndroidDevice) -> some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                VStack(alignment: .leading, spacing: 0) {
                    // Quality section
                    controlSection("Quality") {
                        Picker("Quality", selection: Binding(
                            get: { settings.mirrorPreset },
                            set: { newValue in
                                settings.mirrorPreset = newValue
                                mirrorSession.restartIfNeeded(device: device, frame: mirrorFrame)
                            }
                        )) {
                            ForEach(QualityPreset.allCases) { preset in
                                Text(preset.title).tag(preset)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    Divider().padding(.horizontal, 16)

                    // Video source section
                    controlSection("Source") {
                        Picker("Source", selection: Binding(
                            get: { settings.mirrorVideoSource },
                            set: { newValue in
                                settings.mirrorVideoSource = newValue
                                mirrorSession.restartIfNeeded(device: device, frame: mirrorFrame)
                            }
                        )) {
                            ForEach(VideoSource.allCases) { source in
                                Label(source.title, systemImage: source.icon).tag(source)
                            }
                        }
                        .pickerStyle(.segmented)

                        if settings.mirrorVideoSource == .camera {
                            Picker("Camera", selection: Binding(
                                get: { settings.mirrorCameraFacing },
                                set: { newValue in
                                    settings.mirrorCameraFacing = newValue
                                    mirrorSession.restartIfNeeded(device: device, frame: mirrorFrame)
                                }
                            )) {
                                ForEach(CameraFacing.allCases) { facing in
                                    Text(facing.title).tag(facing)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                    }

                    Divider().padding(.horizontal, 16)

                    // Toggles section
                    controlSection("Options") {
                        VStack(spacing: 8) {
                            controlToggle("Audio", icon: "speaker.wave.2",
                                isOn: Binding(
                                    get: { settings.mirrorAudioEnabled },
                                    set: {
                                        settings.mirrorAudioEnabled = $0
                                        mirrorSession.restartIfNeeded(device: device, frame: mirrorFrame)
                                    }
                                ))
                        }
                    }

                    if mirrorSession.isMirroring {
                        Divider().padding(.horizontal, 16)

                        // Actions section
                        controlSection("Actions") {
                            HStack(spacing: 10) {
                                actionButton("Screenshot", icon: "camera") {
                                    Task { await mirrorSession.takeScreenshot(device: device) }
                                }
                                actionButton("Record", icon: "record.circle") {
                                    mirrorSession.startRecording()
                                }
                                actionButton("Stop", icon: "stop.fill") {
                                    mirrorSession.stopMirroring()
                                }
                            }
                        }
                    }

                    // Status
                    if let message = mirrorSession.statusMessage {
                        Text(message)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 12)
                    }
                }
                .frame(width: 260)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: .black.opacity(0.4), radius: 20, y: 8)
            }
            .padding(16)
        }
    }

    // MARK: - Control Helpers

    private func controlSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
        .padding(16)
    }

    private func controlToggle(_ label: String, icon: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                Text(label)
                    .font(.callout)
            }
        }
        .toggleStyle(.switch)
        .controlSize(.small)
    }

    private func actionButton(_ label: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                Text(label)
                    .font(.caption2)
            }
            .foregroundStyle(.white.opacity(0.85))
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Placeholder & Empty State

    private func placeholder(device: AndroidDevice) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "smartphone")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(device.displayName)
                .font(.title3.weight(.medium))
            Button("Start mirroring") {
                startMirror()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "Connect a device",
            systemImage: "iphone.and.arrow.forward",
            description: Text("Plug in your Android phone with USB debugging enabled, or pair wirelessly from the sidebar.")
        )
    }

    private func startMirror() {
        guard let device = deviceList.selectedDevice, device.isReady else { return }
        guard mirrorFrame != .zero else { return }
        mirrorSession.startMirroring(device: device, frame: mirrorFrame)
    }
}

// MARK: - Device Chrome

struct DeviceChrome<Chrome: View, Content: View>: View {
    let aspectRatio: CGFloat
    var isChromeVisible = false
    @ViewBuilder var chrome: () -> Chrome
    @ViewBuilder var content: () -> Content

    private var chromeHeight: CGFloat {
        isChromeVisible ? 58 : 0
    }

    var body: some View {
        VStack(spacing: 0) {
            chrome()
                .frame(height: chromeHeight)
                .opacity(isChromeVisible ? 1 : 0)
                .offset(y: isChromeVisible ? 0 : -18)
                .clipped()

            content()
                .aspectRatio(aspectRatio, contentMode: .fit)
                .background(Color(white: 0.04))
        }
        .background(Color(white: 0.04))
        .clipShape(RoundedRectangle(cornerRadius: isChromeVisible ? 32 : 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: isChromeVisible ? 32 : 28, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            .white.opacity(isChromeVisible ? 0.34 : 0.25),
                            .white.opacity(isChromeVisible ? 0.11 : 0.05)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
        )
        .shadow(color: .black.opacity(isChromeVisible ? 0.58 : 0.5), radius: isChromeVisible ? 48 : 40, y: isChromeVisible ? 24 : 20)
        .animation(.spring(response: 0.24, dampingFraction: 0.86), value: isChromeVisible)
    }
}



// MARK: - Control Bar (kept for compatibility but unused in new layout)

struct MirrorControlBar: View {
    let device: AndroidDevice
    let mirrorFrame: CGRect

    @EnvironmentObject private var mirrorSession: MirrorSessionViewModel
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        EmptyView()
    }
}

extension Notification.Name {
    static let startMirroring = Notification.Name("AndroidMirror.startMirroring")
}

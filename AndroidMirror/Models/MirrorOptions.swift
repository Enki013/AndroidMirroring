import Foundation

enum QualityPreset: String, CaseIterable, Identifiable, Codable {
    case balanced
    case performance
    case quality

    var id: String { rawValue }

    var title: String {
        switch self {
        case .balanced: return "Balanced"
        case .performance: return "Performance"
        case .quality: return "Quality"
        }
    }

    var subtitle: String {
        switch self {
        case .balanced: return "1920px · 60 fps"
        case .performance: return "1024px · lower latency"
        case .quality: return "16 Mbps · High Quality"
        }
    }
}

/// Video source: device display or camera.
/// Camera requires Android 12+ (API 31).
enum VideoSource: String, CaseIterable, Identifiable, Codable {
    case display
    case camera

    var id: String { rawValue }

    var title: String {
        switch self {
        case .display: return "Display"
        case .camera: return "Camera"
        }
    }

    var icon: String {
        switch self {
        case .display: return "iphone"
        case .camera: return "camera.fill"
        }
    }
}

/// Camera facing direction for camera source.
enum CameraFacing: String, CaseIterable, Identifiable, Codable {
    case front
    case back
    case external

    var id: String { rawValue }

    var title: String {
        switch self {
        case .front: return "Front"
        case .back: return "Back"
        case .external: return "External"
        }
    }

    var icon: String {
        switch self {
        case .front: return "person.fill"
        case .back: return "camera.fill"
        case .external: return "web.camera.fill"
        }
    }
}

struct MirrorOptions: Codable, Equatable {
    var preset: QualityPreset = .balanced
    var audioEnabled: Bool = true
    var turnScreenOff: Bool = false
    var stayAwake: Bool = true
    var videoSource: VideoSource = .display
    var cameraFacing: CameraFacing = .back
    var cameraFps: Int = 30

    /// Whether touch/key control should be enabled (disabled for camera mode).
    var controlEnabled: Bool {
        videoSource == .display
    }

    func scrcpyArguments(serial: String) -> [String] {
        var args = ["-s", serial]

        switch preset {
        case .balanced:
            args += ["--max-size=1920", "--max-fps=60"]
        case .performance:
            args += ["--max-size=1024"]
        case .quality:
            args += ["-b16M", "----max-size=1920", "--max-fps=60"]
        }

        if videoSource == .camera {
            args.append("--video-source=camera")
            args.append("--camera-facing=\(cameraFacing.rawValue)")
            if cameraFps > 0 { args.append("--camera-fps=\(cameraFps)") }
        }

        if !audioEnabled { args.append("--no-audio") }
        if turnScreenOff { args.append("--turn-screen-off") }
        if stayAwake { args.append("--stay-awake") }

        return args
    }

    /// Server key=value arguments for embedded mode (direct scrcpy-server invocation).
    /// Always uses H.264 since only the H264Decoder is available.
    func serverArguments(scid: UInt32) -> [String] {
        // SCID must be hex — server uses Integer.parseInt(value, 0x10)
        let scidHex = String(format: "%08x", scid)

        let isCamera = videoSource == .camera

        var args = [
            "tunnel_forward=true",
            "control=\(isCamera ? "false" : "true")",
            "cleanup=false",
            "raw_stream=true",
            "video_codec=h264",
            "log_level=verbose",
            "scid=\(scidHex)"
        ]

        // Camera source (Android 12+ required)
        if isCamera {
            args.append("video_source=camera")
            args.append("camera_facing=\(cameraFacing.rawValue)")
            if cameraFps > 0 {
                args.append("camera_fps=\(cameraFps)")
            }
        }

        // Audio: raw PCM (s16le 48 kHz stereo) — no external decoder needed.
        // Camera mode defaults to microphone; display mode defaults to device output.
        if audioEnabled {
            let audioSource = isCamera ? "mic" : "output"
            args += ["audio=true", "audio_codec=raw", "audio_source=\(audioSource)"]
        } else {
            args.append("audio=false")
        }

        // Video size/fps constraints.
        // Front cameras often fail to encode at high resolutions (black frames),
        // so cap max_size to 1024. Back/external cameras use normal preset values.
        let cameraFrontLimit = isCamera && cameraFacing == .front
        switch preset {
        case .balanced:
            let size = cameraFrontLimit ? 1024 : 1920
            args += ["max_size=\(size)", "max_fps=60"]
        case .performance:
            args.append("max_size=1024")
        case .quality:
            let size = cameraFrontLimit ? 1024 : 1920
            args += ["max_size=\(size)", "max_fps=60", "video_bit_rate=16000000"]
        }

        if turnScreenOff { args.append("power_off_on_close=true") }
        if stayAwake { args.append("stay_awake=true") }

        return args
    }
}

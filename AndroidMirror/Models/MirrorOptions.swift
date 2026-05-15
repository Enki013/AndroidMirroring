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
        case .quality: return "H.265 · 16 Mbps"
        }
    }
}

struct MirrorOptions: Codable, Equatable {
    var preset: QualityPreset = .balanced
    var audioEnabled: Bool = true
    var turnScreenOff: Bool = false
    var stayAwake: Bool = true

    func scrcpyArguments(serial: String) -> [String] {
        var args = ["-s", serial]

        switch preset {
        case .balanced:
            args += ["--max-size=1920", "--max-fps=60"]
        case .performance:
            args += ["--max-size=1024"]
        case .quality:
            args += ["--video-codec=h265", "-b16M", "--max-size=1920", "--max-fps=60"]
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
        var args = [
            "tunnel_forward=true",
            "audio=false",
            "control=true",
            "cleanup=false",
            "raw_stream=true",
            "video_codec=h264",
            "log_level=verbose",
            "scid=\(scidHex)"
        ]

        switch preset {
        case .balanced:
            args += ["max_size=1920", "max_fps=60"]
        case .performance:
            args += ["max_size=1024"]
        case .quality:
            // Embedded mode forces H.264 (no H.265 decoder); use high bitrate instead
            args += ["max_size=1920", "max_fps=60", "video_bit_rate=16000000"]
        }

        if turnScreenOff { args.append("power_off_on_close=true") }
        if stayAwake { args.append("stay_awake=true") }

        return args
    }
}

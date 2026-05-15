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
}

import Foundation

struct AndroidDevice: Identifiable, Hashable, Codable {
    let id: String
    var serial: String { id }
    var model: String
    var product: String
    var transport: DeviceTransport
    var state: DeviceState

    var displayName: String {
        if !model.isEmpty, model != "unknown" { return model }
        if !product.isEmpty { return product }
        return serial
    }

    var isReady: Bool { state == .device }
}

enum DeviceTransport: String, Codable {
    case usb
    case wifi
    case unknown
}

enum DeviceState: String, Codable {
    case device
    case offline
    case unauthorized
    case authorizing
    case unknown

    var label: String {
        switch self {
        case .device: return "Ready"
        case .offline: return "Offline"
        case .unauthorized: return "Unauthorized"
        case .authorizing: return "Authorizing…"
        case .unknown: return "Unknown"
        }
    }
}

import ActivityKit
import Foundation

struct AirWatchAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var headline: String
        var detail: String
        var fault: Bool
    }
    var label: String
}

struct EventBatch: Decodable {
    let events: [AirWatchEvent]
    let latestEventID: Int
    let instanceID: String?

    enum CodingKeys: String, CodingKey {
        case events
        case latestEventID = "latest_event_id"
        case instanceID = "instance_id"
    }
}

struct AirWatchEvent: Decodable, Identifiable {
    let eventID: Int
    let eventType: String
    let timestamp: Double
    let hex: String?
    let flight: String?
    let registration: String?
    let agency: String?
    let airframeClass: String?
    let aircraftType: String?
    let level: String?
    let distanceMI: Double?
    let direction: String?
    let altitudeFT: Double?
    let clockPosition: Int?
    let movement: String?
    let behavior: [String]?
    let component: String?
    let detail: String?

    var id: Int { eventID }
    var identity: String {
        [registration, flight, hex?.uppercased()]
            .compactMap { $0?.isEmpty == false ? $0 : nil }.first ?? "aircraft"
    }
    var aircraftLabel: String {
        if let agency, !agency.isEmpty { return agency }
        if airframeClass == "helicopter" { return "Helicopter" }
        return "Aircraft"
    }
    var headline: String {
        switch eventType {
        case "factor_entered": return "FACTOR · \(aircraftLabel) \(identity)"
        case "factor_cleared": return "CLEAR · \(identity)"
        case "health_fault": return "FAULT · \(component?.uppercased() ?? "SYSTEM")"
        case "health_recovered": return "RESTORED · \(component?.uppercased() ?? "SYSTEM")"
        default: return eventType
        }
    }
    var detailLine: String {
        if eventType.hasPrefix("health_") { return detail ?? "" }
        var parts = [String]()
        if let clockPosition { parts.append("\(clockPosition) o’clock") }
        else if let direction, !direction.isEmpty { parts.append(direction) }
        if let distanceMI { parts.append(String(format: "%.1f mi", distanceMI)) }
        if let altitudeFT { parts.append("\(Int(altitudeFT.rounded())) ft") }
        if let movement, !movement.isEmpty { parts.append(movement) }
        return parts.joined(separator: " · ")
    }
    var spokenText: String {
        switch eventType {
        case "factor_cleared": return "\(aircraftLabel) \(identity) is no longer a factor."
        case "factor_entered":
            var result = "\(aircraftLabel) \(identity)"
            if let clockPosition { result += ", your \(clockPosition) o’clock" }
            else if let direction, !direction.isEmpty { result += ", \(direction)" }
            if let distanceMI { result += String(format: ", %.1f miles", distanceMI) }
            if let altitudeFT { result += ", \(Int((altitudeFT / 100).rounded() * 100)) feet" }
            if movement == "closing" { result += ", closing" }
            return result + "."
        case "health_fault":
            switch component {
            case "gps": return "AirWatch warning. GPS lost. Position is unreliable."
            case "1090": return "AirWatch warning. 1090 receiver offline."
            case "978": return "AirWatch warning. 978 receiver offline."
            default: return "AirWatch warning. \(component ?? "System") fault."
            }
        case "health_recovered": return "AirWatch \(component ?? "system") restored."
        default: return ""
        }
    }
    enum CodingKeys: String, CodingKey {
        case eventID = "event_id", eventType = "event_type", timestamp, hex, flight
        case registration, agency, component, detail, direction, movement, behavior, level
        case airframeClass = "airframe_class", aircraftType = "aircraft_type"
        case distanceMI = "distance_mi", altitudeFT = "altitude_ft"
        case clockPosition = "clock_position"
    }
}

struct AirWatchStatus: Decodable {
    let updated: Double
    let status: String
    let aircraft1090Count: Int?
    let aircraft978Count: Int?
    let health: [String: HealthComponent]?

    enum CodingKeys: String, CodingKey {
        case updated, status, health
        case aircraft1090Count = "aircraft_1090_count"
        case aircraft978Count = "aircraft_978_count"
    }
}

struct HealthComponent: Decodable {
    let healthy: Bool
    let faulted: Bool
    let detail: String
}

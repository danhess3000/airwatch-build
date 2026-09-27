import Foundation

enum SpokenAlertAudio {
    static let group = "group.com.danhess.airwatch"
    static let maximumBytes = 1_200_000

    // Match the private Pi address already used by the app. Never follow arbitrary
    // URLs or redirects supplied in a push notification.
    static func allowedURL(_ value: String) -> URL? {
        guard let url = URL(string: value),
              url.scheme == "http", url.host == "172.20.10.2", url.port == 8100,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              url.path.range(of: #"^/audio/[0-9a-f]{32}\.wav$"#,
                             options: .regularExpression) != nil else { return nil }
        return url
    }

    // Restrict downloads to short, uncompressed 16-bit mono WAVs. Parsing here
    // avoids loading AVFoundation into the memory-constrained service extension.
    static func validWAV(_ data: Data) -> Bool {
        guard data.count >= 44, data.count <= maximumBytes else { return false }
        let bytes = [UInt8](data)
        func tag(_ offset: Int) -> String {
            String(bytes: bytes[offset..<(offset + 4)], encoding: .ascii) ?? ""
        }
        func u16(_ offset: Int) -> Int {
            Int(bytes[offset]) | Int(bytes[offset + 1]) << 8
        }
        func u32(_ offset: Int) -> Int {
            u16(offset) | u16(offset + 2) << 16
        }
        guard tag(0) == "RIFF", tag(8) == "WAVE",
              u32(4) == bytes.count - 8 else { return false }
        var offset = 12
        var rate: Int?
        var soundBytes: Int?
        while offset + 8 <= bytes.count {
            let size = u32(offset + 4)
            let start = offset + 8
            guard size <= bytes.count - start else { return false }
            switch tag(offset) {
            case "fmt ":
                guard rate == nil, size >= 16, u16(start) == 1,
                      u16(start + 2) == 1, u16(start + 14) == 16,
                      u16(start + 12) == 2 else { return false }
                let sampleRate = u32(start + 4)
                guard (8000...48000).contains(sampleRate),
                      u32(start + 8) == sampleRate * 2 else { return false }
                rate = sampleRate
            case "data":
                guard soundBytes == nil, size > 0, size % 2 == 0 else { return false }
                soundBytes = size
            default: break
            }
            offset = start + size + size % 2
        }
        guard offset == bytes.count, let rate, let soundBytes else { return false }
        return Double(soundBytes) / Double(rate * 2) <= 25
    }
}

import Foundation

func check(_ condition: Bool, _ message: String) {
    if !condition { fatalError(message) }
}
func wav(seconds: Int = 1, channels: Int = 1, format: Int = 1) -> Data {
    var bytes = [UInt8]()
    func text(_ s: String) { bytes += Array(s.utf8) }
    func number(_ value: Int, _ count: Int) {
        for shift in 0..<count { bytes.append(UInt8((value >> (shift * 8)) & 255)) }
    }
    let count = 22050 * seconds * 2 * channels
    text("RIFF"); number(36 + count, 4); text("WAVE")
    text("fmt "); number(16, 4); number(format, 2); number(channels, 2)
    number(22050, 4); number(22050 * 2 * channels, 4)
    number(2 * channels, 2); number(16, 2)
    text("data"); number(count, 4); bytes += Array(repeating: 0, count: count)
    return Data(bytes)
}
let valid = "http://172.20.10.2:8100/audio/" + String(repeating: "a", count: 32) + ".wav"
check(SpokenAlertAudio.allowedURL(valid) != nil, "expected Pi URL")
for url in [valid + "?token=x", valid + "#fragment", valid.replacingOccurrences(of: "172.20.10.2", with: "example.com"),
            valid.replacingOccurrences(of: "/audio/", with: "/other/"),
            valid.replacingOccurrences(of: ":8100", with: ":8099"),
            "file:///etc/passwd", "http://172.20.10.2:8100/audio/../../apns.env"] {
    check(SpokenAlertAudio.allowedURL(url) == nil, "untrusted URL accepted")
}
check(SpokenAlertAudio.validWAV(wav()), "valid PCM rejected")
check(!SpokenAlertAudio.validWAV(wav(seconds: 26)), "overlong sound accepted")
check(!SpokenAlertAudio.validWAV(wav(channels: 2)), "stereo accepted")
check(!SpokenAlertAudio.validWAV(wav(format: 3)), "non-PCM accepted")
check(!SpokenAlertAudio.validWAV(Data(wav().dropLast())), "truncated sound accepted")
check(!SpokenAlertAudio.validWAV(Data("not audio".utf8)), "garbage accepted")
var malformed = wav()
malformed[16] = 255; malformed[17] = 255; malformed[18] = 255; malformed[19] = 127
check(!SpokenAlertAudio.validWAV(malformed), "oversized chunk accepted")
print("Spoken alert URL and WAV validation tests passed")

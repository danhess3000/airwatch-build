import ActivityKit
import AVFAudio
import SwiftUI
import UserNotifications
import UIKit

private extension Notification.Name {
    static let airWatchDeviceToken = Notification.Name("AirWatchDeviceToken")
}

final class AirWatchPushDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in
            DispatchQueue.main.async { application.registerForRemoteNotifications() }
        }
        return true
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        NotificationCenter.default.post(name: .airWatchDeviceToken, object: token)
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("APNS REGISTRATION ERROR: \(error)")
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Direct polling already voices foreground events; avoid a duplicate chime.
        completionHandler([])
    }
}

@main
struct AirWatchApp: App {
    @UIApplicationDelegateAdaptor(AirWatchPushDelegate.self) private var pushDelegate
    @StateObject private var model = AirWatchModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(model.connectionState)
                            .font(.headline)
                        if let status = model.status {
                            Text(status.status).font(.title3).bold()
                            Text("1090: \(status.aircraft1090Count ?? 0)  ·  978: \(status.aircraft978Count ?? 0)")
                            ForEach(["gps", "1090", "978"], id: \.self) { name in
                                if let item = status.health?[name] {
                                    HStack {
                                        Image(systemName: item.faulted ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                                            .foregroundStyle(item.faulted ? .red : .green)
                                        Text("\(name.uppercased()): \(item.detail)")
                                    }
                                }
                            }
                            RadarView(status: status)
                        }
                        Button("Test spoken factor and clearance") { model.testAlert() }
                            .buttonStyle(.borderedProminent)
                        Button("Dismiss current alert") { model.dismissCurrentAlert() }
                            .buttonStyle(.bordered)
                            .disabled(!model.hasLiveActivity)
                        Text(model.liveActivityState)
                            .font(.caption).foregroundStyle(.secondary)
                        SecureField("Pi pairing code", text: $model.pairingCode)
                            .textContentType(.password)
                        Button("Pair push alerts with Pi") { Task { await model.pair() } }
                            .buttonStyle(.bordered)
                        Text(model.pushState).font(.caption)
                        Text("When locked, spoken push alerts use notification sounds. Enable Sounds for AirWatch and turn Silent Mode off.")
                            .font(.caption).foregroundStyle(.secondary)
                        Text("Recent transitions").font(.headline)
                        ForEach(model.events.reversed()) { event in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(event.headline).bold()
                                Text(event.detailLine)
                                Text(Date(timeIntervalSince1970: event.timestamp), style: .time)
                                    .font(.caption).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                                .padding().background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                        }
                    }.padding()
                }
                .navigationTitle("AirWatch")
            }
            .onAppear { model.start() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { model.start() }
                else { model.stop() }
            }
        }
    }
}

private struct RadarView: View {
    let status: AirWatchStatus

    private var targets: [AirWatchTarget] {
        (status.interesting ?? []).filter { target in
            guard let distance = target.distanceMI, let bearing = target.bearing else { return false }
            return distance >= 0 && distance.isFinite && bearing.isFinite
        }.sorted { ($0.distanceMI ?? 0) < ($1.distanceMI ?? 0) }
    }

    private var course: Double? {
        guard let speed = status.receiver?.speedMPS, speed >= 2.5,
              let track = status.receiver?.track else { return nil }
        return track
    }

    private var range: Double {
        max(2, ceil((targets.prefix(12).compactMap(\.distanceMI).max() ?? 0) / 2) * 2)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Nearby aircraft").font(.headline)
                Spacer()
                Text(course == nil ? "NORTH UP" : "AHEAD UP")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            GeometryReader { geometry in
                let radius = min(geometry.size.width, geometry.size.height) * 0.43
                ZStack {
                    ForEach(1...3, id: \.self) { ring in
                        Circle().stroke(.secondary.opacity(0.35), lineWidth: 1)
                            .frame(width: radius * 2 * CGFloat(ring) / 3,
                                   height: radius * 2 * CGFloat(ring) / 3)
                    }
                    Path { path in
                        path.move(to: CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2 - radius))
                        path.addLine(to: CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2 + radius))
                        path.move(to: CGPoint(x: geometry.size.width / 2 - radius, y: geometry.size.height / 2))
                        path.addLine(to: CGPoint(x: geometry.size.width / 2 + radius, y: geometry.size.height / 2))
                    }.stroke(.secondary.opacity(0.25), lineWidth: 1)
                    Image(systemName: "location.north.fill")
                        .foregroundStyle(.blue)
                    ForEach(Array(targets.prefix(12))) { target in
                        if let distance = target.distanceMI, let bearing = target.bearing {
                            let angle = (bearing - (course ?? 0)) * .pi / 180
                            let offset = radius * CGFloat(min(distance / range, 1))
                            Circle()
                                .fill(target.alertable == true ? .red : .cyan)
                                .frame(width: 12, height: 12)
                                .overlay(Circle().stroke(.white, lineWidth: 1))
                                .position(x: geometry.size.width / 2 + CGFloat(sin(angle)) * offset,
                                          y: geometry.size.height / 2 - CGFloat(cos(angle)) * offset)
                                .accessibilityLabel(Text("\(target.label), \(distance.formatted(.number.precision(.fractionLength(1)))) miles"))
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(height: 260)
            HStack {
                Text("Center: your GPS position")
                Spacer()
                Text("Outer ring: \(range.formatted()) mi")
            }.font(.caption2).foregroundStyle(.secondary)
            Text("Red: alertable  ·  Blue: other classified aircraft")
                .font(.caption2).foregroundStyle(.secondary)
            if targets.isEmpty {
                Text("No nearby classified aircraft with a current position")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(Array(targets.prefix(3))) { target in
                    HStack {
                        Circle().fill(target.alertable == true ? .red : .cyan)
                            .frame(width: 8, height: 8)
                        Text(target.label).lineLimit(1)
                        Spacer()
                        if let distance = target.distanceMI {
                            Text("\(distance.formatted(.number.precision(.fractionLength(1)))) mi")
                        }
                    }.font(.caption)
                }
            }
            Text("Position updated \(Date(timeIntervalSince1970: status.updated), style: .relative)")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

@MainActor
final class AirWatchModel: ObservableObject {
    @Published var connectionState = "Connecting to airwatch-m1…"
    @Published var status: AirWatchStatus?
    @Published var events: [AirWatchEvent] = []
    @Published var pairingCode = UserDefaults.standard.string(forKey: "AirWatchPairingCode") ?? ""
    @Published var pushState = "Awaiting Apple push registration"
    @Published var hasLiveActivity = false
    @Published var liveActivityState = "No active Live Activity"

    private let base = URL(string: "http://172.20.10.2:8099")!
    private var monitorTask: Task<Void, Never>?
    private var cursor: Int?
    private var instanceID: String?
    private let voice = VoiceAlerts()
    private var liveActivity: Activity<AirWatchAttributes>?
    private var lastLiveState: AirWatchAttributes.ContentState?
    private var activityRevision = 0
    private var deviceToken: String?
    private var activityToken: String?
    private var tokenObserver: NSObjectProtocol?

    init() {
        liveActivity = Activity<AirWatchAttributes>.activities.first
        hasLiveActivity = liveActivity != nil
        if hasLiveActivity { liveActivityState = "Live Activity active" }
        tokenObserver = NotificationCenter.default.addObserver(
            forName: .airWatchDeviceToken, object: nil, queue: .main
        ) { [weak self] note in
            Task { @MainActor in
                self?.deviceToken = note.object as? String
                await self?.sendTokens()
            }
        }
        if let liveActivity { observePushToken(liveActivity) }
    }

    func start() {
        guard monitorTask == nil else { return }
        monitorTask = Task {
            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    func stop() {
        monitorTask?.cancel()
        monitorTask = nil
        connectionState = "Paused in background · push delivery required"
    }

    private func get<T: Decodable>(_ path: String, as type: T.Type) async throws -> T {
        var request = URLRequest(url: URL(string: path, relativeTo: base)!)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 3
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(type, from: data)
    }

    private func refresh() async {
        do {
            let newStatus = try await get("/api/status", as: AirWatchStatus.self)
            status = newStatus
            connectionState = "Pi connected · \(Date(timeIntervalSince1970: newStatus.updated).formatted(date: .omitted, time: .standard))"
            let batch = try await get("/api/events?since=\(cursor ?? 0)", as: EventBatch.self)
            if cursor == nil || batch.latestEventID < cursor! ||
                (instanceID != nil && batch.instanceID != nil && instanceID != batch.instanceID) {
                // On first launch or Pi restart, show the history but don't speak old alerts.
                events = Array(batch.events.suffix(20))
                cursor = batch.latestEventID
                instanceID = batch.instanceID
            } else {
                for event in batch.events where event.eventID > cursor! {
                    print("LATENCY PHONE_EVENT id=\(event.eventID) type=\(event.eventType) pi_ts=\(event.timestamp) phone_ts=\(Date().timeIntervalSince1970)")
                    events.append(event)
                    if !event.spokenText.isEmpty { voice.speak(event.spokenText) }
                    updateLiveActivity(event)
                }
                if events.count > 40 { events.removeFirst(events.count - 40) }
                cursor = batch.latestEventID
            }
            if newStatus.health?["gps"]?.faulted == true {
                updateLiveActivity(headline: "GPS LOST", detail: "Position alerts suspended", fault: true)
            }
        } catch {
            connectionState = "Pi connection unavailable · \(error.localizedDescription)"
        }
    }

    func testAlert() {
        voice.speak("Police helicopter N nine one one Z R, your 2 o’clock, 1.2 miles, 900 feet, closing.")
        updateLiveActivity(headline: "FACTOR · POLICE HELICOPTER",
                           detail: "2 o’clock · 1.2 mi · 900 ft · closing", fault: false)
    }

    func dismissCurrentAlert() {
        guard hasLiveActivity else { return }
        let activities = Activity<AirWatchAttributes>.activities
        activityRevision += 1
        lastLiveState = nil
        liveActivity = nil
        activityToken = nil
        hasLiveActivity = false
        liveActivityState = "Dismissed. A new Live Activity starts with the next event while AirWatch is open."
        Task {
            for activity in activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    private func updateLiveActivity(_ event: AirWatchEvent) {
        updateLiveActivity(headline: event.headline, detail: event.detailLine,
                           fault: event.eventType == "health_fault")
    }

    private func updateLiveActivity(headline: String, detail: String, fault: Bool) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let state = AirWatchAttributes.ContentState(
            headline: headline, detail: detail, fault: fault
        )
        guard state != lastLiveState else { return }
        lastLiveState = state
        let revision = activityRevision
        let content = ActivityContent(
            state: state,
            staleDate: Date().addingTimeInterval(120)
        )
        Task {
            guard revision == activityRevision else { return }
            if let liveActivity {
                await liveActivity.update(content)
            } else {
                liveActivity = try? Activity.request(
                    attributes: AirWatchAttributes(label: "AirWatch"), content: content,
                    pushType: .token
                )
                if let activity = liveActivity {
                    hasLiveActivity = true
                    liveActivityState = "Live Activity active"
                    observePushToken(activity)
                }
            }
        }
    }

    private func observePushToken(_ activity: Activity<AirWatchAttributes>) {
        Task {
            if let token = activity.pushToken {
                guard liveActivity?.id == activity.id else { return }
                activityToken = token.map { String(format: "%02x", $0) }.joined()
                await sendTokens()
            }
            for await token in activity.pushTokenUpdates {
                guard liveActivity?.id == activity.id else { return }
                activityToken = token.map { String(format: "%02x", $0) }.joined()
                await sendTokens()
            }
        }
    }

    func pair() async {
        UserDefaults.standard.set(pairingCode, forKey: "AirWatchPairingCode")
        await sendTokens()
    }

    private func sendTokens() async {
        guard !pairingCode.isEmpty else {
            pushState = "Enter the Pi pairing code after push is configured"
            return
        }
        var payload = [String: String]()
        if let deviceToken { payload["device_token"] = deviceToken }
        if let activityToken { payload["activity_token"] = activityToken }
        guard !payload.isEmpty else {
            pushState = "Waiting for APNs device or Live Activity token"
            return
        }
        do {
            var request = URLRequest(url: URL(string: "/api/register-push", relativeTo: base)!)
            request.httpMethod = "POST"
            request.timeoutInterval = 5
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer " + pairingCode, forHTTPHeaderField: "Authorization")
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            let (_, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            pushState = "Push token paired with Pi"
        } catch {
            pushState = "Push pairing failed: \(error.localizedDescription)"
        }
    }
}

@MainActor
final class VoiceAlerts: NSObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String) {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? session.setActive(true)
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = 0.52
        synthesizer.speak(utterance)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       didStart utterance: AVSpeechUtterance) {
        print("LATENCY SPEECH_START phone_ts=\(Date().timeIntervalSince1970) text=\(utterance.speechString)")
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }
}

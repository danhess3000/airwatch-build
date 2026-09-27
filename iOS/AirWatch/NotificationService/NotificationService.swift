import Foundation
import UserNotifications
import os

final class NotificationService: UNNotificationServiceExtension, URLSessionDownloadDelegate {
    private let lock = NSLock()
    private var handler: ((UNNotificationContent) -> Void)?
    private var content: UNMutableNotificationContent?
    private var session: URLSession?
    private var deadline: DispatchWorkItem?
    private let logger = Logger(subsystem: "com.danhess.airwatch.speech", category: "notification")

    override func didReceive(_ request: UNNotificationRequest,
                             withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        guard let copy = request.content.mutableCopy() as? UNMutableNotificationContent else {
            contentHandler(request.content)
            return
        }
        lock.lock()
        content = copy
        handler = contentHandler
        lock.unlock()

        guard let text = copy.userInfo["airwatch_audio_url"] as? String,
              let url = SpokenAlertAudio.allowedURL(text) else {
            finish(reason: "no valid speech URL")
            return
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 12
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        let downloadSession = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
        session = downloadSession
        let timeout = DispatchWorkItem { [weak self] in
            self?.finish(reason: "speech download timed out")
        }
        deadline = timeout
        DispatchQueue.global().asyncAfter(deadline: .now() + 15, execute: timeout)
        downloadSession.downloadTask(with: url).resume()
    }

    override func serviceExtensionTimeWillExpire() {
        finish(reason: "extension time limit")
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        if totalBytesWritten > SpokenAlertAudio.maximumBytes ||
            totalBytesExpectedToWrite > SpokenAlertAudio.maximumBytes {
            downloadTask.cancel()
            finish(reason: "speech file too large")
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        guard let response = downloadTask.response as? HTTPURLResponse,
              response.statusCode == 200 else {
            finish(reason: "speech HTTP failure")
            return
        }
        do {
            let size = try location.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size > 0, size <= SpokenAlertAudio.maximumBytes else {
                finish(reason: "invalid speech size")
                return
            }
            let data = try Data(contentsOf: location)
            guard SpokenAlertAudio.validWAV(data),
                  let group = FileManager.default.containerURL(
                    forSecurityApplicationGroupIdentifier: SpokenAlertAudio.group) else {
                finish(reason: "invalid WAV or missing App Group")
                return
            }
            let directory = group.appendingPathComponent("Library/Sounds", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
            prune(directory)
            let name = "airwatch-" + UUID().uuidString + ".wav"
            let destination = directory.appendingPathComponent(name)
            try data.write(to: destination, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            finish(sound: UNNotificationSound(named: UNNotificationSoundName(rawValue: name)),
                   reason: "spoken notification ready")
        } catch {
            // Never log URLs, token values, or error text that might contain them.
            finish(reason: "speech file unavailable")
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        if error != nil { finish(reason: "speech network failure") }
    }

    private func finish(sound: UNNotificationSound? = nil, reason: String) {
        lock.lock()
        guard let callback = handler, let result = content else {
            lock.unlock()
            return
        }
        handler = nil
        if let sound { result.sound = sound }
        lock.unlock()
        deadline?.cancel()
        session?.invalidateAndCancel()
        logger.notice("\(reason, privacy: .public)")
        callback(result)
    }

    private func prune(_ directory: URL) {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        for file in files where file.lastPathComponent.hasPrefix("airwatch-") && file.pathExtension == "wav" {
            if let modified = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
               modified < Date().addingTimeInterval(-86400) {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }
}

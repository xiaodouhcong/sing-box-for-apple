#if os(iOS)

    import Foundation
    import Library
    import Network
    import UIKit

    public extension Notification.Name {
        static let crashReportReceived = Notification.Name("crashReportReceived")
    }

    public class CrashReportServer {
        private var listener: NWListener

        @available(iOS 16.0, *)
        public init() throws {
            listener = try NWListener(using: .applicationService)
            listener.service = NWListener.Service(applicationService: "sing-box:crash-report")
            listener.newConnectionHandler = { connection in
                connection.stateUpdateHandler = { state in
                    if state == .ready {
                        Task.detached {
                            try await Task.sleep(nanoseconds: NSEC_PER_MSEC * 100)
                            await CrashReportConnection(connection).process()
                        }
                    }
                }
                connection.start(queue: .global())
            }
        }

        public func start() {
            listener.start(queue: .global())
        }

        public func cancel() {
            listener.cancel()
        }

        class CrashReportConnection {
            private let connection: NWSocket
            private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid

            init(_ connection: NWConnection) {
                self.connection = NWSocket(connection)
            }

            func process() async {
                beginBackgroundTask()
                defer { endBackgroundTask() }

                var receivedCount = 0
                do {
                    while true {
                        let message = try await connection.read()
                        guard let type = CrashReportTransferMessage.decodeType(message) else {
                            continue
                        }
                        switch type {
                        case .report:
                            let payload = try CrashReportTransferMessage.decodeReport(message)
                            try importReport(payload)
                            receivedCount += 1
                        case .complete:
                            NSLog("crash report server: received \(receivedCount) report(s)")
                            if receivedCount > 0 {
                                await MainActor.run {
                                    NotificationCenter.default.post(name: .crashReportReceived, object: nil)
                                }
                            }
                            return
                        case .error:
                            let errorMsg = CrashReportTransferMessage.decodeError(message)
                            NSLog("crash report server: client error: \(errorMsg)")
                            return
                        }
                    }
                } catch {
                    NSLog("crash report server: \(error.localizedDescription)")
                    await writeError(error.localizedDescription)
                }
            }

            private func importReport(_ payload: CrashReportTransferPayload) throws {
                var metadata = payload.metadata
                metadata.deviceOrigin = "tvOS"
                let contents = CrashReportArtifactContents(
                    goLog: payload.goLog,
                    nativeLog: payload.nativeLog,
                    configContent: payload.configContent
                )
                let date = Date(timeIntervalSince1970: payload.crashTimestamp)
                _ = try CrashReportArchive.writeArchivedReport(
                    contents: contents,
                    date: date,
                    metadata: metadata
                )
            }

            private func writeError(_ message: String) async {
                try? await connection.write(CrashReportTransferMessage.encodeError(message))
            }

            private func beginBackgroundTask() {
                backgroundTaskID = UIApplication.shared.beginBackgroundTask { [weak self] in
                    NSLog("crash report server: background task expiring")
                    self?.connection.cancel()
                    self?.endBackgroundTask()
                }
            }

            private func endBackgroundTask() {
                guard backgroundTaskID != .invalid else { return }
                UIApplication.shared.endBackgroundTask(backgroundTaskID)
                backgroundTaskID = .invalid
            }
        }
    }

#endif

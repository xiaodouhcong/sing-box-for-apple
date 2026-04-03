#if os(tvOS)

    import DeviceDiscoveryUI
    import Library
    import Network
    import SwiftUI

    @MainActor
    public struct ExportCrashReportView: View {
        @Environment(\.dismiss) private var dismiss
        @StateObject private var viewModel = ExportCrashReportViewModel()

        let report: CrashReport

        public init(report: CrashReport) {
            self.report = report
        }

        public var body: some View {
            VStack(alignment: .center) {
                if !viewModel.selected {
                    Form {
                        Section {
                            EmptyView()
                        } footer: {
                            Text("To export this crash report to your iPhone or iPad, make sure sing-box is the **same version** on both devices and **VPN is disabled**.")
                        }

                        DevicePicker(
                            .applicationService(name: "sing-box:crash-report")
                        ) { endpoint in
                            viewModel.selected = true
                            Task {
                                await viewModel.handleEndpoint(endpoint, report: report)
                            }
                        } label: {
                            Text("Select Device")
                        } fallback: {
                            EmptyView()
                        } parameters: {
                            .applicationService
                        }
                    }
                } else if viewModel.exportComplete {
                    VStack(spacing: 16) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 64))
                            .foregroundStyle(.green)
                        Text("Export Complete")
                            .font(.headline)
                    }
                } else {
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("Sending...")
                    }
                }
            }
            .focusSection()
            .alert($viewModel.alert)
            .navigationTitle("Export Crash Report")
            .onChange(of: viewModel.exportComplete) { newValue in
                if newValue {
                    Task {
                        try? await Task.sleep(nanoseconds: NSEC_PER_SEC * 2)
                        dismiss()
                    }
                }
            }
        }
    }

    @MainActor
    private final class ExportCrashReportViewModel: BaseViewModel {
        @Published var selected = false
        @Published var exportComplete = false

        private var connection: NWConnection?
        private var socket: NWSocket?

        func reset() {
            if let connection {
                connection.stateUpdateHandler = nil
                connection.cancel()
                self.connection = nil
            }
            if let socket {
                socket.cancel()
                self.socket = nil
            }
            selected = false
        }

        func handleEndpoint(_ endpoint: NWEndpoint, report: CrashReport) async {
            let connection = NWConnection(to: endpoint, using: NWParameters.applicationService)
            self.connection = connection
            let socket = NWSocket(connection)
            self.socket = socket

            connection.stateUpdateHandler = { state in
                switch state {
                case let .failed(error):
                    DispatchQueue.main.async { [self] in
                        reset()
                        alert = AlertState(action: "connect to device", error: error)
                    }
                default: break
                }
            }
            connection.start(queue: .global())

            do {
                try await sendReport(report, via: socket)
            } catch {
                alert = AlertState(action: "export crash report", error: error)
                reset()
            }
        }

        private nonisolated func sendReport(_ report: CrashReport, via socket: NWSocket) async throws {
            let metadata = CrashReportArchive.readMetadata(for: report.fileURL)
                ?? CrashReportMetadata()
            let contents = CrashReportArchive.readContents(for: report.fileURL)

            guard !contents.isEmpty else {
                throw NSError(domain: "ExportCrashReport", code: 1, userInfo: [NSLocalizedDescriptionKey: "Crash report is empty"])
            }

            let payload = CrashReportTransferPayload(
                metadata: metadata,
                goLog: contents.goLog,
                nativeLog: contents.nativeLog,
                configContent: contents.configContent,
                crashTimestamp: report.date.timeIntervalSince1970
            )
            try await socket.write(CrashReportTransferMessage.encodeReport(payload))
            try await socket.write(CrashReportTransferMessage.encodeComplete())

            await MainActor.run {
                self.exportComplete = true
            }
        }
    }

#endif

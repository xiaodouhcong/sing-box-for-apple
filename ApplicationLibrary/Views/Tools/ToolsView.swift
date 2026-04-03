import Library
import SwiftUI

@MainActor
public struct ToolsView: View {
    @EnvironmentObject private var environments: ExtensionEnvironments
    @StateObject private var viewModel = SettingViewModel()
    #if os(iOS)
        @State private var showCrashReportList = false
    #endif

    public init() {}

    public var body: some View {
        FormView {
            Section("Debug") {
                #if os(iOS)
                    NavigationLink(isActive: $showCrashReportList) {
                        CrashReportListView()
                    } label: {
                        Label("Crash Report", systemImage: "ladybug.fill")
                            .badge(environments.crashReportManager.unreadCount)
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .crashReportReceived)) { _ in
                        Task {
                            try? await Task.sleep(nanoseconds: NSEC_PER_MSEC * 300)
                            showCrashReportList = true
                        }
                    }
                #else
                    FormNavigationLink {
                        CrashReportListView()
                    } label: {
                        #if os(tvOS)
                            HStack {
                                Label("Crash Report", systemImage: "ladybug.fill")
                                Spacer()
                                if environments.crashReportManager.unreadCount > 0 {
                                    Text("\(environments.crashReportManager.unreadCount)")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        #else
                            Label("Crash Report", systemImage: "ladybug.fill")
                                .badge(environments.crashReportManager.unreadCount)
                        #endif
                    }
                #endif
                FormTextItem("Taiwan Flag Available", "touchid") {
                    if viewModel.isLoading {
                        Text("Loading...")
                            .onAppear {
                                Task.detached {
                                    await viewModel.checkTaiwanFlagAvailability()
                                }
                            }
                    } else {
                        Text(viewModel.taiwanFlagAvailable.toString())
                    }
                }
            }
        }
    }
}

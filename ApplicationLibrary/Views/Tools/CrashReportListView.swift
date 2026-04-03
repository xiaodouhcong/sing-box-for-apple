import Libbox
import Library
import SwiftUI

@MainActor
public struct CrashReportListView: View {
    @EnvironmentObject private var environments: ExtensionEnvironments
    @State private var isLoading = true
    @State private var alert: AlertState?
    #if os(tvOS)
        @State private var showCrashTrigger = false
        @State private var selectedReport: CrashReport?
    #endif

    public init() {}

    private var manager: CrashReportManager {
        environments.crashReportManager
    }

    public var body: some View {
        FormView {
            if !isLoading, !manager.reports.isEmpty {
                Section("Reports") {
                    ForEach(manager.reports) { report in
                        #if os(tvOS)
                            Button {
                                selectedReport = report
                            } label: {
                                reportLabel(report)
                            }
                        #else
                            FormNavigationLink {
                                CrashReportDetailView(report: report)
                            } label: {
                                reportLabel(report)
                            }
                        #endif
                    }
                }
            }
        }
        .overlay {
            if isLoading {
                ProgressView()
            } else if manager.reports.isEmpty {
                Text("Empty")
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            Task {
                await manager.refresh()
                isLoading = false
            }
        }
        .navigationTitle("Crash Report")
        .alert($alert)
        #if os(tvOS)
            .navigationDestination(item: $selectedReport) { report in
                CrashReportDetailView(report: report)
                    .toolbar {
                        ToolbarItemGroup(placement: .topBarLeading) {
                            BackButton()
                        }
                    }
            }
        #endif
        #if os(tvOS)
        .navigationDestination(isPresented: $showCrashTrigger) {
            CrashTriggerView()
        }
        .toolbar {
            if SharedPreferences.inDebug {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        showCrashTrigger = true
                    } label: {
                        Image(systemName: "ant.fill")
                    }
                }
            }
            if !manager.reports.isEmpty {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            await manager.deleteAll()
                        }
                    } label: {
                        Image(systemName: "trash.fill")
                    }
                    .tint(.red)
                }
            }
        }
        #else
        .toolbar {
                    if !manager.reports.isEmpty || SharedPreferences.inDebug {
                        Menu {
                            if SharedPreferences.inDebug {
                                Menu {
                                    Menu("Application") {
                                        Button("Go Crash") {
                                            LibboxTriggerGoPanic()
                                        }
                                        Button("Native Crash") {
                                            DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(200)) {
                                                fatalError("debug native crash")
                                            }
                                        }
                                    }
                                    if let profile = environments.extensionProfile {
                                        NetworkExtensionCrashMenu(profile: profile)
                                    }
                                    #if os(macOS)
                                        RootHelperCrashMenu()
                                    #endif
                                } label: {
                                    Label("Crash Trigger", systemImage: "ant.fill")
                                }
                            }
                            if !manager.reports.isEmpty {
                                Button(role: .destructive) {
                                    Task {
                                        await manager.deleteAll()
                                    }
                                } label: {
                                    Label("Delete All", systemImage: "trash.fill")
                                }
                            }
                        } label: {
                            Label("Others", systemImage: "line.3.horizontal.circle")
                        }
                    }
                }
        #endif
    }

    private func reportLabel(_ report: CrashReport) -> some View {
        HStack(spacing: 8) {
            #if os(tvOS)
                Circle()
                    .fill(report.isRead ? .clear : .blue)
                    .frame(width: 10, height: 10)
            #endif
            VStack(alignment: .leading, spacing: 2) {
                Text(report.date, format: .dateTime)
                    .fontWeight(report.isRead ? .regular : .semibold)
                HStack(spacing: 4) {
                    Image(systemName: report.origin == "tvOS" ? "appletv.fill" : Self.localDeviceIcon)
                    Text(report.origin == "tvOS" ? "Apple TV" : "Local")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    #if os(iOS)
        private static let localDeviceIcon = "iphone"
    #elseif os(macOS)
        private static let localDeviceIcon = "desktopcomputer"
    #elseif os(tvOS)
        private static let localDeviceIcon = "appletv.fill"
    #endif
}

#if os(tvOS)
    private struct CrashTriggerView: View {
        @EnvironmentObject private var environments: ExtensionEnvironments

        var body: some View {
            Form {
                Section("Application") {
                    Button("Go Crash") {
                        LibboxTriggerGoPanic()
                    }
                    Button("Native Crash") {
                        DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(200)) {
                            fatalError("debug native crash")
                        }
                    }
                }
                if let profile = environments.extensionProfile, profile.status.isConnectedStrict {
                    Section("NetworkExtension") {
                        Button("Go Crash") {
                            try? LibboxNewStandaloneCommandClient()?.triggerGoCrash()
                            Task {
                                try? await Task.sleep(nanoseconds: NSEC_PER_SEC)
                                await environments.crashReportManager.refresh()
                            }
                        }
                        Button("Native Crash") {
                            try? LibboxNewStandaloneCommandClient()?.triggerNativeCrash()
                            Task {
                                try? await Task.sleep(nanoseconds: NSEC_PER_SEC)
                                await environments.crashReportManager.refresh()
                            }
                        }
                    }
                }
            }
            .navigationTitle("Crash Trigger")
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    BackButton()
                }
            }
        }
    }
#else
    private struct NetworkExtensionCrashMenu: View {
        @EnvironmentObject private var environments: ExtensionEnvironments
        @ObservedObject var profile: ExtensionProfile

        var body: some View {
            if profile.status.isConnectedStrict {
                Menu("NetworkExtension") {
                    Button("Go Crash") {
                        try? LibboxNewStandaloneCommandClient()?.triggerGoCrash()
                        Task {
                            try? await Task.sleep(nanoseconds: NSEC_PER_SEC)
                            await environments.crashReportManager.refresh()
                        }
                    }
                    Button("Native Crash") {
                        try? LibboxNewStandaloneCommandClient()?.triggerNativeCrash()
                        Task {
                            try? await Task.sleep(nanoseconds: NSEC_PER_SEC)
                            await environments.crashReportManager.refresh()
                        }
                    }
                }
            }
        }
    }
#endif

#if os(macOS)
    private struct RootHelperCrashMenu: View {
        @EnvironmentObject private var environments: ExtensionEnvironments

        var body: some View {
            if Variant.useSystemExtension, HelperServiceManager.rootHelperStatus == .enabled {
                Menu("RootHelper") {
                    Button("Go Crash") {
                        try? RootHelperClient.shared.triggerGoCrash()
                        Task {
                            try? await Task.sleep(nanoseconds: NSEC_PER_SEC)
                            await environments.crashReportManager.refresh()
                        }
                    }
                    Button("Native Crash") {
                        try? RootHelperClient.shared.triggerNativeCrash()
                        Task {
                            try? await Task.sleep(nanoseconds: NSEC_PER_SEC)
                            await environments.crashReportManager.refresh()
                        }
                    }
                }
            }
        }
    }
#endif

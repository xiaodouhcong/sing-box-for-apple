import Libbox
import Library
import SwiftUI

#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

@MainActor
public struct CrashReportDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var environments: ExtensionEnvironments

    @State private var alert: AlertState?
    @State private var files: [CrashReportFile] = []
    @State private var isLoading = true

    #if os(macOS)
        @State private var sharePresented = false
        @State private var shareItemURL: URL?
    #elseif os(tvOS)
        @State private var showExport = false
    #endif

    let report: CrashReport

    public init(report: CrashReport) {
        self.report = report
    }

    private var manager: CrashReportManager {
        environments.crashReportManager
    }

    #if !os(tvOS)
        private func shareReport(includeConfig: Bool) async {
            do {
                let zipURL = try await BlockingIO.run {
                    let tempDir = FilePath.cacheDirectory.appendingPathComponent("crash_reports", isDirectory: true)
                    try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
                    let tempURL = tempDir.appendingPathComponent("\(report.id).zip")
                    try? FileManager.default.removeItem(at: tempURL)
                    let sourceURL: URL
                    if !includeConfig {
                        let strippedURL = tempDir.appendingPathComponent(report.id, isDirectory: true)
                        try? FileManager.default.removeItem(at: strippedURL)
                        try FileManager.default.copyItem(at: report.fileURL, to: strippedURL)
                        try? FileManager.default.removeItem(at: strippedURL.appendingPathComponent("configuration.json"))
                        sourceURL = strippedURL
                    } else {
                        sourceURL = report.fileURL
                    }
                    var error: NSError?
                    LibboxCreateZipArchive(sourceURL.path, tempURL.path, &error)
                    if let error { throw error }
                    return tempURL
                }
                #if os(iOS)
                    guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                          let rootViewController = windowScene.keyWindow?.rootViewController
                    else {
                        return
                    }
                    var topViewController = rootViewController
                    while let presented = topViewController.presentedViewController {
                        topViewController = presented
                    }
                    topViewController.present(
                        UIActivityViewController(activityItems: [zipURL], applicationActivities: nil),
                        animated: true
                    )
                #elseif os(macOS)
                    shareItemURL = zipURL
                    sharePresented = true
                #endif
            } catch {
                alert = AlertState(action: "export crash reports", error: error)
            }
        }
    #endif

    public var body: some View {
        FormView {
            if !isLoading, !files.isEmpty {
                Section("Files") {
                    ForEach(files) { file in
                        if file.id == .metadata {
                            FormNavigationLink {
                                CrashReportMetadataFormView(file: file)
                            } label: {
                                Text(file.displayName)
                            }
                        } else {
                            FormNavigationLink {
                                CrashReportFileContentView(file: file)
                            } label: {
                                Text(file.displayName)
                            }
                        }
                    }
                }
            }
        }
        .overlay {
            if isLoading {
                ProgressView()
            } else if files.isEmpty {
                Text("Empty")
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            Task {
                files = await manager.availableFiles(for: report)
                manager.markAsRead(report)
                isLoading = false
            }
        }
        .alert($alert)
        #if os(tvOS)
            .navigationDestination(isPresented: $showExport) {
                ExportCrashReportView(report: report)
                    .toolbar {
                        ToolbarItemGroup(placement: .topBarLeading) {
                            BackButton()
                        }
                    }
            }
        #elseif os(macOS)
            .background(CrashReportSharingServicePicker($sharePresented, $alert, $shareItemURL))
        #endif
            .toolbar {
                if !isLoading, !files.isEmpty {
                    #if os(tvOS)
                        ToolbarItem(placement: .confirmationAction) {
                            Button {
                                showExport = true
                            } label: {
                                Image(systemName: "square.and.arrow.up")
                            }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button {
                                Task {
                                    await manager.delete(report)
                                    dismiss()
                                }
                            } label: {
                                Image(systemName: "trash.fill")
                            }
                            .tint(.red)
                        }
                    #else
                        if files.contains(where: { $0.id == .configContent }) {
                            Menu {
                                Button {
                                    Task {
                                        await shareReport(includeConfig: false)
                                    }
                                } label: {
                                    Label("Share", systemImage: "square.and.arrow.up")
                                }
                                Button {
                                    Task {
                                        await shareReport(includeConfig: true)
                                    }
                                } label: {
                                    Label("Share With Configuration", systemImage: "square.and.arrow.up.on.square")
                                }
                            } label: {
                                Label("Share", systemImage: "square.and.arrow.up")
                            }
                        } else {
                            Button {
                                Task {
                                    await shareReport(includeConfig: false)
                                }
                            } label: {
                                Label("Share", systemImage: "square.and.arrow.up")
                            }
                        }
                        Button(role: .destructive) {
                            Task {
                                await manager.delete(report)
                                dismiss()
                            }
                        } label: {
                            Label("Delete", systemImage: "trash.fill")
                                .foregroundStyle(.red)
                        }
                        .tint(.red)
                    #endif
                }
            }
            .navigationTitle(report.date.formatted(date: .abbreviated, time: .shortened))
    }
}

@MainActor
private struct CrashReportMetadataFormView: View {
    @State private var entries: [(key: String, value: String)] = []
    @State private var isLoading = true

    let file: CrashReportFile

    var body: some View {
        FormView {
            if !isLoading {
                Section {
                    ForEach(entries, id: \.key) { entry in
                        FormTextItem(LocalizedStringKey(entry.key), entry.value)
                    }
                }
            }
        }
        .overlay {
            if isLoading {
                ProgressView()
            } else if entries.isEmpty {
                Text("Empty")
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            Task.detached {
                let loaded = loadEntries()
                await MainActor.run {
                    entries = loaded
                    isLoading = false
                }
            }
        }
        .navigationTitle(file.displayName)
    }

    private nonisolated func loadEntries() -> [(key: String, value: String)] {
        guard let data = try? Data(contentsOf: file.fileURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return []
        }
        return json.compactMap { key, value in
            let stringValue = "\(value)"
            guard !stringValue.isEmpty, stringValue != "<null>" else { return nil }
            return (key, stringValue)
        }.sorted { $0.key < $1.key }
    }
}

@MainActor
private struct CrashReportFileContentView: View {
    @EnvironmentObject private var environments: ExtensionEnvironments

    @State private var content = ""
    @State private var isLoading = true

    let file: CrashReportFile

    private var manager: CrashReportManager {
        environments.crashReportManager
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .onAppear {
                        Task {
                            content = await manager.loadFileContent(file)
                            isLoading = false
                        }
                    }
            } else if content.isEmpty {
                Text("Empty")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                #if os(tvOS)
                    PlainTextView(content: content)
                #elseif os(iOS)
                    ScrollView {
                        PlainTextView(content: content)
                    }
                #else
                    PlainTextView(content: content)
                #endif
            }
        }
        .navigationTitle(file.displayName)
    }
}

#if os(macOS)
    private struct CrashReportSharingServicePicker: NSViewRepresentable {
        @Binding private var isPresented: Bool
        @Binding private var alert: AlertState?
        @Binding private var item: URL?

        init(_ isPresented: Binding<Bool>, _ alert: Binding<AlertState?>, _ item: Binding<URL?>) {
            _isPresented = isPresented
            _alert = alert
            _item = item
        }

        func makeNSView(context _: Context) -> NSView {
            NSView()
        }

        func updateNSView(_ nsView: NSView, context: Context) {
            if isPresented {
                guard let item else {
                    return
                }
                let picker = NSSharingServicePicker(items: [item])
                picker.delegate = context.coordinator
                picker.show(relativeTo: .zero, of: nsView, preferredEdge: .minY)
                DispatchQueue.main.async {
                    isPresented = false
                    self.item = nil
                }
            }
        }

        func makeCoordinator() -> Coordinator {
            Coordinator(self)
        }

        class Coordinator: NSObject, NSSharingServicePickerDelegate {
            private let parent: CrashReportSharingServicePicker

            init(_ parent: CrashReportSharingServicePicker) {
                self.parent = parent
            }

            func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker, didChoose _: NSSharingService?) {
                sharingServicePicker.delegate = nil
                parent.isPresented = false
            }
        }
    }
#endif

#if os(tvOS)
    private struct PlainTextView: UIViewRepresentable {
        let content: String

        private static let monoFont = UIFont.monospacedSystemFont(ofSize: 24, weight: .regular)

        func makeUIView(context _: Context) -> UITextView {
            let textView = UITextView()
            // isSelectable must be true for UITextView to be focusable on tvOS.
            // Without focus, the Siri Remote cannot scroll the content.
            // SwiftUI ScrollView + Text / LazyVStack + .focusable() do NOT work
            // reliably inside navigation destinations on tvOS.
            textView.isSelectable = true
            textView.isUserInteractionEnabled = true
            textView.isScrollEnabled = true
            textView.backgroundColor = .clear
            textView.textContainerInset = UIEdgeInsets(top: 40, left: 40, bottom: 40, right: 40)
            textView.textContainer.lineFragmentPadding = 0
            textView.font = Self.monoFont
            textView.textColor = .label
            textView.text = content
            textView.panGestureRecognizer.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirect.rawValue)]
            return textView
        }

        func updateUIView(_: UITextView, context _: Context) {}
    }

#elseif os(iOS)
    private struct PlainTextView: UIViewRepresentable {
        let content: String

        private static let monoFont = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)

        func makeUIView(context _: Context) -> UITextView {
            let textView = UITextView()
            textView.isEditable = false
            textView.isSelectable = true
            textView.isScrollEnabled = false
            textView.backgroundColor = .clear
            textView.textContainerInset = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
            textView.textContainer.lineFragmentPadding = 0
            textView.font = Self.monoFont
            textView.textColor = .label
            textView.text = content
            textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            return textView
        }

        func updateUIView(_: UITextView, context _: Context) {}
    }

#elseif os(macOS)
    private struct PlainTextView: NSViewRepresentable {
        let content: String

        private static let monoFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)

        func makeNSView(context _: Context) -> NSScrollView {
            let scrollView = NSScrollView()
            scrollView.hasVerticalScroller = true
            scrollView.hasHorizontalScroller = false
            scrollView.autohidesScrollers = true

            let textView = NSTextView()
            textView.isEditable = false
            textView.isSelectable = true
            textView.drawsBackground = false
            textView.textContainerInset = NSSize(width: 16, height: 16)
            textView.font = Self.monoFont
            textView.textColor = .labelColor
            textView.autoresizingMask = [.width]
            textView.string = content

            if let textContainer = textView.textContainer {
                textContainer.widthTracksTextView = true
                textContainer.containerSize = NSSize(width: scrollView.contentSize.width, height: .greatestFiniteMagnitude)
                textContainer.lineFragmentPadding = 0
            }

            scrollView.documentView = textView
            return scrollView
        }

        func updateNSView(_: NSScrollView, context _: Context) {}
    }
#endif

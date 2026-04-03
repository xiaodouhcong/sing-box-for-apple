import Foundation

public struct CrashReportMetadata: Codable, Sendable {
    public var source: String?
    public var bundleIdentifier: String?
    public var processName: String?
    public var processPath: String?
    public var startedAt: String?
    public var crashedAt: String?
    public var appVersion: String?
    public var appMarketingVersion: String?
    public var coreVersion: String?
    public var goVersion: String?
    public var signalName: String?
    public var signalCode: String?
    public var exceptionName: String?
    public var exceptionReason: String?
    public var deviceOrigin: String?

    public init(
        source: String? = nil,
        bundleIdentifier: String? = nil,
        processName: String? = nil,
        processPath: String? = nil,
        startedAt: String? = nil,
        crashedAt: String? = nil,
        appVersion: String? = nil,
        appMarketingVersion: String? = nil,
        coreVersion: String? = nil,
        goVersion: String? = nil,
        signalName: String? = nil,
        signalCode: String? = nil,
        exceptionName: String? = nil,
        exceptionReason: String? = nil,
        deviceOrigin: String? = nil
    ) {
        self.source = source
        self.bundleIdentifier = bundleIdentifier
        self.processName = processName
        self.processPath = processPath
        self.startedAt = startedAt
        self.crashedAt = crashedAt
        self.appVersion = appVersion
        self.appMarketingVersion = appMarketingVersion
        self.coreVersion = coreVersion
        self.goVersion = goVersion
        self.signalName = signalName
        self.signalCode = signalCode
        self.exceptionName = exceptionName
        self.exceptionReason = exceptionReason
        self.deviceOrigin = deviceOrigin
    }
}

public struct CrashReportArtifactContents {
    public var goLog: String?
    public var nativeLog: String?
    public var configContent: String?

    public init(goLog: String? = nil, nativeLog: String? = nil, configContent: String? = nil) {
        self.goLog = goLog
        self.nativeLog = nativeLog
        self.configContent = configContent
    }

    public var isEmpty: Bool {
        let goBody = goLog?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let nativeBody = nativeLog?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return goBody.isEmpty && nativeBody.isEmpty
    }
}

public enum CrashReportArchive {
    static let pendingNativeCrashDirectoryName = "native_crash_pending"
    static let pendingNativeCrashStorageDirectoryName = "com.plausiblelabs.crashreporter.data"
    static let pendingNativeCrashReportFileName = "live_report.plcrash"
    static let metadataFileName = "metadata.json"
    static let goLogFileName = "go.log"
    static let nativeLogFileName = "native.log"
    static let configFileName = "configuration.json"

    static var crashReportsDirectory: URL {
        FilePath.workingDirectory.appendingPathComponent("crash_reports", isDirectory: true)
    }

    static var pendingNativeCrashBaseDirectory: URL {
        FilePath.sharedDirectory.appendingPathComponent(pendingNativeCrashDirectoryName, isDirectory: true)
    }

    static func metadataURL(for artifactURL: URL) -> URL {
        artifactURL.appendingPathComponent(metadataFileName)
    }

    static func goLogURL(for artifactURL: URL) -> URL {
        artifactURL.appendingPathComponent(goLogFileName)
    }

    static func nativeLogURL(for artifactURL: URL) -> URL {
        artifactURL.appendingPathComponent(nativeLogFileName)
    }

    static func configURL(for artifactURL: URL) -> URL {
        artifactURL.appendingPathComponent(configFileName)
    }

    static func pendingNativeCrashReportURL(bundleIdentifier: String) -> URL {
        pendingNativeCrashReportURL(basePath: pendingNativeCrashBaseDirectory, bundleIdentifier: bundleIdentifier)
    }

    public static func pendingNativeCrashReportURL(basePath: URL, bundleIdentifier: String) -> URL {
        basePath
            .appendingPathComponent(pendingNativeCrashStorageDirectoryName, isDirectory: true)
            .appendingPathComponent(bundleIdentifier.replacingOccurrences(of: "/", with: "_"), isDirectory: true)
            .appendingPathComponent(pendingNativeCrashReportFileName)
    }

    public static func writeArchivedReport(contents: CrashReportArtifactContents, date: Date, metadata: CrashReportMetadata) throws -> URL {
        guard !contents.isEmpty else {
            throw NSError(domain: "CrashReportArchive", code: 1, userInfo: [NSLocalizedDescriptionKey: "Empty crash report"])
        }

        let dir = crashReportsDirectory
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let artifactURL = nextAvailableArtifactURL(for: date)
        try rewriteArchivedReport(at: artifactURL, contents: contents, metadata: metadata)
        return artifactURL
    }

    static func rewriteArchivedReport(at artifactURL: URL, contents: CrashReportArtifactContents, metadata: CrashReportMetadata) throws {
        guard !contents.isEmpty else {
            throw NSError(domain: "CrashReportArchive", code: 1, userInfo: [NSLocalizedDescriptionKey: "Empty crash report"])
        }

        try FileManager.default.createDirectory(at: artifactURL, withIntermediateDirectories: true)

        if let goLog = contents.goLog?.trimmingCharacters(in: .whitespacesAndNewlines), !goLog.isEmpty {
            try goLog.write(to: goLogURL(for: artifactURL), atomically: true, encoding: .utf8)
        } else {
            try? FileManager.default.removeItem(at: goLogURL(for: artifactURL))
        }

        if let nativeLog = contents.nativeLog?.trimmingCharacters(in: .whitespacesAndNewlines), !nativeLog.isEmpty {
            try nativeLog.write(to: nativeLogURL(for: artifactURL), atomically: true, encoding: .utf8)
        } else {
            try? FileManager.default.removeItem(at: nativeLogURL(for: artifactURL))
        }

        if let configContent = contents.configContent?.trimmingCharacters(in: .whitespacesAndNewlines), !configContent.isEmpty {
            try configContent.write(to: configURL(for: artifactURL), atomically: true, encoding: .utf8)
        } else {
            try? FileManager.default.removeItem(at: configURL(for: artifactURL))
        }

        let metadataData = try metadataEncoder.encode(metadata)
        try metadataData.write(to: metadataURL(for: artifactURL), options: .atomic)
    }

    public static func readMetadata(for artifactURL: URL) -> CrashReportMetadata? {
        guard let data = try? Data(contentsOf: metadataURL(for: artifactURL)) else {
            return nil
        }
        return try? JSONDecoder().decode(CrashReportMetadata.self, from: data)
    }

    public static func readContents(for artifactURL: URL) -> CrashReportArtifactContents {
        let goLog = try? String(contentsOf: goLogURL(for: artifactURL), encoding: .utf8)
        let nativeLog = try? String(contentsOf: nativeLogURL(for: artifactURL), encoding: .utf8)
        let configContent = try? String(contentsOf: configURL(for: artifactURL), encoding: .utf8)
        return CrashReportArtifactContents(goLog: goLog, nativeLog: nativeLog, configContent: configContent)
    }

    static func removeArtifact(at artifactURL: URL) {
        try? FileManager.default.removeItem(at: artifactURL)
    }

    static func crashDate(for artifactURL: URL) -> Date? {
        let name = artifactURL.lastPathComponent
        let components = name.components(separatedBy: "-")
        let baseName: String
        if components.count > 5, let suffix = components.last, Int(suffix) != nil {
            baseName = components.dropLast().joined(separator: "-")
        } else {
            baseName = components.joined(separator: "-")
        }
        return timestampFormatter.date(from: baseName)
    }

    static func formatMetadata(_ metadata: CrashReportMetadata) -> String {
        var lines: [String] = []
        if let source = metadata.source, !source.isEmpty {
            lines.append("Source: \(source)")
        }
        if let bundleIdentifier = metadata.bundleIdentifier, !bundleIdentifier.isEmpty {
            lines.append("Bundle: \(bundleIdentifier)")
        }
        if let processName = metadata.processName, !processName.isEmpty {
            lines.append("Process: \(processName)")
        }
        if let processPath = metadata.processPath, !processPath.isEmpty {
            lines.append("Path: \(processPath)")
        }
        if let startedAt = metadata.startedAt, !startedAt.isEmpty {
            lines.append("Started: \(startedAt)")
        }
        if let crashedAt = metadata.crashedAt, !crashedAt.isEmpty {
            lines.append("Crash: \(crashedAt)")
        }
        if let appMarketingVersion = metadata.appMarketingVersion, !appMarketingVersion.isEmpty {
            if let appVersion = metadata.appVersion, !appVersion.isEmpty {
                lines.append("App: \(appMarketingVersion) (\(appVersion))")
            } else {
                lines.append("App: \(appMarketingVersion)")
            }
        } else if let appVersion = metadata.appVersion, !appVersion.isEmpty {
            lines.append("App: \(appVersion)")
        }
        if let coreVersion = metadata.coreVersion, !coreVersion.isEmpty {
            lines.append("Core: \(coreVersion)")
        }
        if let goVersion = metadata.goVersion, !goVersion.isEmpty {
            lines.append("Go: \(goVersion)")
        }
        if let signalName = metadata.signalName, !signalName.isEmpty {
            if let signalCode = metadata.signalCode, !signalCode.isEmpty {
                lines.append("Signal: \(signalName) (\(signalCode))")
            } else {
                lines.append("Signal: \(signalName)")
            }
        } else if let signalCode = metadata.signalCode, !signalCode.isEmpty {
            lines.append("Signal Code: \(signalCode)")
        }
        if let exceptionName = metadata.exceptionName, !exceptionName.isEmpty {
            lines.append("Exception: \(exceptionName)")
        }
        if let exceptionReason = metadata.exceptionReason, !exceptionReason.isEmpty {
            lines.append("Reason: \(exceptionReason)")
        }
        return lines.joined(separator: "\n")
    }

    static func iso8601String(from date: Date) -> String {
        iso8601Formatter.string(from: date)
    }

    static func displayContent(for contents: CrashReportArtifactContents) -> String {
        let goBody = contents.goLog?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let nativeBody = contents.nativeLog?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if nativeBody.isEmpty {
            return goBody
        }
        if goBody.isEmpty {
            return nativeBody
        }

        var sections: [String] = []
        sections.append("===== Go Crash =====\n\n" + goBody)
        sections.append("===== Native Crash =====\n\n" + nativeBody)
        return sections.joined(separator: "\n\n")
    }

    private static func nextAvailableArtifactURL(for date: Date) -> URL {
        let dir = crashReportsDirectory
        let baseName = timestampFormatter.string(from: date)
        var index = 0
        while true {
            let suffix = index == 0 ? "" : "-\(index)"
            let artifactURL = dir.appendingPathComponent(baseName + suffix, isDirectory: true)
            if !FileManager.default.fileExists(atPath: artifactURL.path) {
                return artifactURL
            }
            index += 1
        }
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH-mm-ss"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    private static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    private static let metadataEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()
}

import BinaryCodable
import Foundation
import Library

public enum CrashReportTransferMessageType: UInt8 {
    case error = 0
    case report = 1
    case complete = 2
}

public struct CrashReportTransferPayload: Codable {
    public var metadata: CrashReportMetadata
    public var goLog: String?
    public var nativeLog: String?
    public var configContent: String?
    public var crashTimestamp: TimeInterval

    public init(metadata: CrashReportMetadata, goLog: String?, nativeLog: String?, configContent: String?, crashTimestamp: TimeInterval) {
        self.metadata = metadata
        self.goLog = goLog
        self.nativeLog = nativeLog
        self.configContent = configContent
        self.crashTimestamp = crashTimestamp
    }
}

public enum CrashReportTransferMessage {
    public static func encodeReport(_ payload: CrashReportTransferPayload) throws -> Data {
        var data = Data([CrashReportTransferMessageType.report.rawValue])
        try data.append(BinaryEncoder().encode(payload))
        return data
    }

    public static func encodeComplete() -> Data {
        Data([CrashReportTransferMessageType.complete.rawValue])
    }

    public static func encodeError(_ message: String) -> Data {
        var data = Data([CrashReportTransferMessageType.error.rawValue])
        data.append(Data(message.utf8))
        return data
    }

    public static func decodeType(_ data: Data) -> CrashReportTransferMessageType? {
        guard !data.isEmpty else { return nil }
        return CrashReportTransferMessageType(rawValue: data[0])
    }

    public static func decodeReport(_ data: Data) throws -> CrashReportTransferPayload {
        try BinaryDecoder().decode(CrashReportTransferPayload.self, from: data.dropFirst())
    }

    public static func decodeError(_ data: Data) -> String {
        String(data: data.dropFirst(), encoding: .utf8) ?? "Unknown error"
    }
}

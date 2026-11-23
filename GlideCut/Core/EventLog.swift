import Foundation

/// 轻量级线程安全日志器。
///
/// 同时做三件事：
/// 1. 在内存中保留最近若干行，供界面与自检读取；
/// 2. 追加写入 `~/Library/Application Support/GlideCut/glidecut.log`，便于事后取证；
/// 3. 输出到标准输出，便于从命令行直接观察。
///
/// 阶段一只记录事件监听相关的诊断信息，不记录任何用户内容。
final class EventLog {

    static let shared = EventLog()

    private let lock = NSLock()
    private var lines: [String] = []
    private let maxLines = 500
    private var fileHandle: FileHandle?
    private let fileURL: URL

    private init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GlideCut", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("glidecut.log")
        fileHandle = openHandle()
    }

    func log(_ message: String) {
        let line = "[\(Self.timestamp())] \(message)"
        lock.lock()
        lines.append(line)
        if lines.count > maxLines {
            lines.removeFirst(lines.count - maxLines)
        }
        let data = (line + "\n").data(using: .utf8) ?? Data()
        if let handle = fileHandle ?? openHandle() {
            handle.seekToEndOfFile()
            handle.write(data)
        } else {
            try? data.write(to: fileURL, options: .atomic)
        }
        lock.unlock()
        print(line)
    }

    func recent(limit: Int = 100) -> [String] {
        lock.lock()
        defer { lock.unlock() }
        let count = min(limit, lines.count)
        let start = max(0, lines.count - count)
        var result: [String] = []
        result.reserveCapacity(count)
        for index in start..<lines.count {
            result.append(lines[index])
        }
        return result
    }

    func clear() {
        lock.lock()
        lines.removeAll()
        lock.unlock()
        if let handle = fileHandle {
            try? handle.truncate(atOffset: 0)
        } else if FileManager.default.fileExists(atPath: fileURL.path) {
            try? FileManager.default.removeItem(atPath: fileURL.path)
        }
    }

    var logFileURL: URL { fileURL }

    /// 复用已有句柄；没有则新建并缓存，避免每次写日志都重新打开文件。
    private func openHandle() -> FileHandle? {
        if let existing = fileHandle {
            return existing
        }
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            fileHandle = handle
            return handle
        }
        return nil
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: Date())
    }
}

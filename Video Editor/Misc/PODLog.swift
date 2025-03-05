//
//  PODLog.swift
//  Video Editor
//
//  Created by Raidan on 2025. 03. 05..
//



import UIKit

#if DEBUG
private let shouldLog: Bool = true
#else
private let shouldLog: Bool = false
#endif

@inlinable
public func PODLogError(_ message: @autoclosure () -> String,
                        file: StaticString = #file,
                        function: StaticString = #function,
                        line: UInt = #line) {
    PODLog.log(message(), type: .error, file: file, function: function, line: line)
}

@inlinable
public func PODLogWarn(_ message: @autoclosure () -> String,
                       file: StaticString = #file,
                       function: StaticString = #function,
                       line: UInt = #line) {
    PODLog.log(message(), type: .warning, file: file, function: function, line: line)
}

@inlinable
public func PODLogInfo(_ message: @autoclosure () -> String,
                       file: StaticString = #file,
                       function: StaticString = #function,
                       line: UInt = #line) {
    PODLog.log(message(), type: .info, file: file, function: function, line: line)
}

@inlinable
public func PODLogDebug(_ message: @autoclosure () -> String,
                        file: StaticString = #file,
                        function: StaticString = #function,
                        line: UInt = #line) {
    PODLog.log(message(), type: .debug, file: file, function: function, line: line)
}

@inlinable
public func PODLogVerbose(_ message: @autoclosure () -> String,
                          file: StaticString = #file,
                          function: StaticString = #function,
                          line: UInt = #line) {
    PODLog.log(message(), type: .verbose, file: file, function: function, line: line)
}

public class PODLog {
    public enum LogType {
        case error
        case warning
        case info
        case debug
        case verbose
    }

    public static func log(_ message: @autoclosure () -> String,
                           type: LogType,
                           file: StaticString,
                           function: StaticString,
                           line: UInt) {
        guard shouldLog else { return }
        let fileName = String(describing: file).lastPathComponent
        let formattedMsg = String(
            format: "file:%@ func:%@ line:%d msg:---%@",
            fileName,
            String(describing: function),
            line, message()
        )
        PODLogFormatter.shared.log(message: formattedMsg, type: type)
    }
}

private extension String {
    var fileURL: URL {
        return URL(fileURLWithPath: self)
    }

    var pathExtension: String {
        return fileURL.pathExtension
    }

    var lastPathComponent: String {
        return fileURL.lastPathComponent
    }
}

class PODLogFormatter: NSObject {
    nonisolated(unsafe) static let shared = PODLogFormatter()
    let dateFormatter: DateFormatter

    override init() {
        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss:SSS"
        super.init()
    }

    func log(message logMessage: String, type: PODLog.LogType) {
        var logLevelStr: String
        switch type {
        case .error:
            logLevelStr = "‼️ Error"
        case .warning:
            logLevelStr = "⚠️ Warning"
        case .info:
            logLevelStr = "ℹ️ Info"
        case .debug:
            logLevelStr = "✅ Debug"
        case .verbose:
            logLevelStr = "⚪ Verbose"
        }

        let dateStr = dateFormatter.string(from: Date())
        let finalMessage = String(format: "%@ | %@ %@", logLevelStr, dateStr, logMessage)
        print(finalMessage)
    }
}

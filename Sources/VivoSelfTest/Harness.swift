import Foundation

/// 极简断言 harness。
///
/// 之所以不用 XCTest / swift-testing：本机只装了 Command Line Tools，
/// 工具链中不含这两个模块（已验证 `import XCTest` 与 `import Testing` 均报
/// "no such module"）。为保持零依赖，这里自带一套最小实现。
enum Check {
    nonisolated(unsafe) static var passed = 0
    nonisolated(unsafe) static var failed = 0
    nonisolated(unsafe) static var currentSuite = ""

    static func suite(_ name: String, _ body: () throws -> Void) {
        currentSuite = name
        print("\n── \(name)")
        do {
            try body()
        } catch {
            failed += 1
            print("  ✗ 抛出异常: \(error)")
        }
    }

    static func ok(_ condition: Bool, _ label: String, line: UInt = #line) {
        if condition {
            passed += 1
            print("  ✓ \(label)")
        } else {
            failed += 1
            print("  ✗ \(label)  (line \(line))")
        }
    }

    static func equal<T: Equatable>(
        _ actual: T, _ expected: T, _ label: String, line: UInt = #line
    ) {
        if actual == expected {
            passed += 1
            print("  ✓ \(label)")
        } else {
            failed += 1
            print("  ✗ \(label)  (line \(line))")
            print("      期望: \(format(expected))")
            print("      实际: \(format(actual))")
        }
    }

    static func isNil<T>(_ value: T?, _ label: String, line: UInt = #line) {
        ok(value == nil, label, line: line)
    }

    static func notNil<T>(_ value: T?, _ label: String, line: UInt = #line) {
        ok(value != nil, label, line: line)
    }

    static func throwsError(
        _ label: String, line: UInt = #line, _ body: () throws -> Void
    ) {
        do {
            try body()
            failed += 1
            print("  ✗ \(label) — 预期抛出但没有  (line \(line))")
        } catch {
            passed += 1
            print("  ✓ \(label)")
        }
    }

    /// 字节数组打印成 hex，其余用默认描述。
    private static func format<T>(_ value: T) -> String {
        if let bytes = value as? [UInt8] {
            return bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
        }
        return String(describing: value)
    }

    static func summary() -> Int32 {
        print("\n" + String(repeating: "─", count: 46))
        if failed == 0 {
            print("全部通过：\(passed) 项断言")
            return 0
        }
        print("失败 \(failed) 项，通过 \(passed) 项")
        return 1
    }
}

/// 十六进制字符串 → 字节数组（允许空格分隔）。
func hx(_ text: String) -> [UInt8] {
    let compact = text.replacingOccurrences(of: " ", with: "")
    var out: [UInt8] = []
    var idx = compact.startIndex
    while idx < compact.endIndex {
        let next = compact.index(idx, offsetBy: 2)
        out.append(UInt8(compact[idx..<next], radix: 16)!)
        idx = next
    }
    return out
}

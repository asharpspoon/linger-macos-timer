import Foundation

/// SemVer 语义化版本解析与比较（纯逻辑，Foundation-only，可单测）。
///
/// 为什么不用字符串比较：`"2.10.0" < "2.9.0"`（字典序）——数字必须逐段比。
/// 宽松输入：接受 `v2.5.1` / `2.5` / `2.5.1-beta`（ prerelease 后缀忽略，
/// 同号带 prerelease 视为等于不带 —— 本项目 tag 不用 prerelease，够用）。
struct SemVer: Equatable, Comparable {
    let major: Int
    let minor: Int
    let patch: Int

    init(_ version: String) {
        // 去 v 前缀、去 prerelease/build 后缀（-beta、+build.1）
        var s = version.trimmingCharacters(in: .whitespaces)
        while s.hasPrefix("v") || s.hasPrefix("V") { s.removeFirst() }
        if let dash = s.firstIndex(where: { $0 == "-" || $0 == "+" }) {
            s = String(s[s.startIndex..<dash])
        }
        let parts = s.split(separator: ".").compactMap { Int($0) }
        major = parts.count > 0 ? parts[0] : 0
        minor = parts.count > 1 ? parts[1] : 0
        patch = parts.count > 2 ? parts[2] : 0
    }

    init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    static func < (lhs: SemVer, rhs: SemVer) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }

    var stringValue: String { "\(major).\(minor).\(patch)" }
}

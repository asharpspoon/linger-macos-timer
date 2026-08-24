import Foundation

/// 版本号唯一真源（2026-08-24 B 组：检查更新）。
/// 构建脚本 build_and_run.sh 通过 grep 读取此常量生成 Info.plist，
/// 运行时检查更新也读它 —— 两处共用一份，杜绝双号漂移。
/// 发版流程：改这里 → ./script/build_and_run.sh --release → git tag v同版本号。
enum AppVersion {
    /// 当前应用版本（发版时更新，格式严格 SemVer：主.次.修订）
    static let current = "2.5.1"

    /// GitHub 仓库（owner/repo），检查更新与下载直链的来源
    static let gitHubRepo = "asharpspoon/linger-macos-timer"
}

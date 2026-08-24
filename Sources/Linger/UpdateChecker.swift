import Foundation

/// 检查更新（方案 A：GitHub Releases API，见 docs/update-design.md）。
///
/// 职责：
/// - 请求 `GET /repos/{repo}/releases/latest`，解析 tag / 说明 / dmg 直链
/// - SemVer 比较（当前 AppVersion.current vs 远端 tag）
/// - 策略层：自动检查 24h 节流；「忽略此版本」持久化；失败静默（手动检查才上报错误）
///
/// 线程模型：任意线程发起；回调统一 dispatch 回主线程。
/// 无 Token：公开仓库 latest API 限速 60 次/h/IP，对「启动一次查一次」绰绰有余。
final class UpdateChecker {

    /// 检查结果
    enum Result {
        /// 有新版：远端 tag（含 v 前缀原样）、展示用纯数字版本、更新说明、下载直链
        case available(tag: String, version: String, notes: String?, downloadURL: URL)
        /// 已是最新（或远端版本被用户忽略）
        case upToDate
        /// 仅手动检查时 surfaced；自动检查静默
        case failed(String)
    }

    // GitHub Releases latest 响应（只取需要的字段）
    private struct ReleaseDTO: Decodable {
        let tag_name: String
        let body: String?
        let html_url: String
        let assets: [AssetDTO]
        struct AssetDTO: Decodable {
            let name: String
            let browser_download_url: String
        }
    }

    static let shared = UpdateChecker()

    private let session: URLSession
    private let defaults: UserDefaults
    private var inFlight = false   // 防重入（启动检查与手动检查撞车）

    private enum Key {
        static let lastAutoCheck = "linger_update_lastAutoCheck"
        static let skippedTag = "linger_update_skippedTag"
    }

    /// 自动检查节流间隔（24h）
    private let autoCheckInterval: TimeInterval = 24 * 3600

    init(session: URLSession = .shared, defaults: UserDefaults = .standard) {
        self.session = session
        self.defaults = defaults
    }

    /// 手动「检查更新…」：无视节流，失败也上报
    func checkManually(completion: @escaping (Result) -> Void) {
        performCheck(completion: completion)
    }

    /// 启动静默检查：节流（默认 24h 一次）+ 忽略版本 + 失败静默
    func checkSilentlyOnLaunch() {
        // 距上次检查不足间隔 → 跳过（不发请求）
        if let last = defaults.object(forKey: Key.lastAutoCheck) as? Date,
           Date().timeIntervalSince(last) < autoCheckInterval { return }
        performCheck { [weak self] result in
            guard let self, case .available(let tag, let ver, let notes, let url) = result else { return }
            // 用户已忽略此版本 → 静默
            if self.defaults.string(forKey: Key.skippedTag) == tag { return }
            DispatchQueue.main.async {
                UpdatePanel.shared.present(tag: tag, version: ver, notes: notes, downloadURL: url)
            }
        }
    }

    /// 记录「忽略此版本」
    func skip(tag: String) {
        defaults.set(tag, forKey: Key.skippedTag)
    }

    // MARK: - 核心

    private func performCheck(completion: @escaping (Result) -> Void) {
        guard !inFlight else { return }
        inFlight = true

        var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(AppVersion.gitHubRepo)/releases/latest")!)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 15

        session.dataTask(with: req) { [weak self] data, response, error in
            guard let self else { return }
            self.inFlight = false
            // 打点节流：无论手动/静默、成败与否，查过一次就记时间
            //（手动多查几次无妨，远低于 GitHub 60/h 限速）
            self.defaults.set(Date(), forKey: Key.lastAutoCheck)
            let result = self.parse(data: data, response: response, error: error)
            DispatchQueue.main.async { completion(result) }
        }.resume()
    }

    private func parse(data: Data?, response: URLResponse?, error: Error?) -> Result {
        if let error { return .failed(error.localizedDescription) }
        guard let http = response as? HTTPURLResponse else { return .failed("无响应") }
        guard http.statusCode == 200 else {
            // 403 = 限速；404 = 还没有任何 Release
            return .failed("GitHub API HTTP \(http.statusCode)")
        }
        guard let data,
              let dto = try? JSONDecoder().decode(ReleaseDTO.self, from: data) else {
            return .failed("响应解析失败")
        }

        let remote = SemVer(dto.tag_name)
        let current = SemVer(AppVersion.current)
        guard remote > current else { return .upToDate }

        // 下载直链：优先 .dmg 资产，否则回退 Release 页面
        let dmg = dto.assets.first { $0.name.hasSuffix(".dmg") }
        let urlString = dmg?.browser_download_url ?? dto.html_url
        guard let url = URL(string: urlString) else { return .failed("下载链接无效") }

        let displayVer = dto.tag_name.hasPrefix("v") ? String(dto.tag_name.dropFirst()) : dto.tag_name
        return .available(tag: dto.tag_name, version: displayVer,
                          notes: dto.body, downloadURL: url)
    }
}

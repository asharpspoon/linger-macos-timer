import XCTest
@testable import Linger

/// 2026-08-24 B 组：SemVer 解析与比较（检查更新的版本判断核心）
final class SemVerTests: XCTestCase {

    func testParseVariants() {
        XCTAssertEqual(SemVer("2.5.1"), SemVer(major: 2, minor: 5, patch: 1))
        XCTAssertEqual(SemVer("v2.5.1"), SemVer(major: 2, minor: 5, patch: 1))
        XCTAssertEqual(SemVer("2.5"), SemVer(major: 2, minor: 5, patch: 0))
        XCTAssertEqual(SemVer("2.5.1-beta"), SemVer(major: 2, minor: 5, patch: 1))
        XCTAssertEqual(SemVer(" 3.0.0 "), SemVer(major: 3, minor: 0, patch: 0))
    }

    func testCompare() {
        XCTAssertTrue(SemVer("2.5.1") > SemVer("2.5.0"), "patch 位比较")
        XCTAssertTrue(SemVer("2.10.0") > SemVer("2.9.0"),
                      "字符串比较会得出 2.10 < 2.9 —— 本类的存在意义")
        XCTAssertTrue(SemVer("3.0.0") > SemVer("2.99.99"), "major 优先")
        XCTAssertTrue(SemVer("v2.6.0") > SemVer("2.5.1"), "GitHub tag 带 v 前缀")
        XCTAssertFalse(SemVer("2.5.1") > SemVer("2.5.1"), "相等不算更新")
        XCTAssertFalse(SemVer("2.5.0") > SemVer("2.5.1"), "降级不算更新")
    }

    func testMalformedInputFallsBackToZero() {
        XCTAssertEqual(SemVer("abc"), SemVer(major: 0, minor: 0, patch: 0))
        XCTAssertEqual(SemVer(""), SemVer(major: 0, minor: 0, patch: 0))
        // 解析失败 → 0.0.0 < 任何当前版本 → upToDate，安全侧
        XCTAssertFalse(SemVer("garbage") > SemVer(AppVersion.current))
    }
}

/// GitHub Releases JSON 结构与版本判定组合语义（镜像 ReleaseDTO 形状，不联网）
final class ReleaseJSONShapeTests: XCTestCase {

    func testJSONShapeDecodesAndDetectsUpdate() {
        // 与 UpdateChecker.ReleaseDTO 相同形状：字段名错了这里立刻红
        struct ReleaseDTO: Decodable {
            let tag_name: String
            let body: String?
            let html_url: String
            let assets: [Asset]
            struct Asset: Decodable {
                let name: String
                let browser_download_url: String
            }
        }
        let json = """
        {"tag_name":"v2.6.0","body":"修复若干","html_url":"https://github.com/x/y/releases/tag/v2.6.0",
         "assets":[{"name":"Linger-2.6.0.dmg","browser_download_url":"https://example.com/dmg"}]}
        """
        let dto = try? JSONDecoder().decode(ReleaseDTO.self, from: json.data(using: .utf8)!)
        XCTAssertNotNil(dto)
        XCTAssertEqual(dto?.tag_name, "v2.6.0")
        XCTAssertEqual(dto?.assets.first?.name, "Linger-2.6.0.dmg")
        // 组合语义：远端 v2.6.0 > 当前 → 应判为有更新
        XCTAssertTrue(SemVer(dto!.tag_name) > SemVer(AppVersion.current))
    }

    func testEqualTagMeansUpToDate() {
        // 远端 == 当前 → 不算更新（发版后自查不应误报）
        XCTAssertFalse(SemVer("v2.5.1") > SemVer(AppVersion.current))
    }
}

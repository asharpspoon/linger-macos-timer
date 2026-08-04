import XCTest
@testable import Linger

final class DragPhysicsTests: XCTestCase {

    func testNoOvershootReturnsZero() {
        XCTAssertEqual(DragPhysics.dampedOvershoot(0), 0, accuracy: 0.0001)
        XCTAssertEqual(DragPhysics.dampedOvershoot(-10), 0, accuracy: 0.0001)
    }

    func testDampedOvershootNeverExceedsHeadroom() {
        for overshoot in stride(from: 0.0, through: 5000.0, by: 25.0) {
            let v = DragPhysics.dampedOvershoot(overshoot, headroom: 40)
            XCTAssertGreaterThanOrEqual(v, 0)
            // Double 在极大 overshoot 时数学上趋近 headroom 并饱和到 40.0，允许等于
            XCTAssertLessThanOrEqual(v, 40, "overshoot=\(overshoot) must not exceed headroom")
        }
        // 中等过拉仍严格低于上限（体现「越拉越顶手」）
        XCTAssertLessThan(DragPhysics.dampedOvershoot(200, headroom: 40), 40)
    }

    func testLineWidthNoOvershootStaysNormal() {
        XCTAssertEqual(DragPhysics.lineWidth(overshoot: 0), 4, accuracy: 0.0001)
        XCTAssertEqual(DragPhysics.lineWidth(overshoot: -10), 4, accuracy: 0.0001)
    }

    func testLineWidthThinsContinuouslyTowardMin() {
        // 指数衰减（k=60）：拉过 40px → 2 + 2*e^(-40/60) ≈ 3.027
        XCTAssertEqual(DragPhysics.lineWidth(overshoot: 40), 2 + 2 * exp(-40.0 / 60.0), accuracy: 0.0001)
        // 单调递减且不低于 min
        var prev = DragPhysics.lineWidth(overshoot: 0)
        for o in stride(from: 0.0, through: 400.0, by: 20.0) {
            let v = DragPhysics.lineWidth(overshoot: o)
            XCTAssertLessThanOrEqual(v, prev, "must be monotonically non-increasing")
            XCTAssertGreaterThanOrEqual(v, 2 - 0.0001, "must not go below minWidth")
            prev = v
        }
        // 极大 overshoot 饱和到 minWidth（允许浮点等于 2）
        XCTAssertLessThanOrEqual(DragPhysics.lineWidth(overshoot: 5000), 2 + 0.0001)
    }

    func testLineMaxDistanceSyncsWithMaxDuration() {
        // 30 分钟 → 40·√30 ≈ 219.09；60 分钟 → 40·√60 ≈ 309.84
        XCTAssertEqual(DragPhysics.lineMaxDistance(maxMinutes: 30), 40 * sqrt(30), accuracy: 0.0001)
        XCTAssertEqual(DragPhysics.lineMaxDistance(maxMinutes: 60), 40 * sqrt(60), accuracy: 0.0001)
        XCTAssertEqual(DragPhysics.lineMaxDistance(maxMinutes: 0), 40 * sqrt(30), accuracy: 0.0001)  // 缺省 30
        // 更长时长 → 更长的线
        XCTAssertGreaterThan(DragPhysics.lineMaxDistance(maxMinutes: 60),
                             DragPhysics.lineMaxDistance(maxMinutes: 30))
    }

    func testDampedOvershootIsResistantAndMonotonic() {
        // overshoot=40 → ~25.3：远不到 40，体现「越拉越顶手」
        let at40 = DragPhysics.dampedOvershoot(40, headroom: 40)
        XCTAssertGreaterThan(at40, 40 * 0.5)
        XCTAssertLessThan(at40, 40 * 0.7)

        // 单调递增：拉得越狠，延伸越多（但增速放缓）
        let a = DragPhysics.dampedOvershoot(10, headroom: 40)
        let b = DragPhysics.dampedOvershoot(80, headroom: 40)
        let c = DragPhysics.dampedOvershoot(400, headroom: 40)
        XCTAssertGreaterThan(b, a)
        XCTAssertGreaterThan(c, b)
        // 增速放缓：80→400 的增量远小于 10→80
        XCTAssertLessThan(c - b, b - a)
    }
}

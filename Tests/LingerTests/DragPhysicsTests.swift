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

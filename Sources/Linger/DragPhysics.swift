//  DragPhysics.swift
//  拖拽反馈的纯物理逻辑（Foundation-only，可单测）。
//  与视图层隔离：这里只提供「数值 → 数值」的纯函数，渲染交给 DragLineView。

import Foundation

enum DragPhysics {

    /// iOS 式橡皮筋阻尼：越过最大长度后，额外位移被阻尼、阻力渐增。
    ///
    /// - `overshoot`：越过最大长度的额外像素（>0 才生效）
    /// - `headroom`：视觉上最多再延伸多少像素（默认 40）
    ///
    /// 曲线：`headroom * (1 - e^(-overshoot / headroom))` ——
    /// 越拉越「顶手」，但永远到不了 headroom，松手即回弹归位。
    static func dampedOvershoot(_ overshoot: Double, headroom: Double = 40) -> Double {
        guard overshoot > 0, headroom > 0 else { return 0 }
        return headroom * (1 - exp(-overshoot / headroom))
    }

    /// 触顶后线条变细公式：随 overshoot 增加，宽度从 normalWidth 连续衰减到 minWidth。
    ///
    /// 指数曲线：`min + (normal - min) * e^(-overshoot / k)`，
    /// - `k` 为衰减常数（默认 40px：拉过 40px 衰减到差值约 63%，拉过 120px 基本到底）
    /// - overshoot ≤ 0 时恒为 normalWidth（未触顶不细）
    static func lineWidth(overshoot: Double,
                          normalWidth: Double = 4,
                          minWidth: Double = 2,
                          k: Double = 40) -> Double {
        guard overshoot > 0 else { return normalWidth }
        return minWidth + (normalWidth - minWidth) * exp(-overshoot / k)
    }
}

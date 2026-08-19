import Foundation

/// 鼠标悬停胶囊自动展开抽屉的**纯判定**（owner 2026-08-19）。
///
/// 为什么单独抽出来：这套判定和拖动弹簧（`PanelCoordinator.updateSpringLoad`）形状几乎一样，
/// 但触发条件、归属权和关闭条件都不同，混在一起写必然出现「拖动中被悬停逻辑抢开」这类互踩。
/// 判定留在这里（可单测），定时器与几何命中留在 `PanelCoordinator`。
///
/// 三条不变量：
/// 1. **拖动中一律让位**——拖动有自己的弹簧路径（0.4s 开 / 0.35s 收），两套定时器不能同时在跑。
/// 2. **只自动收起自己开的抽屉**。点击开的抽屉是用户的明确意图，鼠标移开不该把它收掉；
///    这就是 `hoverOpened` 存在的唯一理由（与 `drawerSpringOpened` 同构）。
/// 3. **跨屏只搬自己开的**。悬停另一块屏的胶囊时，若当前抽屉是点击开的，不要把它搬走。
enum DrawerHoverPlan {
    /// 定时器动作。同一次输入可能要求多条（例如「取消收起」+「起开」）。
    enum Action: Equatable {
        case armOpen
        case cancelOpen
        case armClose
        case cancelClose
    }

    struct Input: Equatable {
        /// 指针在**某块屏**的胶囊命中区内（含容差）。
        var insideCapsule: Bool
        /// 指针在抽屉体命中区内（含容差）。
        var insideDrawer: Bool
        /// 设置项「鼠标悬停自动展开抽屉」。
        var enabled: Bool
        /// 有拖动进行中（弹簧路径接管）。
        var isDragging: Bool
        /// 抽屉当前逻辑打开。
        var drawerOpen: Bool
        /// 当前打开的抽屉是**悬停**开出来的（而非点击 / 弹簧）。
        var hoverOpened: Bool
        /// 已打开的抽屉就在指针所在这块屏上。`drawerOpen == false` 时无意义。
        var openOnHoveredScreen: Bool
    }

    static func decide(_ input: Input) -> [Action] {
        // 不变量 1：关掉、或拖动中 → 两个定时器都停，什么都不做。
        guard input.enabled, !input.isDragging else { return [.cancelOpen, .cancelClose] }

        if input.insideCapsule {
            if !input.drawerOpen {
                return [.cancelClose, .armOpen]
            }
            // 不变量 3：已开在别的屏，且是我自己悬停开的 → 搬过来；点击开的不动。
            if !input.openOnHoveredScreen, input.hoverOpened {
                return [.cancelClose, .armOpen]
            }
            return [.cancelClose, .cancelOpen]
        }

        if input.insideDrawer {
            // 在抽屉里 → 绝不收起，也别再开。
            return [.cancelClose, .cancelOpen]
        }

        // 两处都不在：取消尚未触发的展开；不变量 2：只有自己开的才起收起定时器。
        if input.drawerOpen, input.hoverOpened {
            return [.cancelOpen, .armClose]
        }
        return [.cancelOpen, .cancelClose]
    }
}

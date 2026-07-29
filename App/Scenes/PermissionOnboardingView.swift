import AppKit
import SwiftUI

/// 窗口的根视图。滚动条平时不出现——窗口高度由内容自然高度决定，
/// 只有在被屏幕高度截断时才真的需要滚。
struct PermissionOnboardingWindowContent: View {
    @ObservedObject var coordinator: PermissionRecoveryCoordinator

    var body: some View {
        ScrollView(.vertical) {
            PermissionOnboardingView(coordinator: coordinator)
        }
        .frame(width: PermissionOnboardingView.contentWidth)
    }
}

struct PermissionOnboardingView: View {
    /// 视图只观察这一个源。
    @ObservedObject var coordinator: PermissionRecoveryCoordinator

    /// 内容宽度固定：窗口高度由 `fittingSize` 决定，宽度不能跟着文案长短抖。
    static let contentWidth: CGFloat = 520

    private var presentation: PermissionPresentation {
        coordinator.presentation ?? .waiting
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            Text(message)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(.secondary)
            if let troubleshooting {
                troubleshootingBox(troubleshooting)
            }
            HStack(spacing: 8) {
                Spacer()
                actions
            }
        }
        .padding(28)
        .frame(width: Self.contentWidth, alignment: .leading)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: symbolName)
                .font(.system(size: 28))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title3.weight(.semibold))
                Text(subtitle)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func troubleshootingBox(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("已经打开开关，却还是没反应？")
                .font(.callout.weight(.semibold))
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.secondary.opacity(0.1))
        )
    }

    // MARK: - 文案

    private var symbolName: String {
        switch presentation {
        case .moveToApplications: return "folder.badge.plus"
        case .waiting, .stalled: return "lock.shield"
        case .recoveryWaiting, .recoveryStalled: return "exclamationmark.shield"
        case .restoringWindows, .relaunching: return "arrow.clockwise"
        case .relaunchFailed: return "xmark.octagon"
        }
    }

    private var title: String {
        switch presentation {
        case .moveToApplications: return "请先移到“应用程序”"
        case .waiting, .stalled: return "需要开启辅助功能权限"
        case .recoveryWaiting, .recoveryStalled: return "辅助功能权限已失效"
        case .restoringWindows: return "正在还原窗口…"
        case .relaunching: return "正在重启钨极…"
        case .relaunchFailed: return "重启失败"
        }
    }

    private var subtitle: String {
        switch presentation {
        case .moveToApplications: return "当前副本位于临时或只读位置。"
        case .waiting, .stalled: return "Tungsten Edge 需要这项权限来读取和操作窗口。"
        case .recoveryWaiting, .recoveryStalled: return "重新授权后钨极会自动重启。"
        case .restoringWindows: return "正在把之前让开过的窗口放回原位。"
        case .relaunching: return "马上就好。"
        case .relaunchFailed: return "钨极还在运行，可以重试。"
        }
    }

    private var message: String {
        switch presentation {
        case .moveToApplications:
            return """
            macOS 会把辅助功能授权绑定到具体的应用副本上。当前这份钨极跑在一个临时或只读的位置，\
            就算你打开了开关也不会生效，而且卸载磁盘映像后那条授权记录还会留在系统里。\
            请把 Tungsten Edge 拖到“应用程序”文件夹，再从那里重新打开。
            """
        case .waiting, .stalled:
            return "请在\(settingsPath)中，打开 Tungsten Edge 钨极的开关。开启后本窗口会自动关闭，任务条会继续启动。"
        case .recoveryWaiting, .recoveryStalled:
            return "钨极刚才失去了辅助功能权限，任务条已经收起。请在\(settingsPath)中重新打开 Tungsten Edge 钨极的开关。"
        case .restoringWindows, .relaunching:
            return "请稍候，不用操作。"
        case let .relaunchFailed(message):
            return "没能启动新的钨极实例：\(message)\n\n可以点“重试”，或者退出后从“应用程序”手动打开。"
        }
    }

    /// 「删旧条目重加」只是**条件式排障建议**：我们读不到系统的授权数据库，
    /// 既证明不了用户有没有打开开关，也证明不了旧记录已经失配。文案必须保持不确定语气，
    /// 也不能预设签名方式——固定证书签的包授权是跨版本有效的。
    private var troubleshooting: String? {
        let steps = """
        如果你已经打开了开关却还是没生效，可能是旧版本留下的授权记录不再匹配当前这份钨极。可以这样重置一次：

        1. 先退出钨极——应用还在运行时，列表里的减号是灰的，删不掉。
        2. 在“隐私与安全性 → 辅助功能”里把列表中的 Tungsten Edge 用减号删掉，可能不止一条，都删掉。
        3. 从“应用程序”重新打开钨极，按提示重新添加并打开开关。
        """
        switch presentation {
        case .stalled:
            return steps
        case .recoveryStalled:
            return steps + """


            如果直接把开关打开就生效了，钨极会自己重启，不用管；走上面的清理步骤则需要退出后手动重开。
            另外，之前被任务条让开过的窗口可能会矮一条边——重新最大化一次就复原了。
            """
        default:
            return nil
        }
    }

    private var settingsPath: String {
        if #available(macOS 13, *) {
            return "系统设置的“隐私与安全性 > 辅助功能”"
        }
        return "系统偏好设置的“安全性与隐私 > 隐私 > 辅助功能”"
    }

    // MARK: - 按钮

    @ViewBuilder
    private var actions: some View {
        switch presentation {
        case .moveToApplications:
            quitButton
            Button("打开“应用程序”") { coordinator.openApplications() }
                .keyboardShortcut(.defaultAction)

        case .waiting, .recoveryWaiting:
            quitButton
            Button("打开系统设置") { coordinator.openSettings() }
                .keyboardShortcut(.defaultAction)

        case .stalled, .recoveryStalled:
            quitButton
            Button("重新检测") { coordinator.recheck() }
            Button("打开系统设置") { coordinator.openSettings() }
                .keyboardShortcut(.defaultAction)

        case .restoringWindows, .relaunching:
            ProgressView()
                .controlSize(.small)

        case .relaunchFailed:
            quitButton
            Button("重试") { coordinator.retryRelaunch() }
                .keyboardShortcut(.defaultAction)
        }
    }

    private var quitButton: some View {
        Button("退出") { coordinator.quit() }
            .keyboardShortcut(.cancelAction)
    }
}

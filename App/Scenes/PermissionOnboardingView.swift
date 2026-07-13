import ApplicationServices
import AppKit
import SwiftUI

/// 轮询「辅助功能」权限状态：每秒一次 `AXIsProcessTrusted()`，
/// 一旦授予就回调 `onGranted` 启动 app。
@MainActor
final class AccessibilityPermissionModel: ObservableObject {
    var onGranted: (() -> Void)?
    private var timer: Timer?

    func startPolling() {
        if AXIsProcessTrusted() { onGranted?(); return }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            guard AXIsProcessTrusted() else { return }
            Task { @MainActor [weak self] in
                self?.onGranted?()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }
}

struct PermissionOnboardingView: View {
    let onOpenSettings: () -> Void
    let onQuit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 28))
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 4) {
                    Text("需要开启辅助功能权限")
                        .font(.title3.weight(.semibold))
                    Text("Tungsten Edge 需要这项权限来读取和操作窗口。")
                        .foregroundStyle(.secondary)
                }
            }

            Text("请在系统设置的“隐私与安全性 > 辅助功能”中，打开 Tungsten Edge 钨极的开关。开启后本窗口会自动关闭，任务条会继续启动。")
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("退出") { onQuit() }
                    .keyboardShortcut(.cancelAction)
                Button("打开系统设置") { onOpenSettings() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 500)
    }
}

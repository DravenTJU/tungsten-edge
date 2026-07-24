import Darwin

/// 进程存活判定的唯一合同（POSIX `kill(pid, 0)`）。
///
/// `AppTracker.reconcile()` 的批量删除路径曾用 `NSRunningApplication(processIdentifier:) == nil`
/// 判死。该 API 解析自 LaunchServices，会对**活**进程瞬时返回 `nil`（实测飞书、Obsidian 等会触发），
/// 导致整个 `AppEntry` 连同其下所有座位被 `reconcile()` 的批量路径一并删掉，绕过逐座位宽限与
/// 幽灵保护。之后 `scanNonAdmittedApps()` 又把同一 pid 以全新座位 token 重新准入，叠加
/// `StripOrderStore` 的 5s 缺席宽限 → 一扇窗出现两张卡。
///
/// 这里只走 POSIX：`kill` 返回 0 即活；返回 -1 且 `errno == ESRCH` 才判死；`EPERM`（进程存在、
/// 但无权限发信号）及其他所有 errno 一律保守判活。**绝不**回退 `NSRunningApplication` /
/// `NSWorkspace` / 其他 LaunchServices 状态。旧脏 worktree 的同名文件在未知 errno 时回退
/// LaunchServices，是错误实现，禁止整包搬运。
///
/// 只依赖 Darwin，不引入 AppKit / ApplicationServices，便于 errno 矩阵单测。
enum ProcessLiveness {
    /// 用 POSIX `kill(pid, 0)` 判定进程是否存活。
    static func isAlive(pid: pid_t) -> Bool {
        interpret(result: kill(pid, 0), errorCode: errno)
    }

    /// 纯判定函数，供 errno 矩阵单测直接喂入合成值，不发起 syscall：
    /// - `result == 0`：alive
    /// - `result != 0` 且 `errorCode == ESRCH`：dead（无此进程）
    /// - `EPERM` 及 `EINTR` / `EINVAL` / `EAGAIN` 等所有其他 errno：alive（保守判活）
    static func interpret(result: Int32, errorCode: Int32) -> Bool {
        if result == 0 { return true }
        return errorCode != ESRCH
    }
}

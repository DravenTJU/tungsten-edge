import XCTest
@testable import macos_dock_cc_v2

final class BuildProvenanceTests: XCTestCase {
    func testInstalledReleaseBuildGetsNoSuffix() {
        XCTAssertNil(BuildProvenance.suffix(
            isDebugBuild: false,
            bundlePath: "/Applications/Tungsten Edge.app"
        ))
    }

    func testDebugBuildIsMarkedRegardlessOfLocation() {
        // 事故现场：登录项钉在 DerivedData 上，开机起来的是这个包。
        XCTAssertEqual(BuildProvenance.suffix(
            isDebugBuild: true,
            bundlePath: "/Users/caye/Projects/macos-dock-cc-v2/build/DerivedData/Build/Products/Debug/macos-dock-cc-v2.app"
        ), "开发版")
        // 开发构建即使被拷进 /Applications 也仍然是开发构建：Debug 判断优先于位置判断。
        XCTAssertEqual(BuildProvenance.suffix(
            isDebugBuild: true,
            bundlePath: "/Applications/Tungsten Edge.app"
        ), "开发版")
    }

    func testReleaseBuildOutsideApplicationsIsMarked() {
        XCTAssertEqual(BuildProvenance.suffix(
            isDebugBuild: false,
            bundlePath: "/Users/caye/Projects/macos-dock-cc-v2/build/ReleaseDD/Build/Products/Release/macos-dock-cc-v2.app"
        ), "非安装位置")
        // 回滚备份包也在 /Applications 之外，同样要能认出来。
        XCTAssertEqual(BuildProvenance.suffix(
            isDebugBuild: false,
            bundlePath: "/Users/caye/Projects/tungsten-edge-rebuild-artifacts/2026-07-25-stage4/rollback/Tungsten Edge.app"
        ), "非安装位置")
    }

    func testInstalledPrefixRequiresTrailingSlashSoLookalikePathsAreNotInstalled() {
        // 少了结尾斜杠就会把这个路径误判成已安装位置。
        XCTAssertEqual(BuildProvenance.suffix(
            isDebugBuild: false,
            bundlePath: "/ApplicationsOld/Tungsten Edge.app"
        ), "非安装位置")
    }

    func testVersionTitleAppendsSuffixWithSeparator() {
        XCTAssertEqual(BuildProvenance.versionTitle(
            version: "0.7.0",
            build: "8",
            isDebugBuild: true,
            bundlePath: "/anywhere/macos-dock-cc-v2.app"
        ), "版本 0.7.0 (8) · 开发版")

        XCTAssertEqual(BuildProvenance.versionTitle(
            version: "0.7.0",
            build: "8",
            isDebugBuild: false,
            bundlePath: "/Applications/Tungsten Edge.app"
        ), "版本 0.7.0 (8)")
    }

    func testVersionTitleDegradesExactlyLikeTheOldImplementation() {
        let installed = "/Applications/Tungsten Edge.app"
        XCTAssertEqual(BuildProvenance.versionTitle(
            version: "0.7.0", build: nil, isDebugBuild: false, bundlePath: installed
        ), "版本 0.7.0")
        XCTAssertEqual(BuildProvenance.versionTitle(
            version: nil, build: "8", isDebugBuild: false, bundlePath: installed
        ), "版本 (8)")
        XCTAssertNil(BuildProvenance.versionTitle(
            version: nil, build: nil, isDebugBuild: false, bundlePath: installed
        ))
    }

    func testSuffixStillAppendsWhenOnlyOneOfVersionOrBuildIsPresent() {
        XCTAssertEqual(BuildProvenance.versionTitle(
            version: "0.7.0", build: nil, isDebugBuild: true, bundlePath: "/tmp/x.app"
        ), "版本 0.7.0 · 开发版")
        // 两者都缺时整行不显示，后缀也不该凭空造出一行。
        XCTAssertNil(BuildProvenance.versionTitle(
            version: nil, build: nil, isDebugBuild: true, bundlePath: "/tmp/x.app"
        ))
    }
}

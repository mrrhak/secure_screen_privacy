import Flutter
import UIKit
import XCTest


@testable import secure_screen_privacy

// This demonstrates a simple unit test of the Swift portion of this plugin's implementation.
//
// See https://developer.apple.com/documentation/xctest for more information about using XCTest.

class RunnerTests: XCTestCase {

  func testGetPlatformVersion() {
    let plugin = SecureScreenPrivacyPlugin()

    let call = FlutterMethodCall(methodName: "getPlatformVersion", arguments: [])

    let resultExpectation = expectation(description: "result block must be called.")
    plugin.handle(call) { result in
      XCTAssertEqual(result as! String, "iOS " + UIDevice.current.systemVersion)
      resultExpectation.fulfill()
    }
    waitForExpectations(timeout: 1)
  }

  // MARK: - App switcher overlay follows the resigning scene

  private var testWindow: UIWindow?

  override func tearDown() {
    testWindow?.isHidden = true
    testWindow = nil
    super.tearDown()
  }

  private func hostScene() throws -> UIWindowScene {
    let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
    return try XCTUnwrap(scene, "test host app has no UIWindowScene")
  }

  // A visible window of our own inside the host scene, so the test doesn't
  // depend on how the host app builds its Flutter window.
  private func makeVisibleWindow(in scene: UIWindowScene) -> UIWindow {
    let window = UIWindow(windowScene: scene)
    window.rootViewController = UIViewController()
    window.isHidden = false
    testWindow = window
    return window
  }

  private func call(_ plugin: SecureScreenPrivacyPlugin, _ method: String, _ args: Any? = nil) {
    plugin.handle(FlutterMethodCall(methodName: method, arguments: args)) { _ in }
  }

  func testSceneWillResignActive_coversThatScenesWindow_andDidBecomeActiveUncoversIt() throws {
    let scene = try hostScene()
    let window = makeVisibleWindow(in: scene)
    let plugin = SecureScreenPrivacyPlugin()
    call(plugin, "enableAppSwitcherProtection", ["mode": "color", "color": 0xFF000000])

    plugin.sceneWillResignActive(scene)

    XCTAssertTrue(plugin.hasOverlay(on: window))
    XCTAssertEqual(window.rootViewController?.view.subviews.count, 1)

    plugin.sceneDidBecomeActive(scene)

    XCTAssertFalse(plugin.hasOverlay(on: window))
    XCTAssertEqual(window.rootViewController?.view.subviews.count, 0)
  }

  func testSceneWillResignActive_firedTwice_addsOnlyOneOverlay() throws {
    let scene = try hostScene()
    let window = makeVisibleWindow(in: scene)
    let plugin = SecureScreenPrivacyPlugin()
    call(plugin, "enableAppSwitcherProtection", ["mode": "color"])

    plugin.sceneWillResignActive(scene)
    plugin.applicationWillResignActive(UIApplication.shared)
    plugin.sceneWillResignActive(scene)

    XCTAssertEqual(window.rootViewController?.view.subviews.count, 1)
    plugin.sceneDidBecomeActive(scene)
  }

  func testSceneWillResignActive_withProtectionOff_addsNoOverlay() throws {
    let scene = try hostScene()
    let window = makeVisibleWindow(in: scene)
    let plugin = SecureScreenPrivacyPlugin()

    plugin.sceneWillResignActive(scene)

    XCTAssertFalse(plugin.hasOverlay(on: window))
  }

  func testDisableAppSwitcherProtection_whileCovered_removesOverlay() throws {
    let scene = try hostScene()
    let window = makeVisibleWindow(in: scene)
    let plugin = SecureScreenPrivacyPlugin()
    call(plugin, "enableAppSwitcherProtection", ["mode": "color"])
    plugin.sceneWillResignActive(scene)

    call(plugin, "disableAppSwitcherProtection")

    XCTAssertFalse(plugin.hasOverlay(on: window))
    XCTAssertEqual(window.rootViewController?.view.subviews.count, 0)
  }

  func testWindowsInScene_returnsThatScenesVisibleWindows() throws {
    let scene = try hostScene()
    let window = makeVisibleWindow(in: scene)

    let windows = SecureScreenPrivacyPlugin.windows(in: scene)

    XCTAssertTrue(windows.contains { $0 === window })
    XCTAssertTrue(windows.allSatisfy { $0.windowScene === scene })
  }
}

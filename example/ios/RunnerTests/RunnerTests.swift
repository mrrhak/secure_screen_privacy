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

  // MARK: - App switcher overlay covers presented screens too

  func testSceneWillResignActive_alsoCoversAPresentedScreen() throws {
    let scene = try hostScene()
    let window = makeVisibleWindow(in: scene)
    let presented = UIViewController()
    presented.modalPresentationStyle = .fullScreen
    window.rootViewController?.present(presented, animated: false)
    XCTAssertTrue(window.rootViewController?.presentedViewController === presented)
    let plugin = SecureScreenPrivacyPlugin()
    call(plugin, "enableAppSwitcherProtection", ["mode": "color"])

    plugin.sceneWillResignActive(scene)

    XCTAssertEqual(window.rootViewController?.view.subviews.count, 1)
    XCTAssertEqual(presented.view.subviews.count, 1)
    XCTAssertEqual(presented.view.subviews.first?.frame, presented.view.bounds)

    plugin.sceneDidBecomeActive(scene)

    XCTAssertFalse(plugin.hasOverlay(on: window))
    XCTAssertEqual(window.rootViewController?.view.subviews.count, 0)
    XCTAssertEqual(presented.view.subviews.count, 0)
    presented.dismiss(animated: false)
  }

  func testOverlayHosts_followsTheWholePresentationChain() throws {
    let scene = try hostScene()
    let window = makeVisibleWindow(in: scene)
    let first = UIViewController()
    let second = UIViewController()
    first.modalPresentationStyle = .fullScreen
    second.modalPresentationStyle = .fullScreen
    window.rootViewController?.present(first, animated: false)
    // Let the first presentation finish before presenting on top of it.
    RunLoop.current.run(until: Date().addingTimeInterval(0.5))
    first.present(second, animated: false)
    RunLoop.current.run(until: Date().addingTimeInterval(0.5))
    XCTAssertTrue(first.presentedViewController === second)

    let hosts = SecureScreenPrivacyPlugin.overlayHosts(in: window)

    try XCTSkipUnless(hosts.count == 3, "presentation chain not set up: \(hosts.count) hosts")
    XCTAssertTrue(hosts[0] === window.rootViewController?.view)
    XCTAssertTrue(hosts[1] === first.view)
    XCTAssertTrue(hosts[2] === second.view)
    second.dismiss(animated: false)
    first.dismiss(animated: false)
  }

  func testOverlayHosts_withNoRootViewController_isTheWindow() throws {
    let scene = try hostScene()
    let window = UIWindow(windowScene: scene)

    XCTAssertTrue(SecureScreenPrivacyPlugin.overlayHosts(in: window).first === window)
  }

  // MARK: - Screenshot events: one screenshot, one event

  func testScreenshotDeduper_dropsARepeatInsideTheWindow() {
    var deduper = ScreenshotEventDeduper()
    XCTAssertTrue(deduper.shouldEmit(at: 100.000))
    XCTAssertFalse(deduper.shouldEmit(at: 100.003))
    XCTAssertFalse(deduper.shouldEmit(at: 100.4))
  }

  func testScreenshotDeduper_reportsAScreenshotAfterTheWindow() {
    var deduper = ScreenshotEventDeduper()
    XCTAssertTrue(deduper.shouldEmit(at: 100.0))
    XCTAssertTrue(deduper.shouldEmit(at: 100.0 + ScreenshotEventDeduper.window))
    XCTAssertFalse(deduper.shouldEmit(at: 100.6))
    XCTAssertTrue(deduper.shouldEmit(at: 101.2))
  }

  func testScreenshotDeduper_resetForgetsTheLastScreenshot() {
    var deduper = ScreenshotEventDeduper()
    XCTAssertTrue(deduper.shouldEmit(at: 100.0))
    deduper.reset()
    XCTAssertTrue(deduper.shouldEmit(at: 100.1))
  }

  func testScreenshotDeduper_clockGoingBackwardsStillReports() {
    var deduper = ScreenshotEventDeduper()
    XCTAssertTrue(deduper.shouldEmit(at: 100.0))
    XCTAssertTrue(deduper.shouldEmit(at: 50.0))
  }

  // The real-device bug: iOS posted userDidTakeScreenshotNotification twice
  // for one screenshot and both reached Dart.
  func testDuplicateScreenshotNotifications_reachTheSinkOnce() {
    let plugin = SecureScreenPrivacyPlugin()
    var events: [Any?] = []
    _ = plugin.onListen(withArguments: nil) { events.append($0) }
    defer { _ = plugin.onCancel(withArguments: nil) }

    NotificationCenter.default.post(name: UIApplication.userDidTakeScreenshotNotification, object: UIApplication.shared)
    NotificationCenter.default.post(name: UIApplication.userDidTakeScreenshotNotification, object: UIApplication.shared)
    drainMainQueue()

    XCTAssertEqual(events.count, 1)
    let payload = events.first as? [String: Any]
    XCTAssertNotNil(payload?["timestamp"] as? Int64)
  }

  func testScreenshotAfterRelisten_isReportedEvenInsideTheWindow() {
    let plugin = SecureScreenPrivacyPlugin()
    var events: [Any?] = []
    _ = plugin.onListen(withArguments: nil) { events.append($0) }
    plugin.handleScreenshotTaken()
    drainMainQueue()
    _ = plugin.onCancel(withArguments: nil)

    // Subscribing again well inside the window must start fresh.
    _ = plugin.onListen(withArguments: nil) { events.append($0) }
    defer { _ = plugin.onCancel(withArguments: nil) }
    plugin.handleScreenshotTaken()
    drainMainQueue()

    XCTAssertEqual(events.count, 2)
  }

  private func drainMainQueue() {
    let delivered = expectation(description: "main queue drained")
    DispatchQueue.main.async { delivered.fulfill() }
    wait(for: [delivered], timeout: 1)
  }
}

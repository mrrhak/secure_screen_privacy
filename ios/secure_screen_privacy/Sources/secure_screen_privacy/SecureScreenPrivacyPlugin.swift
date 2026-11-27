import Flutter
import UIKit

public class SecureScreenPrivacyPlugin: NSObject, FlutterPlugin, FlutterSceneLifeCycleDelegate, FlutterStreamHandler {
  /// Backing text field whose internal secure layer is used to block
  /// screenshots and screen recording of the app's window.
  private var screenPreventField = UITextField()
  private weak var attachedWindow: UIWindow?
  private var isCaptureProtectionEnabled = false

  // App switcher protection state.
  private var appSwitcherMode: String?
  private var appSwitcherBlurIntensity: String = "ultraLight"
  private var appSwitcherColor: UIColor = .black
  private var appSwitcherImageBackgroundColor: UIColor = .black
  private var isAppSwitcherProtectionEnabled = false
  // The overlay views covering each window (one per overlay host, see
  // overlayHosts(in:)), keyed weakly by the window: on iPad multi-window
  // each UIWindowScene resigns/activates independently, so a single shared
  // overlay slot could cover the wrong window or be removed from a window
  // that is still in the App Switcher.
  private let overlays = NSMapTable<UIWindow, NSArray>.weakToStrongObjects()
  private var screenshotEventSink: FlutterEventSink?
  private var screenRecordingEventSink: FlutterEventSink?
  private var isRecordingListening = false
  // Strong reference: FlutterEventChannel.setStreamHandler does not
  // document that it retains the handler, so this plugin holds it
  // explicitly rather than relying on undocumented retention behavior.
  private var screenRecordingStreamHandler: ScreenRecordingStreamHandler?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "secure_screen_privacy", binaryMessenger: registrar.messenger())
    let instance = SecureScreenPrivacyPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
    // Register both delegate styles so re-attachment fires regardless of
    // whether the host app is UIApplicationDelegate-only or UIScene-based
    // (legacy app-delegate lifecycle callbacks stop firing for scene-based
    // apps on newer iOS versions).
    registrar.addApplicationDelegate(instance)
    registrar.addSceneDelegate(instance)

    let screenshotEventChannel = FlutterEventChannel(
      name: "secure_screen_privacy/screenshot_events", binaryMessenger: registrar.messenger())
    screenshotEventChannel.setStreamHandler(instance)

    // A dedicated handler object, not `instance` itself: a single
    // FlutterStreamHandler registered against two different channels can't
    // tell which channel's onListen/onCancel it's being called for, since
    // `arguments` is only the Dart-side listen() payload, never the channel
    // name - sharing one would incorrectly arm this channel's native side
    // effects whenever the OTHER channel is subscribed to, and vice versa.
    let screenRecordingEventChannel = FlutterEventChannel(
      name: "secure_screen_privacy/screen_recording_events", binaryMessenger: registrar.messenger())
    let recordingHandler = ScreenRecordingStreamHandler(plugin: instance)
    instance.screenRecordingStreamHandler = recordingHandler
    screenRecordingEventChannel.setStreamHandler(recordingHandler)
  }

  // MARK: - Screenshot detection
  //
  // Subscribing to the Dart stream (onListen) starts observing
  // UIApplication.userDidTakeScreenshotNotification; cancelling (onCancel)
  // stops it. There is no separate start/stop method - the subscription is
  // the toggle. This notification is UIApplication-level (posted once per
  // screenshot regardless of how many UIScenes exist), unlike
  // applicationWillResignActive/sceneWillResignActive above, so it needs no
  // scene-specific dual-hook.

  public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    screenshotEventSink = events
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleScreenshotTaken),
      name: UIApplication.userDidTakeScreenshotNotification,
      object: nil
    )
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    NotificationCenter.default.removeObserver(self, name: UIApplication.userDidTakeScreenshotNotification, object: nil)
    screenshotEventSink = nil
    return nil
  }

  // Apple's documentation does not explicitly guarantee
  // userDidTakeScreenshotNotification is posted on the main thread. It's
  // commonly observed to be main-thread in practice, but FlutterEventSink
  // must only be invoked on the platform (main) thread, so the dispatch
  // below is a cheap, unconditional safety net rather than an assumption.
  @objc private func handleScreenshotTaken() {
    let millis = Int64(Date().timeIntervalSince1970 * 1000)
    DispatchQueue.main.async { [weak self] in
      self?.screenshotEventSink?(["timestamp": millis])
    }
  }

  // MARK: - Screen recording detection
  //
  // Subscribing to the Dart stream (onListen, forwarded via
  // ScreenRecordingStreamHandler below) starts observing
  // UIScreen.capturedDidChangeNotification; cancelling (onCancel) stops it -
  // same subscribe-is-the-toggle model as screenshot detection above.
  // Because `.isCaptured` is a live boolean re-read on every notification
  // firing (not a directional start/stop event), one observer naturally
  // reports both start and stop transitions correctly - unlike Android 14,
  // there's no "stuck true" problem here.

  private var isScreenCaptured: Bool {
    if let scene = activeWindow()?.windowScene {
      return scene.screen.isCaptured
    }
    // activeWindow() can return nil very early (e.g. onListen fires before
    // any UIWindowScene has become foregroundActive) - fall back to any
    // connected scene rather than defaulting to "not recording", since a
    // false negative here would silently drop a genuinely active recording.
    if let anyScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
      return anyScene.screen.isCaptured
    }
    return false
  }

  fileprivate func handleRecordingListen(_ events: @escaping FlutterEventSink) {
    screenRecordingEventSink = events
    isRecordingListening = true
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleScreenCapturedChange),
      name: UIScreen.capturedDidChangeNotification,
      object: nil
    )
    // Emitted immediately so a late subscriber sees an already-in-progress
    // recording rather than waiting for the next transition.
    emitScreenRecordingEvent(isScreenCaptured)
  }

  fileprivate func handleRecordingCancel() {
    NotificationCenter.default.removeObserver(self, name: UIScreen.capturedDidChangeNotification, object: nil)
    isRecordingListening = false
    screenRecordingEventSink = nil
  }

  @objc private func handleScreenCapturedChange() {
    emitScreenRecordingEvent(isScreenCaptured)
  }

  // Apple doesn't document capturedDidChangeNotification as guaranteed
  // main-thread, same reasoning as handleScreenshotTaken's dispatch above.
  private func emitScreenRecordingEvent(_ isRecording: Bool) {
    let millis = Int64(Date().timeIntervalSince1970 * 1000)
    DispatchQueue.main.async { [weak self] in
      self?.screenRecordingEventSink?(["isRecording": isRecording, "timestamp": millis])
    }
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getPlatformVersion":
      result("iOS " + UIDevice.current.systemVersion)
    case "enableCaptureProtection":
      result(setCaptureProtection(true))
    case "disableCaptureProtection":
      result(setCaptureProtection(false))
    case "isCaptureProtectionEnabled":
      result(isCaptureProtectionEnabled)
    case "enableAppSwitcherProtection":
      result(setAppSwitcherProtection(from: call.arguments as? [String: Any]))
    case "disableAppSwitcherProtection":
      result(clearAppSwitcherProtection())
    case "isAppSwitcherProtectionEnabled":
      result(isAppSwitcherProtectionEnabled)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Secure layer technique
  //
  // Reparents the app's UIWindow.layer as a sublayer of a UITextField's
  // internal secure layer. Toggling isSecureTextEntry then makes the OS treat
  // the whole window as secure content, blocking both screenshots and screen
  // recording capture of it.

  private func activeWindow() -> UIWindow? {
    if let windowScene = UIApplication.shared.connectedScenes
      .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene {
      if #available(iOS 15.0, *) {
        return windowScene.keyWindow
      } else {
        return windowScene.windows.first(where: { $0.isKeyWindow })
      }
    }
    return nil
  }

  private func configurePrevention(window: UIWindow) {
    guard let rootLayer = window.layer.superlayer else { return }
    guard screenPreventField.layer.superlayer == nil else { return }

    screenPreventField.semanticContentAttribute = .forceLeftToRight
    screenPreventField.textAlignment = .left

    // Briefly attach to build the internal sublayer hierarchy, then detach
    // immediately to avoid a circular view hierarchy (EXC_BAD_ACCESS on
    // iOS 26+ if left attached).
    window.addSubview(screenPreventField)
    screenPreventField.layoutIfNeeded()
    screenPreventField.removeFromSuperview()

    screenPreventField.layer.frame = .zero
    rootLayer.addSublayer(screenPreventField.layer)
    if #available(iOS 17.0, *) {
      screenPreventField.layer.sublayers?.last?.addSublayer(window.layer)
    } else {
      screenPreventField.layer.sublayers?.first?.addSublayer(window.layer)
    }
  }

  private func attachWindowIfNeeded() {
    guard let window = activeWindow(), window !== attachedWindow else { return }

    // Undo previous reparenting if the active window/scene changed.
    if let oldWindow = attachedWindow, let rootLayer = screenPreventField.layer.superlayer {
      rootLayer.addSublayer(oldWindow.layer)
      screenPreventField.layer.removeFromSuperlayer()
    }

    screenPreventField = UITextField() // fresh field avoids stale layer state
    configurePrevention(window: window)
    attachedWindow = window
  }

  // The requested state is always recorded, even when no window can be
  // attached yet (e.g. a call made during cold launch, before any scene is
  // foregroundActive): handleDidBecomeActive() attaches the window and
  // applies it once the app becomes active. Dropping the request instead
  // would leave the screen unprotected with no later retry.
  @discardableResult
  private func setCaptureProtection(_ enabled: Bool) -> Bool {
    isCaptureProtectionEnabled = enabled
    attachWindowIfNeeded()
    if attachedWindow != nil {
      screenPreventField.isSecureTextEntry = enabled
    }
    return true
  }

  // MARK: - App switcher protection
  //
  // Shows a blur/image/color overlay over the window while the app is
  // resigning active, so the interactive App Switcher snapshot (captured at
  // that moment, per Apple's guidance on preventing sensitive content in the
  // task switcher - `didEnterBackground` fires too late for this) shows the
  // overlay instead of live content. If capture protection is on, the secure
  // text field trick would otherwise force a blank snapshot regardless of
  // the overlay's content, so showOverlay() disables it - but only once
  // the overlay is actually attached, immediately for every mode (all four
  // attach synchronously), so there's no gap where the field is off and
  // nothing has replaced it yet. It's restored by
  // clearAppSwitcherProtection() and handleDidBecomeActive().
  //
  // Note this hook also fires on transient interruptions (incoming call,
  // Siri, Control Center, share sheet) - the overlay will briefly flash in
  // those cases too, which is inherent to the technique.

  private func setAppSwitcherProtection(from arguments: [String: Any]?) -> Bool {
    guard let mode = arguments?["mode"] as? String else { return false }
    if (mode == "image" || mode == "imageBlur"), UIImage(named: "SecureScreenPrivacyImage") == nil { return false }

    appSwitcherMode = mode
    if let intensity = arguments?["blurIntensity"] as? String {
      appSwitcherBlurIntensity = intensity
    }
    if let colorValue = arguments?["color"] as? NSNumber {
      appSwitcherColor = SecureScreenPrivacyPlugin.color(fromARGB: colorValue)
    }
    if let imageBackgroundColorValue = arguments?["imageBackgroundColor"] as? NSNumber {
      appSwitcherImageBackgroundColor = SecureScreenPrivacyPlugin.color(fromARGB: imageBackgroundColorValue)
    }
    isAppSwitcherProtectionEnabled = true
    return true
  }

  @discardableResult
  private func clearAppSwitcherProtection() -> Bool {
    isAppSwitcherProtectionEnabled = false
    appSwitcherMode = nil
    removeAllOverlays()
    // Restores what showOverlay() turned off, in case this is called
    // while the overlay is already attached (e.g. app switcher protection
    // explicitly disabled while backgrounded) - without this, capture
    // protection would report enabled but the underlying secure field
    // would stay off until the next foreground transition.
    if isCaptureProtectionEnabled {
      screenPreventField.isSecureTextEntry = true
    }
    return true
  }

  // Covers every overlay host in the window (see overlayHosts(in:)) with
  // its own overlay view, all attached synchronously in this one call.
  private func showOverlay(mode: String, in window: UIWindow) {
    var views: [UIView] = []
    for host in SecureScreenPrivacyPlugin.overlayHosts(in: window) {
      guard let view = makeOverlayView(mode: mode) else { continue }
      view.frame = host.bounds
      view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      host.addSubview(view)
      views.append(view)
    }
    guard !views.isEmpty else { return }
    overlays.setObject(views as NSArray, forKey: window)
    // Only safe to disable here: this is the one point the overlay is
    // guaranteed to already be covering the window, for every mode -
    // disabling it any earlier (e.g. in handleWillResignActive) would leave
    // a window where the secure field is off but nothing has replaced it
    // yet. Only for the window the secure field actually protects: on iPad
    // multi-window, covering some other scene's window must not switch off
    // capture protection for a window that may still be live.
    if isCaptureProtectionEnabled, window === attachedWindow {
      screenPreventField.isSecureTextEntry = false
    }
  }

  // The views to put an overlay on: the root view controller's view plus the
  // view of every view controller presented on top of it (share sheet,
  // image picker, alert, a full-screen or sheet modal...). Covering only the
  // root view left any presented screen above the overlay, so its live
  // content showed in the App Switcher. A sheet that doesn't fill the window
  // gets its own overlay sized to it, and the root's overlay covers the rest.
  //
  // Root view controller's view rather than the window itself: under test,
  // a blur/imageBlur overlay attached straight to the window never showed
  // any real backdrop content in the App Switcher snapshot regardless of
  // blurIntensity/style, suggesting that snapshot mechanism walks from
  // rootViewController.view as "the app's content" rather than arbitrary
  // window subviews.
  static func overlayHosts(in window: UIWindow) -> [UIView] {
    var hosts: [UIView] = []
    var controller = window.rootViewController
    if let rootView = controller?.viewIfLoaded { hosts.append(rootView) }
    while let presented = controller?.presentedViewController {
      if let view = presented.viewIfLoaded { hosts.append(view) }
      controller = presented
    }
    return hosts.isEmpty ? [window] : hosts
  }

  private func makeOverlayView(mode: String) -> UIView? {
    switch mode {
    case "blur":
      return UIVisualEffectView(
        effect: UIBlurEffect(style: SecureScreenPrivacyPlugin.blurStyle(forIntensity: appSwitcherBlurIntensity)))
    case "image":
      guard let image = UIImage(named: "SecureScreenPrivacyImage") else { return nil }
      let imageView = UIImageView(image: image)
      // .scaleAspectFit (not .scaleAspectFill) so the whole image is visible
      // rather than cropped when its aspect ratio doesn't match the window's -
      // a square placeholder image, for instance, would otherwise have most
      // of its height cropped off on a tall phone screen. The opaque
      // background covers the resulting letterbox/pillarbox bars so they
      // don't reveal live content underneath.
      imageView.contentMode = .scaleAspectFit
      imageView.clipsToBounds = true
      imageView.backgroundColor = appSwitcherImageBackgroundColor
      return imageView
    case "imageBlur":
      // Same sharp image as "image" mode, over a live UIVisualEffectView
      // blur of whatever's behind the window. Both the blur and the sharp
      // image attach in one synchronous step, so there's never a frame
      // where one is visible without the other.
      guard let image = UIImage(named: "SecureScreenPrivacyImage") else { return nil }
      let container = UIView()

      let blurView = UIVisualEffectView(
        effect: UIBlurEffect(style: SecureScreenPrivacyPlugin.blurStyle(forIntensity: appSwitcherBlurIntensity)))
      blurView.frame = container.bounds
      blurView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      container.addSubview(blurView)

      let imageView = UIImageView(image: image)
      imageView.frame = container.bounds
      imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      imageView.contentMode = .scaleAspectFit
      imageView.clipsToBounds = true
      imageView.backgroundColor = .clear
      container.addSubview(imageView)
      return container
    case "color":
      let colorView = UIView()
      colorView.backgroundColor = appSwitcherColor
      return colorView
    default:
      return nil
    }
  }

  private func removeOverlay(from window: UIWindow) {
    (overlays.object(forKey: window) as? [UIView])?.forEach { $0.removeFromSuperview() }
    overlays.removeObject(forKey: window)
  }

  private func removeAllOverlays() {
    for case let views as [UIView] in overlays.objectEnumerator()?.allObjects ?? [] {
      views.forEach { $0.removeFromSuperview() }
    }
    overlays.removeAllObjects()
  }

  // The window(s) to cover for a resigning/activating UIScene, taken from
  // that scene itself rather than from activeWindow(): by the time
  // sceneWillResignActive runs, the scene may already have left
  // .foregroundActive, so activeWindow() can return nil (no overlay at all,
  // live content in the App Switcher) or, on iPad multi-window, another
  // still-active scene's window (wrong window covered).
  static func windows(in scene: UIScene) -> [UIWindow] {
    guard let windowScene = scene as? UIWindowScene else { return [] }
    let windows = windowScene.windows.filter { !$0.isHidden }
    return windows.isEmpty ? windowScene.windows : windows
  }

  // App-delegate path (apps without a UIScene lifecycle): the app delegate's
  // own window, falling back to the key window of any foreground scene -
  // again without requiring .foregroundActive, for the same reason as above.
  private func appDelegateWindow(_ application: UIApplication) -> UIWindow? {
    if let window = application.delegate?.window ?? nil { return window }
    let scenes = application.connectedScenes.compactMap { $0 as? UIWindowScene }
      .filter { $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive }
    for scene in scenes {
      if let key = scene.windows.first(where: { $0.isKeyWindow }) { return key }
    }
    return scenes.first?.windows.first
  }

  // Four explicit, developer-chosen tiers - not a continuous value bucketed
  // into styles, so .systemThickMaterial (Apple's most opaque/legible
  // translucent material) is a legitimate top tier a developer opts into
  // here, rather than an ambiguous point on an auto-scaled continuum that
  // could look no more blurred than the step before it. Falls back to the
  // lightest tier (matching the Dart-side default) for any unrecognized
  // name, e.g. a version skew between an older native build and a newer
  // Dart client that added a fifth tier.
  private static func blurStyle(forIntensity intensity: String) -> UIBlurEffect.Style {
    switch intensity {
    case "ultraLight": return .systemUltraThinMaterial
    case "light": return .systemThinMaterial
    case "medium": return .systemMaterial
    case "heavy": return .systemThickMaterial
    default: return .systemUltraThinMaterial
    }
  }

  private static func color(fromARGB value: NSNumber) -> UIColor {
    let bits = UInt32(truncatingIfNeeded: value.int64Value)
    let alpha = CGFloat((bits >> 24) & 0xFF) / 255.0
    let red = CGFloat((bits >> 16) & 0xFF) / 255.0
    let green = CGFloat((bits >> 8) & 0xFF) / 255.0
    let blue = CGFloat(bits & 0xFF) / 255.0
    return UIColor(red: red, green: green, blue: blue, alpha: alpha)
  }

  // MARK: - App lifecycle
  //
  // Scene-based apps get sceneWillResignActive/sceneDidBecomeActive per
  // UIScene; apps without a scene lifecycle get the app-delegate variants.
  // Both resolve the window(s) to act on from the callback's own scene or
  // application, never from whichever scene is foregroundActive right now.
  private func handleWillResignActive(windows: [UIWindow]) {
    guard isAppSwitcherProtectionEnabled, let mode = appSwitcherMode else { return }
    // Both the app-delegate and scene-delegate variants can fire for the
    // same transition - skip a window that is already covered.
    for window in windows where overlays.object(forKey: window) == nil {
      // showOverlay attaches synchronously for every mode, so by the time
      // this call returns (the point at which the OS can capture the App
      // Switcher snapshot) the overlay is already covering the window.
      showOverlay(mode: mode, in: window)
    }
  }

  private func handleDidBecomeActive(windows: [UIWindow]?) {
    if let windows = windows {
      windows.forEach { removeOverlay(from: $0) }
    } else {
      removeAllOverlays()
    }
    guard isCaptureProtectionEnabled else { return }
    attachWindowIfNeeded()
    // Leave the secure field off while the protected window is still
    // covered (another scene became active, not this one): showOverlay()
    // turned it off so the overlay, not a blank frame, is what's captured.
    if let attached = attachedWindow, overlays.object(forKey: attached) != nil { return }
    screenPreventField.isSecureTextEntry = true
  }

  public func applicationWillResignActive(_ application: UIApplication) {
    handleWillResignActive(windows: appDelegateWindow(application).map { [$0] } ?? [])
  }

  public func sceneWillResignActive(_ scene: UIScene) {
    handleWillResignActive(windows: SecureScreenPrivacyPlugin.windows(in: scene))
  }

  public func applicationDidBecomeActive(_ application: UIApplication) {
    // The whole app is active again - nothing should stay covered.
    handleDidBecomeActive(windows: nil)
  }

  public func sceneDidBecomeActive(_ scene: UIScene) {
    handleDidBecomeActive(windows: SecureScreenPrivacyPlugin.windows(in: scene))
  }

  // Test-only view of which windows currently carry an overlay.
  func hasOverlay(on window: UIWindow) -> Bool {
    overlays.object(forKey: window) != nil
  }
}

// Dedicated FlutterStreamHandler for the screen-recording EventChannel
private final class ScreenRecordingStreamHandler: NSObject, FlutterStreamHandler {
  weak var plugin: SecureScreenPrivacyPlugin?

  init(plugin: SecureScreenPrivacyPlugin) {
    self.plugin = plugin
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    plugin?.handleRecordingListen(events)
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    plugin?.handleRecordingCancel()
    return nil
  }
}

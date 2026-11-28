import Flutter
import UIKit

public class SecureScreenPrivacyPlugin: NSObject, FlutterPlugin, FlutterSceneLifeCycleDelegate, FlutterStreamHandler {
  /// Backing text field whose internal secure layer is used to block
  /// screenshots and screen recording of the app's window.
  private var screenPreventField = UITextField()
  private weak var attachedWindow: UIWindow?
  // The window showing this plugin's own Flutter view. On iPad multi-window
  // each window runs its own engine with its own plugin instance, so
  // capture protection must follow this window, not whichever scene happens
  // to be active (that can be another window of the same app). A property so
  // tests can stand in for the registrar. nil falls back to activeWindow().
  var ownWindowProvider: () -> UIWindow? = { nil }
  private var isCaptureProtectionEnabled = false

  // App switcher protection state.
  private var appSwitcherMode: String?
  // Where image/imageBlur modes get their picture. A property (not a direct
  // UIImage(named:) call) so tests can simulate a host app without the asset.
  var appSwitcherImageProvider: () -> UIImage? = { UIImage(named: "SecureScreenPrivacyImage") }
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
  // Collapses the duplicate screenshot notifications iOS posts for a single
  // screenshot (see handleScreenshotTaken()).
  var screenshotDeduper = ScreenshotEventDeduper()
  // Whether the app is on screen right now (see isAppOnScreen()); a
  // variable so tests can simulate a backgrounded app.
  var appOnScreenProvider: () -> Bool = { SecureScreenPrivacyPlugin.isAppOnScreen() }
  private var screenRecordingEventSink: FlutterEventSink?
  private var isRecordingListening = false
  // Drops a recording state equal to the last one sent (see
  // emitScreenRecordingEvent).
  var screenRecordingStateDeduper = ScreenRecordingStateDeduper()
  // Strong reference: FlutterEventChannel.setStreamHandler does not
  // document that it retains the handler, so this plugin holds it
  // explicitly rather than relying on undocumented retention behavior.
  private var screenRecordingStreamHandler: ScreenRecordingStreamHandler?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "secure_screen_privacy", binaryMessenger: registrar.messenger())
    let instance = SecureScreenPrivacyPlugin()
    instance.ownWindowProvider = { [weak registrar] in registrar?.viewController?.view.window }
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
  // scene-specific dual-hook. It can still arrive more than once for a
  // single screenshot, though - see handleScreenshotTaken().

  public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    screenshotEventSink = events
    screenshotDeduper.reset()
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
  //
  // One screenshot can post the notification twice: on an iPhone 17 Pro
  // (iOS 27.2.1) a single screenshot posted it twice, 3 ms apart, to the
  // one observer this plugin registers - so every screenshot was reported
  // twice. The deduper drops any repeat that arrives within its window of
  // the last reported screenshot.
  //
  // iOS tells every running app about a screenshot, also an app that keeps
  // running in the background (audio, location, ...), so a screenshot of
  // another app would be reported. Like Android 14+'s ScreenCaptureCallback,
  // only a screenshot taken while this app is on screen is reported.
  @objc func handleScreenshotTaken() {
    guard appOnScreenProvider() else { return }
    guard screenshotDeduper.shouldEmit(at: ProcessInfo.processInfo.systemUptime) else { return }
    let millis = Int64(Date().timeIntervalSince1970 * 1000)
    DispatchQueue.main.async { [weak self] in
      self?.screenshotEventSink?(["timestamp": millis])
    }
  }

  // On screen = at least one app window scene is in the foreground, active
  // or inactive: an inactive scene is still visible (Control Center or a
  // system alert over it, or the other app focused in iPad Split View), so
  // it is in the screenshot. Without any app window scene, the app-wide
  // state decides.
  static func isAppOnScreen() -> Bool {
    let appScenes = UIApplication.shared.connectedScenes
      .filter { $0.session.role == .windowApplication }
    if appScenes.isEmpty {
      return UIApplication.shared.applicationState != .background
    }
    return appScenes.contains {
      $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive
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
    recordingCheckScene()?.screen.isCaptured ?? false
  }

  // The scene whose screen says whether this app is being recorded or
  // mirrored: the scene of this engine's own window first, like capture
  // protection (protectionTargetWindow()). Before, it was the active scene's
  // key window, which on iPad multi-window can be another window of the app,
  // on another screen with Stage Manager and an external display, and is
  // nil while the app is inactive (e.g. Control Center open to start a
  // recording); the fallback then took any connected scene, which could be
  // an external-display scene instead of an app window. Without an own
  // window: the active window's scene, then an app-window scene (active,
  // then inactive, then any), then any scene. A false negative would drop a
  // real recording, so a scene is always picked when one exists.
  func recordingCheckScene() -> UIWindowScene? {
    if let scene = ownWindowProvider()?.windowScene { return scene }
    if let scene = activeWindow()?.windowScene { return scene }
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let appScenes = scenes.filter { $0.session.role == .windowApplication }
    return appScenes.first(where: { $0.activationState == .foregroundActive })
      ?? appScenes.first(where: { $0.activationState == .foregroundInactive })
      ?? appScenes.first
      ?? scenes.first
  }

  func handleRecordingListen(_ events: @escaping FlutterEventSink) {
    screenRecordingEventSink = events
    isRecordingListening = true
    // A new subscriber always gets the current state first.
    screenRecordingStateDeduper.reset()
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

  func handleRecordingCancel() {
    NotificationCenter.default.removeObserver(self, name: UIScreen.capturedDidChangeNotification, object: nil)
    isRecordingListening = false
    screenRecordingEventSink = nil
  }

  @objc private func handleScreenCapturedChange() {
    emitScreenRecordingEvent(isScreenCaptured)
  }

  // Apple doesn't document capturedDidChangeNotification as guaranteed
  // main-thread, same reasoning as handleScreenshotTaken's dispatch above.
  //
  // Only a change of state is sent: subscribing reports the current state,
  // and capturedDidChangeNotification is not promised to post only when
  // isCaptured changes, so the same state could reach Dart twice in a row.
  // Checked on the main queue, where the deduper is reset, so it is never
  // touched from two threads.
  private func emitScreenRecordingEvent(_ isRecording: Bool) {
    let millis = Int64(Date().timeIntervalSince1970 * 1000)
    DispatchQueue.main.async { [weak self] in
      guard let self = self, self.screenRecordingStateDeduper.shouldEmit(isRecording) else { return }
      self.screenRecordingEventSink?(["isRecording": isRecording, "timestamp": millis])
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

  // This engine's own window first; the active scene's key window only when
  // the own window isn't known yet (no view controller, or its view isn't in
  // a window yet). Re-run on every enable and become-active, so a fallback
  // pick moves to the own window as soon as that window exists.
  private func protectionTargetWindow() -> UIWindow? {
    ownWindowProvider() ?? activeWindow()
  }

  private func attachWindowIfNeeded() {
    guard let window = protectionTargetWindow(), window !== attachedWindow else { return }

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
  //
  // Only enabling moves the window under the secure field. Disabling used to
  // do it too, so every app using SecureScreenPrivacyNavigatorObserver had
  // its window moved at startup (the first route disables protection) even
  // if no route ever turned it on.
  @discardableResult
  private func setCaptureProtection(_ enabled: Bool) -> Bool {
    isCaptureProtectionEnabled = enabled
    if enabled {
      attachWindowIfNeeded()
    }
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
    // A missing SecureScreenPrivacyImage asset no longer refuses the call:
    // returning false left the App Switcher showing live content, and the
    // route observer (which ignores the result) never noticed. The overlay
    // falls back instead (see makeOverlayView), so the screen stays hidden.
    if (mode == "image" || mode == "imageBlur"), appSwitcherImageProvider() == nil {
      NSLog(
        "secure_screen_privacy: no \"SecureScreenPrivacyImage\" in the app's asset catalog; "
          + "\(mode) mode falls back to \(mode == "image" ? "imageBackgroundColor" : "blur") in the App Switcher.")
    }

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
      // No image asset: a plain imageBackgroundColor cover, so the screen
      // is still hidden.
      guard let image = appSwitcherImageProvider() else {
        let colorView = UIView()
        colorView.backgroundColor = appSwitcherImageBackgroundColor
        return colorView
      }
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
      // where one is visible without the other. No image asset: just the
      // blur, so the screen is still hidden.
      guard let image = appSwitcherImageProvider() else {
        return UIVisualEffectView(
          effect: UIBlurEffect(style: SecureScreenPrivacyPlugin.blurStyle(forIntensity: appSwitcherBlurIntensity)))
      }
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

  // The snapshot iOS saves when the app enters the background (shown in the
  // App Switcher afterwards) treats the secure layer like any other capture,
  // so with capture protection on and app switcher protection off it came out
  // all black. The live App Switcher (opened straight from the app) was fine.
  // So the secure field is switched off once the window is in the background,
  // where nothing of it is on screen to capture, and back on before it
  // returns. With app switcher protection on, the overlay already handles the
  // snapshot (see showOverlay()), and the field stays as it is.
  // `scene` is nil for the app-delegate variants (the whole app).
  private func handleDidEnterBackground(scene: UIScene?) {
    guard isCaptureProtectionEnabled, !isAppSwitcherProtectionEnabled,
      let attached = attachedWindow
    else { return }
    if let scene = scene, attached.windowScene !== scene { return }
    screenPreventField.isSecureTextEntry = false
  }

  private func handleWillEnterForeground(scene: UIScene?) {
    guard isCaptureProtectionEnabled, let attached = attachedWindow else { return }
    if let scene = scene, attached.windowScene !== scene { return }
    // Still covered by the app switcher overlay: showOverlay() keeps the
    // field off until handleDidBecomeActive() removes the overlay.
    if overlays.object(forKey: attached) != nil { return }
    screenPreventField.isSecureTextEntry = true
  }

  public func applicationDidEnterBackground(_ application: UIApplication) {
    handleDidEnterBackground(scene: nil)
  }

  public func sceneDidEnterBackground(_ scene: UIScene) {
    handleDidEnterBackground(scene: scene)
  }

  public func applicationWillEnterForeground(_ application: UIApplication) {
    handleWillEnterForeground(scene: nil)
  }

  public func sceneWillEnterForeground(_ scene: UIScene) {
    handleWillEnterForeground(scene: scene)
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
  var isWindowAttachedToSecureField: Bool {
    attachedWindow != nil
  }

  func isProtecting(_ window: UIWindow) -> Bool {
    window === attachedWindow && screenPreventField.isSecureTextEntry
  }

  func hasOverlay(on window: UIWindow) -> Bool {
    overlays.object(forKey: window) != nil
  }
}

// Decides whether a screenshot notification is a new screenshot or a repeat
// of the one just reported. Times are monotonic seconds (systemUptime), so a
// wall-clock change can't swallow or duplicate an event. The window is
// measured from the last *reported* screenshot and is far shorter than two
// real screenshots can be taken apart, yet far longer than the few
// milliseconds between duplicate notifications.
struct ScreenshotEventDeduper {
  static let window: TimeInterval = 0.5
  private var lastEmittedAt: TimeInterval?

  mutating func shouldEmit(at now: TimeInterval) -> Bool {
    if let last = lastEmittedAt, now - last >= 0, now - last < ScreenshotEventDeduper.window {
      return false
    }
    lastEmittedAt = now
    return true
  }

  mutating func reset() {
    lastEmittedAt = nil
  }
}

// Lets a screen recording state through only when it differs from the last
// one sent. Only touched from the main queue.
struct ScreenRecordingStateDeduper {
  private var lastState: Bool?

  mutating func shouldEmit(_ state: Bool) -> Bool {
    if lastState == state { return false }
    lastState = state
    return true
  }

  mutating func reset() {
    lastState = nil
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

# Changelog

## 1.0.0

First release. One API for screen privacy on Android and iOS.

### Features

- **Block screenshots and screen recording:** `enableCaptureProtection`,
  `disableCaptureProtection` and `isCaptureProtectionEnabled`. Screenshots and
  recordings of the app come out blank.
- **Hide the app in the App Switcher:** `enableAppSwitcherProtection`,
  `disableAppSwitcherProtection` and `isAppSwitcherProtectionEnabled`, with
  four `AppSwitcherProtectionMode`s: `blur`, `color`, `image` and `imageBlur`.
  Options: `blurIntensity` (`ultraLight`, `light`, `medium`, `heavy`), `color`
  and `imageBackgroundColor`.
- **Protect only some screens:** `SecureScreenPrivacyNavigatorObserver` and
  `SecureRouteConfig` turn protection on and off per route, with a
  `defaultConfig` for the rest. Dialogs and bottom sheets can be protected by
  route name. Works with nested navigators, go_router and auto_route.
- **Screenshot events:** `screenshotEvents` reports each screenshot of your
  app with its time. Listening starts detection, cancelling stops it.
- **Screen recording events:** `screenRecordingEvents` reports when recording
  or mirroring starts and stops (`recording`, `notRecording`, `unknown`). It
  sends the current state first, then each change.
- **No permission prompts:** no storage, photos or media permission is ever
  requested. `DETECT_SCREEN_CAPTURE` and `DETECT_SCREEN_RECORDING` are granted
  at install time.
- Protection asked for before the screen is ready (at app start, or with no
  Android Activity yet) is kept and applied as soon as it is.

### Platform support

- **iOS:** every App Switcher mode is drawn as shown (a blur, a solid color,
  your `SecureScreenPrivacyImage` asset on a color, or the image over a blur),
  over every screen showing, including sheets, pickers and alerts. Without the
  image asset the image modes still cover the screen. On iPad multi-window
  each window protects itself. Mirroring (AirPlay) counts as recording.
- **Android:** every App Switcher mode uses `FLAG_SECURE` and shows a plain
  card, with no blur or image. On Android 13+ the card uses `color` (color
  mode), `imageBackgroundColor` (image mode) or the theme's background color,
  and follows dark and light mode. App Switcher protection also blanks
  screenshots and recordings while it is on.
- **Android version differences:** Android 14+ reports each screenshot once
  through the system callback; older versions watch new screenshots while the
  app is on screen. Recording events need Android 15+; older versions send
  `unknown`.
- Web, Windows, macOS and Linux are not supported: calls throw
  `PlatformException` with code `channel-error`.

### Requirements

- Flutter 3.38 or newer (Dart 3.10).
- Android 7.0 (API 24) or newer.
- iOS 15.0 or newer, with Swift Package Manager or CocoaPods. Includes a
  privacy manifest.

### Under the hood

- Platform calls and events use [Pigeon](https://pub.dev/packages/pigeon)
  generated code (Dart, Kotlin, Swift), as in Flutter's plugin template.

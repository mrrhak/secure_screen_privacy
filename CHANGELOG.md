# Changelog

## 0.1.0

Moves the plugin onto [Pigeon](https://pub.dev/packages/pigeon), as in the
Flutter 3.50.1 plugin template. Protection, detection and the public
`SecureScreenPrivacy` API work as before. See "Migrating to 0.1.0" in the
README.

### Breaking changes

- iOS 15.0 or newer is required (was iOS 13.0).
- `MethodChannelSecureScreenPrivacy` (`secure_screen_privacy_method_channel.dart`)
  is replaced by `PigeonSecureScreenPrivacy` (`secure_screen_privacy_pigeon.dart`).
  Its `methodChannel`, `screenshotEventChannel` and
  `screenRecordingEventChannel` fields are gone; it takes an optional `api`
  for tests instead.
- The platform channels have new names, so mocks of
  `MethodChannel('secure_screen_privacy')` and its event channels no longer
  take effect. Set `SecureScreenPrivacyPlatform.instance` to a fake instead.
- On unsupported platforms, methods throw `PlatformException` with code
  `channel-error` instead of `MissingPluginException`.

### Other changes

- The Dart, Kotlin and Swift code for the platform calls is generated from
  `pigeon/messages.dart`, with typed App Switcher options and events. CI
  checks the generated files are up to date.
- Android: Android Gradle plugin 9.3.1 and Kotlin 2.4.20 for the plugin build.

## 0.0.1

First release.

### Screenshot and recording blocking

- `enableCaptureProtection`, `disableCaptureProtection` and
  `isCaptureProtectionEnabled` block screenshots and screen recording of the
  app.
- Protection asked for before the screen is ready (at app start, or with no
  Android Activity yet) is kept and applied as soon as it is.
- On iPad multi-window each window protects itself.

### App Switcher privacy

- `enableAppSwitcherProtection`, `disableAppSwitcherProtection` and
  `isAppSwitcherProtectionEnabled` hide the app in the App Switcher.
- `AppSwitcherProtectionMode`: `blur`, `color`, `image` and `imageBlur`, with
  `BlurIntensity` (`ultraLight`, `light`, `medium`, `heavy`), `color` and
  `imageBackgroundColor`.
- iOS covers every screen showing, including share sheets, pickers, alerts
  and modals, on the window that is leaving.
- iOS image modes without the `SecureScreenPrivacyImage` asset still cover
  the screen, with the background color or the blur.
- Android shows a plain card. On Android 13 and newer its color follows the
  mode and changes right away with dark and light mode.

### Per-route protection

- `SecureScreenPrivacyNavigatorObserver` and `SecureRouteConfig` turn
  protection on and off per route, with a `defaultConfig` for the rest.
- Dialogs and bottom sheets can be protected by route name. Menus and
  dropdowns never change protection.
- Works with nested navigators, `pushAndRemoveUntil`, `removeRoute`,
  `replace`, go_router and auto_route. Pages added below the one showing
  don't change protection until they're on top.

### Screenshot and recording events

- `screenshotEvents` reports each screenshot with its time. Listening starts
  detection and cancelling stops it.
- `screenRecordingEvents` reports when recording or mirroring starts and
  stops, with `ScreenRecordingState` (`recording`, `notRecording`,
  `unknown`). It sends the current state first, then only changes.
- Android 14 and newer use the system screenshot callback, so each
  screenshot is reported once. On both platforms only screenshots taken
  while your app is on screen are reported. Android 15 and newer detect recording. Older
  versions send `unknown`.
- No storage, photos or media permission is ever requested. The
  `DETECT_SCREEN_CAPTURE` and `DETECT_SCREEN_RECORDING` permissions are
  granted at install time and never shown to the user.

### Platforms

- Flutter 3.38 or newer, Android 7.0 (API 24) or newer, iOS 13 or newer.
- iOS supports Swift Package Manager and CocoaPods, and includes a privacy
  manifest.

# secure_screen_privacy

A Flutter plugin for screen privacy on Android and iOS: block screenshots/screen
recording, and customize what's shown in the OS app switcher / recents preview.

## Usage

### Block screenshots & screen recording

```dart
final privacy = SecureScreenPrivacy();

await privacy.enableCaptureProtection();
await privacy.disableCaptureProtection();
final isEnabled = await privacy.isCaptureProtectionEnabled();
```

> **Note:** with only `enableCaptureProtection` on (no app switcher protection),
> the OS app switcher / recents preview will show a plain black card while
> backgrounded. That's the underlying OS mechanism itself — Android's
> `FLAG_SECURE` and iOS's secure-text-entry trick both blank any capture of
> the window, including the app switcher snapshot, not just screenshots/
> recording — not a plugin bug. Pair it with `enableAppSwitcherProtection`
> below if you want something other than plain black shown there.

### App switcher protection

```dart
await privacy.enableAppSwitcherProtection(
  AppSwitcherProtectionMode.blur,
  blurIntensity: BlurIntensity.medium, // blur only
);

await privacy.enableAppSwitcherProtection(
  AppSwitcherProtectionMode.color,
  color: 0xFF000000, // color only, ARGB
);

await privacy.enableAppSwitcherProtection(
  AppSwitcherProtectionMode.image,
  imageBackgroundColor: 0xFF000000, // image/imageBlur, ARGB
);

await privacy.enableAppSwitcherProtection(
  AppSwitcherProtectionMode.imageBlur,
  blurIntensity: BlurIntensity.medium, // blur intensity
  imageBackgroundColor: 0xFF000000, // fallback background, ARGB
);

await privacy.disableAppSwitcherProtection();
final isEnabled = await privacy.isAppSwitcherProtectionEnabled();
```

`blurIntensity` has four levels — `ultraLight` (default), `light`, `medium`,
`heavy` — mapped on iOS to increasingly opaque `UIBlurEffect` materials.

> **Platform difference:** `mode` and the styling parameters above
> (`blurIntensity`/`color`/`imageBackgroundColor`) are **iOS-only**. On
> Android, `enableAppSwitcherProtection` always relies solely on
> `FLAG_SECURE` for the entire time protection is enabled, showing a plain
> black/secure card in the app switcher regardless of `mode` — no custom
> overlay is rendered there. This is deliberate, not a missing feature: on
> Android, none of a custom overlay view, `RenderEffect` blur, or
> `PixelCopy`-based capture protects the live gesture-nav "swipe up and
> hold" recents peek (the OS composites the app's actual on-screen window
> directly during that gesture, which isn't a capture/cast/recording at
> all), so `FLAG_SECURE` alone already provides the maximum protection
> Android allows, and a custom overlay would only add implementation cost
> with no additional coverage. `mode` is still required (and still selects
> real behavior) on iOS, whose secure-window mechanism doesn't have this
> gesture-peek gap.

Shows a blur, a static image (optionally over a blurred backdrop), or a
solid color in the iOS App Switcher preview instead of your live UI
whenever the app is backgrounded (Android always shows a plain
black/secure card instead, per the note above).

`AppSwitcherProtectionMode.image` and `AppSwitcherProtectionMode.imageBlur`
require the host app to bundle an image set named `SecureScreenPrivacyImage`
in `Assets.xcassets` **on iOS**. `enableAppSwitcherProtection` returns
`false` immediately if that image is missing, rather than failing silently
later. The image is shown at its correct aspect ratio (never cropped or
stretched); `imageBackgroundColor` fills any resulting letterbox/pillarbox
bars and shows through transparent areas of the image itself. Android has
no equivalent resource requirement, since it doesn't render an image
overlay.

> **`imageBlur` note:** shows the same bundled image as `image` mode, but
> over a live blurred snapshot of the screen instead of a solid color. Blur
> is always attempted (the same pipeline `blur` mode uses); it's computed
> asynchronously, and rather than showing a solid-color placeholder in the
> meantime (which read as a jarring flicker once the blur popped in), the
> sharp image appears immediately with a transparent background, so
> whatever's behind it is visible, unblurred, for that brief window until
> the blur is ready and gets inserted behind it.

> **iOS note:** if `enableCaptureProtection` is also on, it's transiently
> disabled while the overlay is shown (otherwise the OS would blank the
> snapshot regardless of the overlay) and restored as soon as the app
> returns to the foreground. The overlay itself is shown on
> `applicationWillResignActive` / `sceneWillResignActive`, since that's what
> fires before the interactive App Switcher preview snapshot is captured.
> That hook also fires on transient interruptions (incoming call, Siri,
> Control Center, share sheet), so the overlay will briefly flash in those
> cases too — this is inherent to the technique, not a bug.

### Screenshot detection

Get notified when the user takes a screenshot:

```dart
final subscription = privacy.screenshotEvents.listen((event) {
  print('Screenshot detected at ${event.timestamp}');
});

// Later:
await subscription.cancel();
```

Subscribing to `screenshotEvents` *is* what starts native detection
(Android 14+: `Activity.ScreenCaptureCallback`; older Android: a
`ContentObserver` on the images `MediaStore`; iOS:
`UIApplication.userDidTakeScreenshotNotification`); cancelling the
subscription stops it. There's no separate start/stop method. `ScreenshotEvent`
carries only a `timestamp` — no file path or image data.

Detection is best-effort and has real platform-specific caveats:

> **Android 14+ (API 34+):** uses the OS's own screenshot callback, so each
> screenshot of your app is reported exactly once. It only fires while your
> app's screen is visible. The plugin
> declares the `DETECT_SCREEN_CAPTURE` permission for this. It's an
> install-time permission, never shown to the user, not a storage/media
> permission, and it's merged into your app's manifest automatically.

> **Android 13 and below:** no storage/media permission is requested, so detection
> uses a heuristic filter over `MediaStore` change notifications (matching a
> "screenshot" substring in the file's name/path, and requiring the row to be
> freshly added) to avoid reporting every new photo/download as a screenshot.
> When the underlying metadata can't be read at all, the filter fails *open*
> (still emits) rather than silently dropping a real screenshot — so it can
> both under- and over-report depending on locale (a localized display name
> like "Bildschirmfoto" won't match) and OEM (custom screenshot folder
> naming). Deleted images are ignored, and the several notifications a single
> screenshot produces are merged into one event (anything within 1.5 seconds
> of the last event is dropped). New images saved by other apps can still be
> reported. Not confirmed across real hardware/OEM variance.

> **Android, while capture protection is on:** a screenshot attempt is still
> reported on every Android version, even though the saved image is black
> (`FLAG_SECURE` blanks the content but doesn't stop the system from taking
> the screenshot). Use the event to react to the attempt; the content itself
> stayed hidden.

> **iOS note:** uses `UIApplication.userDidTakeScreenshotNotification`, which
> never provides a file path or image data — this is why the payload is
> timestamp-only by design, not a placeholder workaround.

> **Scope:** on Android 14+ only screenshots of your visible app are
> reported. On Android 13 and below detection is MediaStore-wide, and on iOS
> it's a process-wide notification. On those, pair the subscription with your
> own app-foreground tracking if you need to filter it down.

### Screen recording detection

Get notified when the screen starts or stops being recorded/mirrored:

```dart
final subscription = privacy.screenRecordingEvents.listen((event) {
  print('Recording ${event.isRecording ? "started" : "stopped"} at ${event.timestamp}');
});

// Later:
await subscription.cancel();
```

Subscribing to `screenRecordingEvents` *is* what starts native detection
(Android: `WindowManager.addScreenRecordingCallback` on API 35+, no-op below
API 35; iOS:
`UIScreen.capturedDidChangeNotification`); cancelling the subscription stops
it. There's no separate start/stop method. The current state is emitted
immediately on subscribe, so a late subscriber doesn't miss an
already-in-progress recording. No runtime permission is required on either
platform (on Android 15+ it uses the install-time `DETECT_SCREEN_RECORDING`
permission, which the plugin declares for you and the user never sees).

> **Android note:** recording detection needs **Android 15 (API 35)** or
> newer, where `WindowManager.addScreenRecordingCallback` gives true start
> *and* stop detection. **Below API 35** it's a graceful no-op and nothing is
> ever emitted: Android 14 has no screen-recording signal. (Its
> `Activity.ScreenCaptureCallback` fires for screenshots, not recordings;
> see `screenshotEvents`.)

> **iOS note:** uses `UIScreen.capturedDidChangeNotification`, which reports
> a live `isCaptured` boolean rather than a directional start/stop event, so
> a single observer correctly reports both start and stop. There's no de-duplication: a notification for an
> unrelated screen/scene (e.g. an external display in a multi-scene app) can
> re-emit an unchanged value.

## Getting Started

This project is a starting point for a Flutter
[plug-in package](https://flutter.dev/to/develop-plugins),
a specialized package that includes platform-specific implementation code for
Android and/or iOS.

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev), which offers tutorials,
samples, guidance on mobile development, and a full API reference.


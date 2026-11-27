package com.mrrhak.secure_screen_privacy

import android.app.Activity
import android.content.Context
import android.database.ContentObserver
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.provider.MediaStore
import android.view.WindowManager
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.util.function.Consumer

/** SecureScreenPrivacyPlugin */
class SecureScreenPrivacyPlugin :
    FlutterPlugin,
    MethodCallHandler,
    ActivityAware,
    EventChannel.StreamHandler {
    // The MethodChannel that will the communication between Flutter and native Android
    //
    // This local reference serves to register the plugin with the Flutter Engine and unregister it
    // when the Flutter Engine is detached from the Activity
    private lateinit var channel: MethodChannel
    private lateinit var appContext: Context
    private var activity: Activity? = null
    private var isCaptureProtectionEnabled = false

    // App switcher protection state. Android has no custom overlay - see the
    // "App switcher protection" section below for why FLAG_SECURE alone is
    // the whole implementation here, unlike iOS which keeps a full set of
    // custom overlay modes.
    private var isAppSwitcherProtectionEnabled = false

    // Screenshot event stream. Engine-scoped (registered against appContext)
    // rather than tied to Activity attach state - a screenshot is a
    // device-level event, not something that should stop being detected
    // during e.g. a config-change-driven Activity recreation.
    private lateinit var screenshotEventChannel: EventChannel
    private var screenshotEventSink: EventChannel.EventSink? = null
    private var screenshotContentObserver: ContentObserver? = null

    // Dedicated background thread so the MediaStore query in
    // handleMediaStoreChange() never runs on the main thread (disk IO);
    // only the final EventSink.success() call is hopped back to main, since
    // EventSink must be invoked on the platform thread. Its lifecycle
    // matches the ContentObserver's 1:1 (started in onListen, stopped in
    // onCancel).
    private var screenshotObserverThread: HandlerThread? = null

    // Screen recording event stream. Unlike the screenshot ContentObserver
    // above, both Android detection APIs are Activity-scoped
    // (act.windowManager / act.mainExecutor need a live Activity), so this
    // needs its own isRecordingListening flag wired through the ActivityAware
    // callbacks below rather than being set up once at engine-attach time.
    private lateinit var screenRecordingEventChannel: EventChannel
    private var screenRecordingEventSink: EventChannel.EventSink? = null
    private var isRecordingListening = false
    private var screenRecordingCallback: Consumer<Int>? = null // API 35+ only
    private var screenCaptureCallback: Activity.ScreenCaptureCallback? = null // API 34 only

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        appContext = flutterPluginBinding.applicationContext
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "secure_screen_privacy")
        channel.setMethodCallHandler(this)

        screenshotEventChannel =
            EventChannel(flutterPluginBinding.binaryMessenger, "secure_screen_privacy/screenshot_events")
        screenshotEventChannel.setStreamHandler(this)

        // A dedicated handler object, not `this`: a single StreamHandler
        // instance registered against two different channels can't tell
        // which channel's onListen/onCancel it's being called for (the
        // `arguments` parameter is only the Dart-side listen() payload, never
        // the channel name) - sharing one would incorrectly arm this
        // channel's native side effects whenever the OTHER channel is
        // subscribed to, and vice versa.
        screenRecordingEventChannel =
            EventChannel(flutterPluginBinding.binaryMessenger, "secure_screen_privacy/screen_recording_events")
        screenRecordingEventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                screenRecordingEventSink = events
                isRecordingListening = true
                registerScreenRecordingCallbacksIfNeeded()
            }

            override fun onCancel(arguments: Any?) {
                isRecordingListening = false
                unregisterScreenRecordingCallbacks()
                screenRecordingEventSink = null
            }
        })
    }

    override fun onMethodCall(
        call: MethodCall,
        result: Result
    ) {
        when (call.method) {
            "getPlatformVersion" -> result.success("Android ${android.os.Build.VERSION.RELEASE}")
            "enableCaptureProtection" -> result.success(setCaptureProtection(true))
            "disableCaptureProtection" -> result.success(setCaptureProtection(false))
            "isCaptureProtectionEnabled" -> result.success(isCaptureProtectionEnabled)
            "enableAppSwitcherProtection" -> {
                val mode = call.argument<String>("mode")
                result.success(setAppSwitcherProtection(mode))
            }
            "disableAppSwitcherProtection" -> result.success(clearAppSwitcherProtection())
            "isAppSwitcherProtectionEnabled" -> result.success(isAppSwitcherProtectionEnabled)
            else -> result.notImplemented()
        }
    }

    // Screenshot detection
    //
    // Subscribing to the Dart stream (onListen) starts a ContentObserver on
    // the images MediaStore; cancelling (onCancel) stops it. There is no
    // separate start/stop method - the subscription is the toggle. See
    // shouldEmitScreenshotEvent for the filtering heuristic and its
    // documented tradeoffs.

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        screenshotEventSink = events
        registerScreenshotObserver()
    }

    override fun onCancel(arguments: Any?) {
        unregisterScreenshotObserver()
        screenshotEventSink = null
    }

    private fun registerScreenshotObserver() {
        if (screenshotContentObserver != null) return
        val thread = HandlerThread("secure_screen_privacy-screenshot-observer").apply { start() }
        screenshotObserverThread = thread
        val observer = object : ContentObserver(Handler(thread.looper)) {
            override fun onChange(selfChange: Boolean, uri: Uri?) {
                handleMediaStoreChange(uri)
            }
        }
        try {
            appContext.contentResolver.registerContentObserver(
                MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                true, // notifyForDescendants: needed to receive the specific changed item's URI
                observer
            )
            screenshotContentObserver = observer
        } catch (e: SecurityException) {
            // No known device/OEM this has been observed on, but
            // registration is guarded defensively rather than crashing the
            // host app.
            thread.quitSafely()
            screenshotObserverThread = null
        }
    }

    private fun unregisterScreenshotObserver() {
        screenshotContentObserver?.let { appContext.contentResolver.unregisterContentObserver(it) }
        screenshotContentObserver = null
        screenshotObserverThread?.quitSafely()
        screenshotObserverThread = null
    }

    // Runs on screenshotObserverThread, not main.
    private fun handleMediaStoreChange(uri: Uri?) {
        if (uri == null) return
        var displayName: String? = null
        var relativePathOrData: String? = null
        var dateAddedMillis: Long? = null
        try {
            val projection = mutableListOf(
                MediaStore.Images.Media.DISPLAY_NAME,
                MediaStore.Images.Media.DATE_ADDED
            )
            val pathColumn =
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    MediaStore.Images.Media.RELATIVE_PATH
                } else {
                    MediaStore.Images.Media.DATA
                }
            projection.add(pathColumn)
            appContext.contentResolver.query(uri, projection.toTypedArray(), null, null, null)?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val nameIdx = cursor.getColumnIndex(MediaStore.Images.Media.DISPLAY_NAME)
                    if (nameIdx >= 0 && !cursor.isNull(nameIdx)) displayName = cursor.getString(nameIdx)

                    val dateIdx = cursor.getColumnIndex(MediaStore.Images.Media.DATE_ADDED)
                    if (dateIdx >= 0 && !cursor.isNull(dateIdx)) dateAddedMillis = cursor.getLong(dateIdx) * 1000L

                    val pathIdx = cursor.getColumnIndex(pathColumn)
                    if (pathIdx >= 0 && !cursor.isNull(pathIdx)) relativePathOrData = cursor.getString(pathIdx)
                }
            }
        } catch (e: Exception) {
            // Query failed (permission denied, row not visible to this app
            // under scoped storage, transient provider error, ...) - fall
            // through with nulls; shouldEmitScreenshotEvent() fails open in
            // that case.
        }

        if (shouldEmitScreenshotEvent(displayName, relativePathOrData, dateAddedMillis, System.currentTimeMillis())) {
            val payload = mapOf("timestamp" to (dateAddedMillis ?: System.currentTimeMillis()))
            Handler(Looper.getMainLooper()).post {
                screenshotEventSink?.success(payload)
            }
        }
    }

    // Screen recording detection
    //
    // Subscribing to the Dart stream (onListen) starts detection; cancelling
    // (onCancel) stops it - same subscribe-is-the-toggle model as screenshot
    // detection above. isRecordingListening additionally gates re-
    // registration across Activity attach/reattach (see ActivityAware
    // section below), since - unlike the engine-scoped screenshot
    // ContentObserver - both detection APIs here require a live Activity.
    //
    // API 35+: WindowManager.addScreenRecordingCallback gives true start AND
    // stop detection. API 34: Activity.ScreenCaptureCallback fires once when
    // recording starts, with NO corresponding stop callback at the OS level
    // - isRecording is emitted true and never auto-reset to false; the Dart
    // subscriber must cancel and re-subscribe to reset it. This matches the
    // sibling no_screenshot plugin's behavior exactly. Below API 34: no-op.

    private fun registerScreenRecordingCallbacksIfNeeded() {
        if (!isRecordingListening) return
        val act = activity ?: return
        when (screenRecordingRegistrationPathForSdkInt(Build.VERSION.SDK_INT)) {
            ScreenRecordingRegistrationPath.WINDOW_MANAGER_CALLBACK -> registerWindowManagerRecordingCallback(act)
            ScreenRecordingRegistrationPath.ACTIVITY_SCREEN_CAPTURE_CALLBACK -> registerActivityScreenCaptureCallback(act)
            ScreenRecordingRegistrationPath.UNSUPPORTED -> {}
        }
    }

    // @Suppress("NewApi"): the SDK_INT guard lives in
    // screenRecordingRegistrationPathForSdkInt/registerScreenRecordingCallbacksIfNeeded,
    // a different method than this API call - Lint's NewApi check only
    // recognizes a guard inline in the same method as the call it protects.
    @Suppress("NewApi")
    private fun registerWindowManagerRecordingCallback(act: Activity) {
        if (screenRecordingCallback != null) return
        val callback = Consumer<Int> { state -> emitScreenRecordingEvent(isRecordingStateVisible(state)) }
        // addScreenRecordingCallback also returns the current state
        // synchronously, so a late subscriber sees an already-in-progress
        // recording immediately rather than waiting for the next transition.
        val initialState = act.windowManager.addScreenRecordingCallback(act.mainExecutor, callback)
        screenRecordingCallback = callback
        emitScreenRecordingEvent(isRecordingStateVisible(initialState))
    }

    @Suppress("NewApi")
    private fun registerActivityScreenCaptureCallback(act: Activity) {
        if (screenCaptureCallback != null) return
        val callback = Activity.ScreenCaptureCallback { emitScreenRecordingEvent(true) }
        act.registerScreenCaptureCallback(act.mainExecutor, callback)
        screenCaptureCallback = callback
    }

    private fun unregisterScreenRecordingCallbacks() {
        val act = activity
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.VANILLA_ICE_CREAM) {
            screenRecordingCallback?.let { act?.windowManager?.removeScreenRecordingCallback(it) }
            screenRecordingCallback = null
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            screenCaptureCallback?.let { act?.unregisterScreenCaptureCallback(it) }
            screenCaptureCallback = null
        }
    }

    // act.mainExecutor already delivers these callbacks on the main thread,
    // unlike handleMediaStoreChange's ContentObserver (which genuinely runs
    // off-main) - no Handler(Looper.getMainLooper()).post() hop needed here.
    private fun emitScreenRecordingEvent(isRecording: Boolean) {
        screenRecordingEventSink?.success(
            mapOf("isRecording" to isRecording, "timestamp" to System.currentTimeMillis())
        )
    }

    // FLAG_SECURE blocks both screenshots and screen recording of the
    // Activity's window, and (unlike iOS) also blanks its app-switcher/
    // recents thumbnail for free - no separate app-switcher handling needed
    // on Android.
    //
    // The requested state is always recorded, even when no Activity/Window
    // is attached yet (add-to-app or background engines, or a call landing
    // between onDetachedFromActivityForConfigChanges and
    // onReattachedToActivityForConfigChanges): reapplyFlagSecureIfNeeded()
    // applies it as soon as an Activity attaches. Dropping the request
    // instead would leave the screen unprotected with no later retry.
    private fun setCaptureProtection(enabled: Boolean): Boolean {
        isCaptureProtectionEnabled = enabled
        val window = activity?.window ?: return true
        if (enabled) {
            window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        } else if (!isAppSwitcherProtectionEnabled) {
            // Only clear the flag if app switcher protection isn't also
            // relying on it - otherwise disabling capture protection alone
            // would silently turn app switcher protection off too, even
            // though isAppSwitcherProtectionEnabled would still report true.
            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
        }
        return true
    }

    // App switcher protection
    //
    // Android has no custom overlay rendering - FLAG_SECURE alone is applied
    // for the entire time protection is enabled (not toggled reactively
    // around pause/resume/focus), because it's the only mechanism that has
    // any effect during the live gesture-nav "swipe up and hold" recents
    // peek. That peek composites the app's actual on-screen window directly
    // (a real-time mirror of FlutterSurfaceView's own SurfaceFlinger layer),
    // not a capture/cast/recording - confirmed on a real device (Samsung
    // SM-J810Y, Android 10/API 29, gesture nav) that neither a rendered
    // overlay view, RenderEffect, PixelCopy-based capture, nor even
    // FLAG_SECURE itself blocks content during the hold itself. Releasing
    // the gesture into a settled, genuinely-backgrounded task IS correctly
    // protected by FLAG_SECURE alone, verified via adb across full
    // backgrounding, a direct app-switch peek, and revisiting a cached
    // thumbnail after switching to a different app - the same cases a custom
    // overlay used to handle, at far greater implementation cost, with no
    // additional coverage. iOS is unaffected by this gap (its secure-window
    // mechanism has no equivalent live-compositor bypass) and keeps its full
    // set of custom overlay AppSwitcherProtectionMode renderings.
    //
    // mode/blurIntensity/color/imageBackgroundColor are still accepted on the
    // method channel for cross-platform API-contract parity with iOS, but
    // Android only reads mode (to preserve the existing null-check contract)
    // and otherwise ignores all of them.

    // Like setCaptureProtection, recorded even with no Activity attached yet
    // and applied by reapplyFlagSecureIfNeeded() on attach.
    private fun setAppSwitcherProtection(mode: String?): Boolean {
        if (mode == null) return false
        isAppSwitcherProtectionEnabled = true
        activity?.window?.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        return true
    }

    private fun clearAppSwitcherProtection(): Boolean {
        isAppSwitcherProtectionEnabled = false
        if (!isCaptureProtectionEnabled) {
            activity?.window?.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
        }
        return true
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        screenshotEventChannel.setStreamHandler(null)
        unregisterScreenshotObserver() // safety net if onCancel never fired
        screenshotEventSink = null
        screenRecordingEventChannel.setStreamHandler(null)
        unregisterScreenRecordingCallbacks() // safety net if onCancel never fired
        screenRecordingEventSink = null
        isRecordingListening = false
    }

    // ActivityAware
    //
    // FLAG_SECURE is set on the Activity's Window, so the plugin tracks the
    // current Activity and re-applies the flag whenever attached to a new
    // one (e.g. after a config change recreates the Activity) - window flags
    // don't survive Activity recreation.

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        reapplyFlagSecureIfNeeded()
        registerScreenRecordingCallbacksIfNeeded()
    }

    override fun onDetachedFromActivityForConfigChanges() {
        unregisterScreenRecordingCallbacks() // must run before activity = null below
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
        reapplyFlagSecureIfNeeded()
        registerScreenRecordingCallbacksIfNeeded()
    }

    override fun onDetachedFromActivity() {
        unregisterScreenRecordingCallbacks() // must run before activity = null below
        activity = null
    }

    private fun reapplyFlagSecureIfNeeded() {
        if (isCaptureProtectionEnabled || isAppSwitcherProtectionEnabled) {
            activity?.window?.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        }
    }
}

// Extracted as a pure, Android-framework-free function so it's directly
// unit-testable without mocking ContentResolver/Cursor/HandlerThread for
// every branch.
//
// Filters MediaStore.Images changes down to ones that look like screenshots,
// to reduce false positives from ordinary saved/downloaded/camera images -
// but fails OPEN (returns true) whenever the available metadata is
// inconclusive, rather than silently dropping a real screenshot: a missed
// screenshot defeats the entire point of this feature, while an occasional
// false positive (e.g. the user saved a photo from a messaging app) does
// not. This is a deliberate improvement over the sibling no_screenshot
// plugin, which treats any MediaStore.Images change as a screenshot with no
// filtering at all. No permission is requested for this (see
// AndroidManifest.xml, which stays empty), so the filter is inherently
// best-effort: it can both under- and over-report depending on locale/OEM
// (see relativePathOrData/displayName comments below) and is not confirmed
// across real hardware/OEM variance.
internal fun shouldEmitScreenshotEvent(
    displayName: String?,
    relativePathOrData: String?,
    dateAddedMillis: Long?,
    nowMillis: Long,
    staleThresholdMillis: Long = 10_000L
): Boolean {
    // Can't determine recency at all - can't rule this out, fail open.
    if (dateAddedMillis == null) return true
    // Row is old relative to "now" - likely a metadata update/edit on an
    // existing file, not a fresh insert triggered by taking a screenshot.
    if (nowMillis - dateAddedMillis > staleThresholdMillis) return false

    // Path is checked first/preferentially: the OS/OEM typically creates a
    // literal "Screenshots" folder even on non-English locales, so it's less
    // likely to be localized than the display name (which may be, e.g.
    // "Bildschirmfoto", "Capture d'écran" - a real, undocumented,
    // OEM/locale-dependent gap in this heuristic).
    if (relativePathOrData?.contains("screenshot", ignoreCase = true) == true) return true
    if (displayName?.contains("screenshot", ignoreCase = true) == true) return true

    // Both values were available and neither matched - fail closed.
    if (displayName != null || relativePathOrData != null) return false

    // Neither value was available (e.g. columns not returned) - can't
    // determine, fail open.
    return true
}

// Which Android screen-recording detection API is available at a given SDK
// level. Extracted as a pure function (same reasoning as
// shouldEmitScreenshotEvent above) so the SDK-level tiering is directly
// unit-testable.
internal enum class ScreenRecordingRegistrationPath {
    WINDOW_MANAGER_CALLBACK, // API 35+: true start/stop detection
    ACTIVITY_SCREEN_CAPTURE_CALLBACK, // API 34: start-only, no stop signal
    UNSUPPORTED // < API 34: graceful no-op
}

internal fun screenRecordingRegistrationPathForSdkInt(sdkInt: Int): ScreenRecordingRegistrationPath =
    when {
        sdkInt >= Build.VERSION_CODES.VANILLA_ICE_CREAM -> ScreenRecordingRegistrationPath.WINDOW_MANAGER_CALLBACK
        sdkInt >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE -> ScreenRecordingRegistrationPath.ACTIVITY_SCREEN_CAPTURE_CALLBACK
        else -> ScreenRecordingRegistrationPath.UNSUPPORTED
    }

// WindowManager.SCREEN_RECORDING_STATE_VISIBLE is a compile-time-constant
// Int field (added API 35), so referencing it here has no runtime effect on
// older devices - this comparison is inlined to a plain int equality check -
// but it's still an API-35 symbol from Lint's point of view.
@Suppress("NewApi")
internal fun isRecordingStateVisible(state: Int): Boolean =
    state == WindowManager.SCREEN_RECORDING_STATE_VISIBLE

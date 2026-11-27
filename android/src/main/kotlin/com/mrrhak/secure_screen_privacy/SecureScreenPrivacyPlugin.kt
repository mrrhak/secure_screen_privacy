package com.mrrhak.secure_screen_privacy

import android.app.Activity
import android.app.ActivityManager
import android.app.Application
import android.content.ComponentCallbacks
import android.content.ContentResolver
import android.content.Context
import android.content.res.Configuration
import android.database.ContentObserver
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.provider.MediaStore
import android.util.TypedValue
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
    private var appSwitcherMode: String? = null
    private var appSwitcherColor: Int? = null
    private var appSwitcherImageBackgroundColor: Int? = null

    // App Switcher card colour (Android 13+ only). While FLAG_SECURE is on,
    // Android shows a blank card filled with the task's background colour,
    // which by default is the theme's android:colorBackground read once at
    // Activity start - so it ignores AppSwitcherProtectionMode.color and
    // keeps the old colour after a dark/light switch until the app restarts.
    // The plugin sets that colour itself via setTaskDescription: the chosen
    // colour for color/image mode, otherwise the theme's current
    // colorBackground, re-applied on every pause and configuration change.
    // See appSwitcherCardColor below.
    private var hasSetTaskBackgroundColor = false
    private var lifecycleCallbacks: Application.ActivityLifecycleCallbacks? = null
    private var configurationCallbacks: ComponentCallbacks? = null

    // Screenshot event stream. Two detection paths, picked by
    // screenshotDetectionPathForSdkInt: on API 34+ the OS's own
    // Activity.ScreenCaptureCallback (exact, once per screenshot of this
    // app's visible Activity - Activity-scoped, so wired through the
    // ActivityAware callbacks via isScreenshotListening, like screen
    // recording below); below API 34 a MediaStore ContentObserver registered
    // against the engine-scoped appContext, de-duplicated by
    // screenshotDeduper.
    private lateinit var screenshotEventChannel: EventChannel
    private var screenshotEventSink: EventChannel.EventSink? = null
    private var isScreenshotListening = false
    private var screenshotCaptureCallback: Activity.ScreenCaptureCallback? = null // API 34+ only
    private var screenshotContentObserver: ContentObserver? = null
    private val screenshotDeduper = ScreenshotEventDeduper()

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
    private val screenRecordingStateDeduper = ScreenRecordingStateDeduper()

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
                // A new subscriber always gets the current state first.
                screenRecordingStateDeduper.reset()
                // Below API 35 there's nothing to register, so tell the
                // subscriber once that the state is unknown instead of
                // sending nothing. Sent here, not on Activity attach, so it
                // isn't repeated on every Activity recreation.
                if (screenRecordingRegistrationPathForSdkInt(Build.VERSION.SDK_INT) ==
                    ScreenRecordingRegistrationPath.UNSUPPORTED
                ) {
                    emitScreenRecordingEvent(null)
                }
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
                result.success(
                    setAppSwitcherProtection(
                        mode,
                        (call.argument<Any>("color") as? Number)?.toInt(),
                        (call.argument<Any>("imageBackgroundColor") as? Number)?.toInt(),
                    )
                )
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
        isScreenshotListening = true
        when (screenshotDetectionPathForSdkInt(Build.VERSION.SDK_INT)) {
            ScreenshotDetectionPath.ACTIVITY_SCREEN_CAPTURE_CALLBACK -> registerScreenshotCaptureCallbackIfNeeded()
            ScreenshotDetectionPath.MEDIA_STORE_OBSERVER -> registerScreenshotObserver()
        }
    }

    override fun onCancel(arguments: Any?) {
        isScreenshotListening = false
        unregisterScreenshotCaptureCallback()
        unregisterScreenshotObserver()
        screenshotEventSink = null
    }

    // API 34+: Activity.ScreenCaptureCallback fires exactly once per
    // screenshot, only while this app's Activity is visible. It still fires
    // when the window has FLAG_SECURE (the saved image is black), as seen on
    // API 34 and 37 emulators. Needs
    // the install-time DETECT_SCREEN_CAPTURE permission declared in this
    // plugin's AndroidManifest.xml - not a storage/media permission.
    @Suppress("NewApi")
    private fun registerScreenshotCaptureCallbackIfNeeded() {
        if (!isScreenshotListening || screenshotCaptureCallback != null) return
        if (screenshotDetectionPathForSdkInt(Build.VERSION.SDK_INT) !=
            ScreenshotDetectionPath.ACTIVITY_SCREEN_CAPTURE_CALLBACK
        ) return
        val act = activity ?: return
        val callback = Activity.ScreenCaptureCallback {
            screenshotEventSink?.success(mapOf("timestamp" to System.currentTimeMillis()))
        }
        try {
            act.registerScreenCaptureCallback(act.mainExecutor, callback)
            screenshotCaptureCallback = callback
        } catch (e: SecurityException) {
            // Only if a host app strips DETECT_SCREEN_CAPTURE from the merged
            // manifest - degrade to no detection instead of crashing.
        }
    }

    @Suppress("NewApi")
    private fun unregisterScreenshotCaptureCallback() {
        val callback = screenshotCaptureCallback ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            activity?.unregisterScreenCaptureCallback(callback)
        }
        screenshotCaptureCallback = null
    }

    private fun registerScreenshotObserver() {
        if (screenshotContentObserver != null) return
        screenshotDeduper.reset()
        val thread = HandlerThread("secure_screen_privacy-screenshot-observer").apply { start() }
        screenshotObserverThread = thread
        val observer = object : ContentObserver(Handler(thread.looper)) {
            override fun onChange(selfChange: Boolean, uri: Uri?) {
                handleMediaStoreChange(uri)
            }

            // API 30+ delivers change flags; a delete is never a new
            // screenshot. (The framework's default implementation of this
            // overload just calls onChange(selfChange, uri) per URI.)
            override fun onChange(selfChange: Boolean, uris: Collection<Uri>, flags: Int) {
                if (!isMediaStoreChangeWorthChecking(flags)) return
                uris.forEach { handleMediaStoreChange(it) }
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

        val now = System.currentTimeMillis()
        // One screenshot produces several MediaStore notifications (Android
        // 10+ inserts the row as pending, then updates it once written), and
        // without a media permission the query above usually returns nothing,
        // so each of them would pass the fail-open filter - the deduper
        // collapses that burst into a single event.
        if (shouldEmitScreenshotEvent(displayName, relativePathOrData, dateAddedMillis, now) &&
            screenshotDeduper.shouldEmit(now)
        ) {
            // Detection time, like the API 34+ path and iOS. DATE_ADDED is
            // only whole seconds, so it would read up to a second early.
            val payload = mapOf("timestamp" to now)
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
    // stop detection (needs the install-time DETECT_SCREEN_RECORDING
    // permission declared in this plugin's AndroidManifest.xml). Below API 35:
    // one "unknown" event (isRecording null) on subscribe, then nothing. Android 14 has no screen-recording signal at all:
    // Activity.ScreenCaptureCallback, which an earlier version used here,
    // fires for screenshots, not recordings, so it reported every screenshot
    // as "recording started" and never saw a real recording.

    private fun registerScreenRecordingCallbacksIfNeeded() {
        if (!isRecordingListening) return
        val act = activity ?: return
        when (screenRecordingRegistrationPathForSdkInt(Build.VERSION.SDK_INT)) {
            ScreenRecordingRegistrationPath.WINDOW_MANAGER_CALLBACK -> registerWindowManagerRecordingCallback(act)
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
        val initialState = try {
            act.windowManager.addScreenRecordingCallback(act.mainExecutor, callback)
        } catch (e: SecurityException) {
            // Only if a host app strips DETECT_SCREEN_RECORDING from the
            // merged manifest - degrade to no detection instead of failing,
            // and report "unknown" rather than staying silent.
            emitScreenRecordingEvent(null)
            return
        }
        screenRecordingCallback = callback
        emitScreenRecordingEvent(isRecordingStateVisible(initialState))
    }

    private fun unregisterScreenRecordingCallbacks() {
        val act = activity
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.VANILLA_ICE_CREAM) {
            screenRecordingCallback?.let { act?.windowManager?.removeScreenRecordingCallback(it) }
            screenRecordingCallback = null
        }
    }

    // act.mainExecutor already delivers these callbacks on the main thread,
    // unlike handleMediaStoreChange's ContentObserver (which genuinely runs
    // off-main) - no Handler(Looper.getMainLooper()).post() hop needed here.
    // null means "can't tell" (Dart maps it to ScreenRecordingState.unknown).
    //
    // Only a change of state is sent: re-registering on Activity recreation
    // (rotation, dark mode...) reports the current state again, which used
    // to reach Dart as a repeat of the state it already had.
    private fun emitScreenRecordingEvent(isRecording: Boolean?) {
        if (!screenRecordingStateDeduper.shouldEmit(isRecording)) return
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
        updateTaskBackgroundColor()
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
    // There is no blur or image on Android. On Android 13+ the blank card's
    // colour follows the mode instead (see appSwitcherCardColor): color mode
    // uses `color`, image mode uses `imageBackgroundColor`, and blur/imageBlur
    // use the theme's current background colour. blurIntensity is ignored.

    // Like setCaptureProtection, recorded even with no Activity attached yet
    // and applied by reapplyFlagSecureIfNeeded() on attach.
    private fun setAppSwitcherProtection(
        mode: String?,
        color: Int?,
        imageBackgroundColor: Int?,
    ): Boolean {
        if (mode == null) return false
        isAppSwitcherProtectionEnabled = true
        appSwitcherMode = mode
        appSwitcherColor = color
        appSwitcherImageBackgroundColor = imageBackgroundColor
        activity?.window?.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        updateTaskBackgroundColor()
        return true
    }

    private fun clearAppSwitcherProtection(): Boolean {
        isAppSwitcherProtectionEnabled = false
        appSwitcherMode = null
        appSwitcherColor = null
        appSwitcherImageBackgroundColor = null
        if (!isCaptureProtectionEnabled) {
            activity?.window?.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
        }
        updateTaskBackgroundColor()
        return true
    }

    // Sets (or, once protection is off, resets) the background colour of the
    // App Switcher card. Keeps the task's current label and colours, which
    // Flutter itself sets from MaterialApp.title/color, and only swaps the
    // background colour. Flutter resets the whole description whenever the
    // Title widget rebuilds, which is why this also runs on every pause.
    private fun updateTaskBackgroundColor() {
        if (!isTaskBackgroundColorSupported(Build.VERSION.SDK_INT)) return
        val act = activity ?: return
        val isProtected = isCaptureProtectionEnabled || isAppSwitcherProtectionEnabled
        if (!isProtected && !hasSetTaskBackgroundColor) return
        val background = if (isProtected) {
            appSwitcherCardColor(
                if (isAppSwitcherProtectionEnabled) appSwitcherMode else null,
                appSwitcherColor,
                appSwitcherImageBackgroundColor,
                themeBackgroundColor(act),
            )
        } else {
            0 // 0 = no override: back to the theme's own colour
        }
        try {
            val current = currentTaskDescription(act)
            val builder = ActivityManager.TaskDescription.Builder()
            if (current != null) {
                current.label?.let { builder.setLabel(it) }
                builder.setPrimaryColor(current.primaryColor)
                builder.setStatusBarColor(current.statusBarColor)
                builder.setNavigationBarColor(current.navigationBarColor)
            }
            builder.setBackgroundColor(background)
            act.setTaskDescription(builder.build())
            hasSetTaskBackgroundColor = isProtected
        } catch (e: RuntimeException) {
            // Never let a cosmetic colour break protection itself.
        }
    }

    private fun currentTaskDescription(act: Activity): ActivityManager.TaskDescription? =
        try {
            act.getSystemService(ActivityManager::class.java)
                ?.appTasks
                ?.firstOrNull { it.taskInfo.taskId == act.taskId }
                ?.taskInfo
                ?.taskDescription
        } catch (e: RuntimeException) {
            null
        }

    // The theme's android:colorBackground for the current dark/light mode,
    // or 0 (no override) if it isn't a plain colour.
    private fun themeBackgroundColor(act: Activity): Int {
        val value = TypedValue()
        if (!act.theme.resolveAttribute(android.R.attr.colorBackground, value, true)) return 0
        return if (value.type in TypedValue.TYPE_FIRST_COLOR_INT..TypedValue.TYPE_LAST_COLOR_INT) {
            value.data
        } else {
            0
        }
    }

    private fun registerTaskColorCallbacks(act: Activity) {
        if (!isTaskBackgroundColorSupported(Build.VERSION.SDK_INT)) return
        unregisterTaskColorCallbacks(act)
        val lifecycle = object : Application.ActivityLifecycleCallbacks {
            override fun onActivityPaused(a: Activity) = updateTaskBackgroundColor()
            override fun onActivityCreated(a: Activity, b: Bundle?) {}
            override fun onActivityStarted(a: Activity) {}
            override fun onActivityResumed(a: Activity) {}
            override fun onActivityStopped(a: Activity) {}
            override fun onActivitySaveInstanceState(a: Activity, b: Bundle) {}
            override fun onActivityDestroyed(a: Activity) {}
        }
        act.registerActivityLifecycleCallbacks(lifecycle)
        lifecycleCallbacks = lifecycle
        val config = object : ComponentCallbacks {
            override fun onConfigurationChanged(newConfig: Configuration) = updateTaskBackgroundColor()
            @Deprecated("Deprecated in Java")
            override fun onLowMemory() {}
        }
        act.registerComponentCallbacks(config)
        configurationCallbacks = config
    }

    private fun unregisterTaskColorCallbacks(act: Activity?) {
        lifecycleCallbacks?.let { act?.unregisterActivityLifecycleCallbacks(it) }
        configurationCallbacks?.let { act?.unregisterComponentCallbacks(it) }
        lifecycleCallbacks = null
        configurationCallbacks = null
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        screenshotEventChannel.setStreamHandler(null)
        isScreenshotListening = false
        unregisterScreenshotCaptureCallback() // safety net if onCancel never fired
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
        registerTaskColorCallbacks(binding.activity)
        updateTaskBackgroundColor()
        registerScreenRecordingCallbacksIfNeeded()
        registerScreenshotCaptureCallbackIfNeeded()
    }

    override fun onDetachedFromActivityForConfigChanges() {
        unregisterScreenshotCaptureCallback() // must run before activity = null below
        unregisterScreenRecordingCallbacks() // must run before activity = null below
        unregisterTaskColorCallbacks(activity)
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
        reapplyFlagSecureIfNeeded()
        registerTaskColorCallbacks(binding.activity)
        updateTaskBackgroundColor()
        registerScreenRecordingCallbacksIfNeeded()
        registerScreenshotCaptureCallbackIfNeeded()
    }

    override fun onDetachedFromActivity() {
        unregisterScreenshotCaptureCallback() // must run before activity = null below
        unregisterScreenRecordingCallbacks() // must run before activity = null below
        unregisterTaskColorCallbacks(activity)
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

// Which Android screenshot detection mechanism to use at a given SDK level.
// Pure (same reasoning as shouldEmitScreenshotEvent) so it's unit-testable.
internal enum class ScreenshotDetectionPath {
    ACTIVITY_SCREEN_CAPTURE_CALLBACK, // API 34+: exact OS signal, this app's visible Activity only
    MEDIA_STORE_OBSERVER // < API 34: heuristic MediaStore ContentObserver
}

internal fun screenshotDetectionPathForSdkInt(sdkInt: Int): ScreenshotDetectionPath =
    if (sdkInt >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
        ScreenshotDetectionPath.ACTIVITY_SCREEN_CAPTURE_CALLBACK
    } else {
        ScreenshotDetectionPath.MEDIA_STORE_OBSERVER
    }

// Collapses the burst of MediaStore notifications a single screenshot
// produces (pending insert, then update once written, sometimes more) into
// one event: after an emit, anything within windowMillis is dropped. Two
// genuine screenshots inside that window are reported once - an accepted
// trade-off, since the OS itself can't take them much faster. Framework-free
// so it's unit-testable; only touched from the observer's HandlerThread.
internal class ScreenshotEventDeduper(private val windowMillis: Long = 1_500L) {
    private var lastEmittedMillis: Long? = null

    fun shouldEmit(nowMillis: Long): Boolean {
        val last = lastEmittedMillis
        if (last != null && nowMillis >= last && nowMillis - last < windowMillis) return false
        lastEmittedMillis = nowMillis
        return true
    }

    fun reset() {
        lastEmittedMillis = null
    }
}

// ContentObserver change flags (API 30+): a delete is never a new
// screenshot, so skip it. flags == 0 (older APIs / unknown) is checked.
// ContentResolver.NOTIFY_DELETE is a compile-time Int constant, inlined.
@Suppress("NewApi", "InlinedApi")
internal fun isMediaStoreChangeWorthChecking(flags: Int): Boolean =
    (flags and ContentResolver.NOTIFY_DELETE) == 0

// Which Android screen-recording detection API is available at a given SDK
// level. Extracted as a pure function (same reasoning as
// shouldEmitScreenshotEvent above) so the SDK-level tiering is directly
// unit-testable.
internal enum class ScreenRecordingRegistrationPath {
    WINDOW_MANAGER_CALLBACK, // API 35+: true start/stop detection
    UNSUPPORTED // < API 35: one "unknown" event on subscribe (Android 14 has no recording signal)
}

internal fun screenRecordingRegistrationPathForSdkInt(sdkInt: Int): ScreenRecordingRegistrationPath =
    when {
        sdkInt >= Build.VERSION_CODES.VANILLA_ICE_CREAM -> ScreenRecordingRegistrationPath.WINDOW_MANAGER_CALLBACK
        else -> ScreenRecordingRegistrationPath.UNSUPPORTED
    }

// WindowManager.SCREEN_RECORDING_STATE_VISIBLE is a compile-time-constant
// Int field (added API 35), so referencing it here has no runtime effect on
// older devices - this comparison is inlined to a plain int equality check -
// but it's still an API-35 symbol from Lint's point of view.
@Suppress("NewApi")
internal fun isRecordingStateVisible(state: Int): Boolean =
    state == WindowManager.SCREEN_RECORDING_STATE_VISIBLE

// Lets a screen recording state through only when it differs from the last
// one sent (null, "unknown", counts as a state of its own). Framework-free
// so it's unit-testable; only touched from the main thread.
internal class ScreenRecordingStateDeduper {
    private var hasEmitted = false
    private var lastState: Boolean? = null

    fun shouldEmit(state: Boolean?): Boolean {
        if (hasEmitted && state == lastState) return false
        hasEmitted = true
        lastState = state
        return true
    }

    fun reset() {
        hasEmitted = false
        lastState = null
    }
}

// Android 13 (API 33) added TaskDescription.Builder.setBackgroundColor, the
// only public way to set the App Switcher card colour at runtime.
internal fun isTaskBackgroundColorSupported(sdkInt: Int): Boolean = sdkInt >= 33

// The colour of the blank App Switcher card while protection is on. `mode`
// is the AppSwitcherProtectionMode name, or null when only capture protection
// is on. color mode uses `color`, image mode `imageBackgroundColor`; every
// other case uses the theme's current background colour. Colours are made
// fully opaque, since TaskDescription rejects a translucent background.
// 0 means "no override" (Android falls back to the theme's own colour).
internal fun appSwitcherCardColor(
    mode: String?,
    color: Int?,
    imageBackgroundColor: Int?,
    themeColor: Int,
): Int {
    val chosen = when (mode) {
        "color" -> color
        "image" -> imageBackgroundColor
        else -> null
    } ?: themeColor
    return if (chosen == 0) 0 else chosen or 0xFF000000.toInt()
}

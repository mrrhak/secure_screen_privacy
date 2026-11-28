package com.mrrhak.secure_screen_privacy

import android.app.Activity
import android.view.Window
import android.view.WindowManager
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import org.mockito.ArgumentMatchers.eq
import org.mockito.Mockito
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/*
 * This demonstrates a simple unit test of the Kotlin portion of this plugin's implementation.
 *
 * Once you have built the plugin's example app, you can run these tests from the command
 * line by running `./gradlew testDebugUnitTest` in the `example/android/` directory, or
 * you can run them directly from IDEs that support JUnit such as Android Studio.
 */

internal class SecureScreenPrivacyPluginTest {
    @Test
    fun getPlatformVersion_returnsExpectedValue() {
        val plugin = SecureScreenPrivacyPlugin()

        assertEquals("Android " + android.os.Build.VERSION.RELEASE, plugin.getPlatformVersion())
    }

    @Test
    fun enableCaptureProtection_withNoActivity_isKeptAndAppliedOnAttach() {
        val plugin = SecureScreenPrivacyPlugin()

        assertTrue(plugin.enableCaptureProtection())
        assertTrue(plugin.isCaptureProtectionEnabled())

        // An Activity attaching later must get FLAG_SECURE.
        val (_, mockWindow) = attachActivity(plugin)
        Mockito.verify(mockWindow).addFlags(eq(WindowManager.LayoutParams.FLAG_SECURE))
    }

    @Test
    fun disableCaptureProtection_withNoActivity_isNotReappliedOnAttach() {
        val plugin = SecureScreenPrivacyPlugin()
        plugin.enableCaptureProtection()
        plugin.disableCaptureProtection()

        val (_, mockWindow) = attachActivity(plugin)
        Mockito.verify(mockWindow, Mockito.never()).addFlags(eq(WindowManager.LayoutParams.FLAG_SECURE))
    }

    @Test
    fun enableCaptureProtection_withActivity_addsFlagSecureAndReturnsTrue() {
        val plugin = SecureScreenPrivacyPlugin()
        val (_, mockWindow) = attachActivity(plugin)

        assertTrue(plugin.enableCaptureProtection())

        Mockito.verify(mockWindow).addFlags(eq(WindowManager.LayoutParams.FLAG_SECURE))
    }

    @Test
    fun disableCaptureProtection_withActivity_clearsFlagSecureAndReturnsTrue() {
        val plugin = SecureScreenPrivacyPlugin()
        val (_, mockWindow) = attachActivity(plugin)

        assertTrue(plugin.disableCaptureProtection())

        Mockito.verify(mockWindow).clearFlags(eq(WindowManager.LayoutParams.FLAG_SECURE))
    }

    @Test
    fun onAttachedToActivity_reappliesFlagSecure_whenCaptureProtectionPreviouslyEnabled() {
        val plugin = SecureScreenPrivacyPlugin()
        attachActivity(plugin)
        plugin.enableCaptureProtection()

        val newMockWindow = recreateActivity(plugin)

        Mockito.verify(newMockWindow).addFlags(eq(WindowManager.LayoutParams.FLAG_SECURE))
    }

    @Test
    fun onAttachedToActivity_reappliesFlagSecure_whenAppSwitcherProtectionPreviouslyEnabled() {
        val plugin = SecureScreenPrivacyPlugin()
        attachActivity(plugin)
        plugin.enableAppSwitcherProtection(colorOptions())

        val newMockWindow = recreateActivity(plugin)

        Mockito.verify(newMockWindow).addFlags(eq(WindowManager.LayoutParams.FLAG_SECURE))
    }

    @Test
    fun isCaptureProtectionEnabled_defaultsToFalse() {
        assertFalse(SecureScreenPrivacyPlugin().isCaptureProtectionEnabled())
    }

    @Test
    fun isCaptureProtectionEnabled_reflectsEnabledState() {
        val plugin = SecureScreenPrivacyPlugin()
        attachActivity(plugin)
        plugin.enableCaptureProtection()

        assertTrue(plugin.isCaptureProtectionEnabled())
    }

    // Returns both the mocked Activity and its mocked Window, so callers that
    // need to assert on window flag changes (app switcher protection tests
    // below) can do so, while callers that only care about the side effect
    // of attaching can ignore the return value.
    private fun attachActivity(plugin: SecureScreenPrivacyPlugin): Pair<Activity, Window> {
        val mockActivity = Mockito.mock(Activity::class.java)
        val mockWindow = Mockito.mock(Window::class.java)
        Mockito.`when`(mockActivity.window).thenReturn(mockWindow)
        val mockBinding = Mockito.mock(ActivityPluginBinding::class.java)
        Mockito.`when`(mockBinding.activity).thenReturn(mockActivity)
        plugin.onAttachedToActivity(mockBinding)
        return Pair(mockActivity, mockWindow)
    }

    // Simulates a config change recreating the Activity; returns the new
    // Activity's Window.
    private fun recreateActivity(plugin: SecureScreenPrivacyPlugin): Window {
        plugin.onDetachedFromActivityForConfigChanges()
        val newMockActivity = Mockito.mock(Activity::class.java)
        val newMockWindow = Mockito.mock(Window::class.java)
        Mockito.`when`(newMockActivity.window).thenReturn(newMockWindow)
        val newMockBinding = Mockito.mock(ActivityPluginBinding::class.java)
        Mockito.`when`(newMockBinding.activity).thenReturn(newMockActivity)
        plugin.onReattachedToActivityForConfigChanges(newMockBinding)
        return newMockWindow
    }

    private fun colorOptions(
        mode: AppSwitcherModeMessage = AppSwitcherModeMessage.COLOR,
    ) = AppSwitcherOptionsMessage(
        mode = mode,
        blurIntensity = BlurIntensityMessage.MEDIUM,
        color = 0xFF000000,
        imageBackgroundColor = 0xFF000000,
    )

    // App switcher protection on Android has no custom overlay - it's a thin
    // FLAG_SECURE toggle, kept on for the entire enabled lifetime (see the
    // "App switcher protection" comment in SecureScreenPrivacyPlugin.kt for
    // why: none of a custom overlay view, RenderEffect blur, or PixelCopy
    // capture protects the live gesture-nav "swipe up and hold" recents
    // peek, so there is nothing left for those techniques to add over
    // FLAG_SECURE alone).

    @Test
    fun enableAppSwitcherProtection_withNoActivity_isKeptAndAppliedOnAttach() {
        val plugin = SecureScreenPrivacyPlugin()

        assertTrue(plugin.enableAppSwitcherProtection(colorOptions()))
        assertTrue(plugin.isAppSwitcherProtectionEnabled())

        val (_, mockWindow) = attachActivity(plugin)
        Mockito.verify(mockWindow).addFlags(eq(WindowManager.LayoutParams.FLAG_SECURE))
    }

    @Test
    fun enableAppSwitcherProtection_withActivity_addsFlagSecureAndReturnsTrue() {
        val plugin = SecureScreenPrivacyPlugin()
        val (_, mockWindow) = attachActivity(plugin)

        // blurIntensity is accepted (matching the real Dart call shape) but
        // Android ignores it - only FLAG_SECURE is added, whatever is passed.
        assertTrue(plugin.enableAppSwitcherProtection(colorOptions()))

        Mockito.verify(mockWindow).addFlags(eq(WindowManager.LayoutParams.FLAG_SECURE))
    }

    @Test
    fun isAppSwitcherProtectionEnabled_defaultsToFalse() {
        assertFalse(SecureScreenPrivacyPlugin().isAppSwitcherProtectionEnabled())
    }

    @Test
    fun isAppSwitcherProtectionEnabled_reflectsEnabledState() {
        val plugin = SecureScreenPrivacyPlugin()
        attachActivity(plugin)
        plugin.enableAppSwitcherProtection(colorOptions())

        assertTrue(plugin.isAppSwitcherProtectionEnabled())
    }

    @Test
    fun disableAppSwitcherProtection_clearsFlagSecureAndReturnsTrue() {
        val plugin = SecureScreenPrivacyPlugin()
        val (_, mockWindow) = attachActivity(plugin)
        plugin.enableAppSwitcherProtection(colorOptions())

        assertTrue(plugin.disableAppSwitcherProtection())

        Mockito.verify(mockWindow).clearFlags(eq(WindowManager.LayoutParams.FLAG_SECURE))
        assertFalse(plugin.isAppSwitcherProtectionEnabled())
    }

    @Test
    fun disableAppSwitcherProtection_withCaptureProtectionEnabled_leavesFlagSecureOn() {
        val plugin = SecureScreenPrivacyPlugin()
        val (_, mockWindow) = attachActivity(plugin)
        plugin.enableCaptureProtection()
        plugin.enableAppSwitcherProtection(colorOptions())

        plugin.disableAppSwitcherProtection()

        Mockito.verify(mockWindow, Mockito.never()).clearFlags(eq(WindowManager.LayoutParams.FLAG_SECURE))
    }

    @Test
    fun disableCaptureProtection_withAppSwitcherProtectionEnabled_leavesFlagSecureOn() {
        val plugin = SecureScreenPrivacyPlugin()
        val (_, mockWindow) = attachActivity(plugin)
        plugin.enableAppSwitcherProtection(colorOptions())
        plugin.enableCaptureProtection()

        plugin.disableCaptureProtection()

        Mockito.verify(mockWindow, Mockito.never()).clearFlags(eq(WindowManager.LayoutParams.FLAG_SECURE))
        assertTrue(plugin.isAppSwitcherProtectionEnabled())
    }

    @Test
    fun appSwitcherModeName_matchesTheDartModeNames() {
        assertEquals("blur", appSwitcherModeName(AppSwitcherModeMessage.BLUR))
        assertEquals("image", appSwitcherModeName(AppSwitcherModeMessage.IMAGE))
        assertEquals("color", appSwitcherModeName(AppSwitcherModeMessage.COLOR))
        assertEquals("imageBlur", appSwitcherModeName(AppSwitcherModeMessage.IMAGE_BLUR))
    }

    // shouldEmitScreenshotEvent - the pure filter used by the screenshot
    // event stream (see handleMediaStoreChange) to decide whether a
    // MediaStore.Images change looks like a genuine screenshot. Extracted as
    // a pure function so it's testable here: registering the real
    // ContentObserver/HandlerThread/MediaStore constants it feeds from is
    // not - this project's plain-JUnit unit tests run against the stub
    // android.jar (no Robolectric, no returnDefaultValues), where real
    // framework bodies like Uri.parse (used internally by
    // MediaStore.Images.Media.EXTERNAL_CONTENT_URI) throw "Stub!" rather
    // than doing anything, and constructing a real Looper/HandlerThread is
    // similarly unsafe. That wiring is intentionally left to manual/example
    // app verification instead.

    @Test
    fun shouldEmitScreenshotEvent_matchingRelativePath_returnsTrue() {
        assertTrue(shouldEmitScreenshotEvent("IMG_001.png", "Pictures/Screenshots/", 1_000L, 1_500L))
    }

    @Test
    fun shouldEmitScreenshotEvent_matchingDisplayName_returnsTrue() {
        assertTrue(shouldEmitScreenshotEvent("Screenshot_20260710.png", null, 1_000L, 1_500L))
    }

    @Test
    fun shouldEmitScreenshotEvent_nonMatchingNameAndPath_returnsFalse() {
        assertFalse(shouldEmitScreenshotEvent("IMG_20260710.jpg", "DCIM/Camera/", 1_000L, 1_500L))
    }

    @Test
    fun shouldEmitScreenshotEvent_staleDateAdded_returnsFalse() {
        assertFalse(shouldEmitScreenshotEvent("Screenshot.png", null, 1_000L, 1_000L + 30_000L))
    }

    @Test
    fun shouldEmitScreenshotEvent_missingDateAdded_failsOpen() {
        assertTrue(shouldEmitScreenshotEvent(null, null, null, 1_500L))
    }

    @Test
    fun shouldEmitScreenshotEvent_missingNameAndPath_withFreshDate_failsOpen() {
        assertTrue(shouldEmitScreenshotEvent(null, null, 1_000L, 1_500L))
    }

    // screenRecordingRegistrationPathForSdkInt / isRecordingStateVisible -
    // pure functions backing the screen recording event stream. As with
    // shouldEmitScreenshotEvent above, the actual onListen/onCancel wiring
    // (WindowManager.addScreenRecordingCallback) needs a real
    // Activity/WindowManager and is not exercised here - covered by the
    // example app's integration test on an emulator instead.

    @Test
    fun screenRecordingRegistrationPathForSdkInt_belowApi34_returnsUnsupported() {
        assertEquals(ScreenRecordingRegistrationPath.UNSUPPORTED, screenRecordingRegistrationPathForSdkInt(24))
        assertEquals(ScreenRecordingRegistrationPath.UNSUPPORTED, screenRecordingRegistrationPathForSdkInt(33))
    }

    // Android 14 has no screen-recording signal: Activity.ScreenCaptureCallback
    // fires for screenshots, so using it here reported screenshots as
    // recordings.
    @Test
    fun screenRecordingRegistrationPathForSdkInt_api34_returnsUnsupported() {
        assertEquals(ScreenRecordingRegistrationPath.UNSUPPORTED, screenRecordingRegistrationPathForSdkInt(34))
    }

    @Test
    fun screenRecordingRegistrationPathForSdkInt_api35AndAbove_returnsWindowManagerCallback() {
        assertEquals(ScreenRecordingRegistrationPath.WINDOW_MANAGER_CALLBACK, screenRecordingRegistrationPathForSdkInt(35))
        assertEquals(ScreenRecordingRegistrationPath.WINDOW_MANAGER_CALLBACK, screenRecordingRegistrationPathForSdkInt(36))
    }

    @Test
    fun isRecordingStateVisible_visibleState_returnsTrue() {
        // WindowManager.SCREEN_RECORDING_STATE_VISIBLE is a plain
        // compile-time-constant Int field, inlined at compile time, so
        // referencing it here is safe even though it's an API-35 symbol -
        // unlike a real method call (e.g. Uri.parse), there's no runtime
        // "Stub!" risk for a constant field read.
        assertTrue(isRecordingStateVisible(WindowManager.SCREEN_RECORDING_STATE_VISIBLE))
    }

    @Test
    fun isRecordingStateVisible_notVisibleState_returnsFalse() {
        assertFalse(isRecordingStateVisible(WindowManager.SCREEN_RECORDING_STATE_NOT_VISIBLE))
    }

    @Test
    fun isRecordingStateVisible_arbitraryOtherState_returnsFalse() {
        assertFalse(isRecordingStateVisible(-1))
    }

    // Screenshot detection path selection / de-duplication / delete filter

    @Test
    fun screenshotDetectionPathForSdkInt_api34AndAbove_usesScreenCaptureCallback() {
        assertEquals(ScreenshotDetectionPath.ACTIVITY_SCREEN_CAPTURE_CALLBACK, screenshotDetectionPathForSdkInt(34))
        assertEquals(ScreenshotDetectionPath.ACTIVITY_SCREEN_CAPTURE_CALLBACK, screenshotDetectionPathForSdkInt(36))
    }

    @Test
    fun screenshotDetectionPathForSdkInt_belowApi34_usesMediaStoreObserver() {
        assertEquals(ScreenshotDetectionPath.MEDIA_STORE_OBSERVER, screenshotDetectionPathForSdkInt(33))
        assertEquals(ScreenshotDetectionPath.MEDIA_STORE_OBSERVER, screenshotDetectionPathForSdkInt(24))
    }

    @Test
    fun screenshotEventDeduper_firstEvent_isEmitted() {
        assertTrue(ScreenshotEventDeduper(1_500L).shouldEmit(10_000L))
    }

    @Test
    fun screenshotEventDeduper_burstWithinWindow_isCollapsedToOne() {
        val deduper = ScreenshotEventDeduper(1_500L)
        assertTrue(deduper.shouldEmit(10_000L)) // pending insert
        assertFalse(deduper.shouldEmit(10_200L)) // update once written
        assertFalse(deduper.shouldEmit(11_499L))
    }

    @Test
    fun screenshotEventDeduper_afterWindow_emitsAgain() {
        val deduper = ScreenshotEventDeduper(1_500L)
        assertTrue(deduper.shouldEmit(10_000L))
        assertTrue(deduper.shouldEmit(11_500L))
    }

    @Test
    fun screenshotEventDeduper_windowIsMeasuredFromLastEmit_notLastDrop() {
        val deduper = ScreenshotEventDeduper(1_500L)
        assertTrue(deduper.shouldEmit(10_000L))
        assertFalse(deduper.shouldEmit(11_000L))
        assertTrue(deduper.shouldEmit(11_600L))
    }

    @Test
    fun screenshotEventDeduper_clockGoingBackwards_emits() {
        val deduper = ScreenshotEventDeduper(1_500L)
        assertTrue(deduper.shouldEmit(10_000L))
        assertTrue(deduper.shouldEmit(9_000L))
    }

    @Test
    fun screenshotEventDeduper_reset_allowsImmediateEmit() {
        val deduper = ScreenshotEventDeduper(1_500L)
        assertTrue(deduper.shouldEmit(10_000L))
        deduper.reset()
        assertTrue(deduper.shouldEmit(10_100L))
    }

    @Test
    fun isMediaStoreChangeWorthChecking_deleteFlag_isSkipped() {
        assertFalse(isMediaStoreChangeWorthChecking(android.content.ContentResolver.NOTIFY_DELETE))
    }

    @Test
    fun isMediaStoreChangeWorthChecking_insertUpdateOrUnknown_isChecked() {
        assertTrue(isMediaStoreChangeWorthChecking(android.content.ContentResolver.NOTIFY_INSERT))
        assertTrue(isMediaStoreChangeWorthChecking(android.content.ContentResolver.NOTIFY_UPDATE))
        assertTrue(isMediaStoreChangeWorthChecking(0))
    }

    @Test
    fun screenRecordingStateDeduper_firstState_isEmitted() {
        assertTrue(ScreenRecordingStateDeduper().shouldEmit(false))
    }

    @Test
    fun screenRecordingStateDeduper_sameStateAgain_isDropped() {
        val deduper = ScreenRecordingStateDeduper()
        assertTrue(deduper.shouldEmit(true))
        assertFalse(deduper.shouldEmit(true))
        assertTrue(deduper.shouldEmit(false))
        assertFalse(deduper.shouldEmit(false))
    }

    @Test
    fun screenRecordingStateDeduper_unknownIsItsOwnState() {
        val deduper = ScreenRecordingStateDeduper()
        assertTrue(deduper.shouldEmit(null))
        assertFalse(deduper.shouldEmit(null))
        assertTrue(deduper.shouldEmit(false))
        assertTrue(deduper.shouldEmit(null))
    }

    @Test
    fun screenRecordingStateDeduper_reset_emitsTheSameStateAgain() {
        val deduper = ScreenRecordingStateDeduper()
        assertTrue(deduper.shouldEmit(true))
        deduper.reset()
        assertTrue(deduper.shouldEmit(true))
    }

    @Test
    fun isTaskBackgroundColorSupported_onlyFromAndroid13() {
        assertFalse(isTaskBackgroundColorSupported(32))
        assertTrue(isTaskBackgroundColorSupported(33))
        assertTrue(isTaskBackgroundColorSupported(37))
    }

    @Test
    fun appSwitcherCardColor_colorMode_usesTheChosenColor() {
        assertEquals(0xFF3F51B5.toInt(), appSwitcherCardColor("color", 0xFF3F51B5.toInt(), 0xFF000000.toInt(), 0xFFFFFFFF.toInt()))
    }

    @Test
    fun appSwitcherCardColor_imageMode_usesImageBackgroundColor() {
        assertEquals(0xFF00897B.toInt(), appSwitcherCardColor("image", 0xFF3F51B5.toInt(), 0xFF00897B.toInt(), 0xFFFFFFFF.toInt()))
    }

    @Test
    fun appSwitcherCardColor_blurModesAndCaptureOnly_useTheThemeColor() {
        val theme = 0xFF121212.toInt()
        assertEquals(theme, appSwitcherCardColor("blur", 0xFF3F51B5.toInt(), 0xFF00897B.toInt(), theme))
        assertEquals(theme, appSwitcherCardColor("imageBlur", 0xFF3F51B5.toInt(), 0xFF00897B.toInt(), theme))
        assertEquals(theme, appSwitcherCardColor(null, 0xFF3F51B5.toInt(), 0xFF00897B.toInt(), theme))
    }

    @Test
    fun appSwitcherCardColor_missingColor_fallsBackToTheTheme() {
        assertEquals(0xFFFFFFFF.toInt(), appSwitcherCardColor("color", null, null, 0xFFFFFFFF.toInt()))
    }

    @Test
    fun appSwitcherCardColor_translucentColor_isMadeOpaque() {
        assertEquals(0xFF3F51B5.toInt(), appSwitcherCardColor("color", 0x803F51B5.toInt(), null, 0))
    }

    @Test
    fun appSwitcherCardColor_noThemeColor_meansNoOverride() {
        assertEquals(0, appSwitcherCardColor("blur", null, null, 0))
    }

    @Test
    fun isOnScreenImportance_onlyWhenAnActivityIsInFrontOrVisible() {
        assertTrue(isOnScreenImportance(100)) // IMPORTANCE_FOREGROUND
        assertTrue(isOnScreenImportance(200)) // IMPORTANCE_VISIBLE
        assertFalse(isOnScreenImportance(125)) // IMPORTANCE_FOREGROUND_SERVICE
        assertFalse(isOnScreenImportance(325)) // IMPORTANCE_TOP_SLEEPING (screen off)
        assertFalse(isOnScreenImportance(400)) // IMPORTANCE_CACHED
        assertFalse(isOnScreenImportance(1000)) // IMPORTANCE_GONE
    }
}

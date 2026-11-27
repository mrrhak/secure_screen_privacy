package com.mrrhak.secure_screen_privacy

import android.app.Activity
import android.view.Window
import android.view.WindowManager
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
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
    fun onMethodCall_getPlatformVersion_returnsExpectedValue() {
        val plugin = SecureScreenPrivacyPlugin()

        val call = MethodCall("getPlatformVersion", null)
        val mockResult: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)
        plugin.onMethodCall(call, mockResult)

        Mockito.verify(mockResult).success("Android " + android.os.Build.VERSION.RELEASE)
    }

    @Test
    fun onMethodCall_enableCaptureProtection_withNoActivity_returnsFalse() {
        val plugin = SecureScreenPrivacyPlugin()

        val call = MethodCall("enableCaptureProtection", null)
        val mockResult: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)
        plugin.onMethodCall(call, mockResult)

        Mockito.verify(mockResult).success(false)
    }

    @Test
    fun onMethodCall_enableCaptureProtection_withActivity_addsFlagSecureAndReturnsTrue() {
        val plugin = SecureScreenPrivacyPlugin()
        val mockActivity = Mockito.mock(Activity::class.java)
        val mockWindow = Mockito.mock(Window::class.java)
        Mockito.`when`(mockActivity.window).thenReturn(mockWindow)
        val mockBinding = Mockito.mock(ActivityPluginBinding::class.java)
        Mockito.`when`(mockBinding.activity).thenReturn(mockActivity)
        plugin.onAttachedToActivity(mockBinding)

        val call = MethodCall("enableCaptureProtection", null)
        val mockResult: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)
        plugin.onMethodCall(call, mockResult)

        Mockito.verify(mockWindow).addFlags(eq(WindowManager.LayoutParams.FLAG_SECURE))
        Mockito.verify(mockResult).success(true)
    }

    @Test
    fun onMethodCall_disableCaptureProtection_withActivity_clearsFlagSecureAndReturnsTrue() {
        val plugin = SecureScreenPrivacyPlugin()
        val mockActivity = Mockito.mock(Activity::class.java)
        val mockWindow = Mockito.mock(Window::class.java)
        Mockito.`when`(mockActivity.window).thenReturn(mockWindow)
        val mockBinding = Mockito.mock(ActivityPluginBinding::class.java)
        Mockito.`when`(mockBinding.activity).thenReturn(mockActivity)
        plugin.onAttachedToActivity(mockBinding)

        val call = MethodCall("disableCaptureProtection", null)
        val mockResult: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)
        plugin.onMethodCall(call, mockResult)

        Mockito.verify(mockWindow).clearFlags(eq(WindowManager.LayoutParams.FLAG_SECURE))
        Mockito.verify(mockResult).success(true)
    }

    @Test
    fun onAttachedToActivity_reappliesFlagSecure_whenCaptureProtectionPreviouslyEnabled() {
        val plugin = SecureScreenPrivacyPlugin()
        val mockActivity = Mockito.mock(Activity::class.java)
        val mockWindow = Mockito.mock(Window::class.java)
        Mockito.`when`(mockActivity.window).thenReturn(mockWindow)
        val mockBinding = Mockito.mock(ActivityPluginBinding::class.java)
        Mockito.`when`(mockBinding.activity).thenReturn(mockActivity)
        plugin.onAttachedToActivity(mockBinding)
        plugin.onMethodCall(
            MethodCall("enableCaptureProtection", null),
            Mockito.mock(MethodChannel.Result::class.java)
        )

        // Simulate a config change recreating the Activity.
        plugin.onDetachedFromActivityForConfigChanges()
        val newMockActivity = Mockito.mock(Activity::class.java)
        val newMockWindow = Mockito.mock(Window::class.java)
        Mockito.`when`(newMockActivity.window).thenReturn(newMockWindow)
        val newMockBinding = Mockito.mock(ActivityPluginBinding::class.java)
        Mockito.`when`(newMockBinding.activity).thenReturn(newMockActivity)
        plugin.onReattachedToActivityForConfigChanges(newMockBinding)

        Mockito.verify(newMockWindow).addFlags(eq(WindowManager.LayoutParams.FLAG_SECURE))
    }

    @Test
    fun onAttachedToActivity_reappliesFlagSecure_whenAppSwitcherProtectionPreviouslyEnabled() {
        val plugin = SecureScreenPrivacyPlugin()
        attachActivity(plugin)
        plugin.onMethodCall(
            MethodCall("enableAppSwitcherProtection", mapOf("mode" to "color")),
            Mockito.mock(MethodChannel.Result::class.java)
        )

        // Simulate a config change recreating the Activity.
        plugin.onDetachedFromActivityForConfigChanges()
        val newMockActivity = Mockito.mock(Activity::class.java)
        val newMockWindow = Mockito.mock(Window::class.java)
        Mockito.`when`(newMockActivity.window).thenReturn(newMockWindow)
        val newMockBinding = Mockito.mock(ActivityPluginBinding::class.java)
        Mockito.`when`(newMockBinding.activity).thenReturn(newMockActivity)
        plugin.onReattachedToActivityForConfigChanges(newMockBinding)

        Mockito.verify(newMockWindow).addFlags(eq(WindowManager.LayoutParams.FLAG_SECURE))
    }

    @Test
    fun onMethodCall_isCaptureProtectionEnabled_defaultsToFalse() {
        val plugin = SecureScreenPrivacyPlugin()

        val call = MethodCall("isCaptureProtectionEnabled", null)
        val mockResult: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)
        plugin.onMethodCall(call, mockResult)

        Mockito.verify(mockResult).success(false)
    }

    @Test
    fun onMethodCall_isCaptureProtectionEnabled_reflectsEnabledState() {
        val plugin = SecureScreenPrivacyPlugin()
        val mockActivity = Mockito.mock(Activity::class.java)
        val mockWindow = Mockito.mock(Window::class.java)
        Mockito.`when`(mockActivity.window).thenReturn(mockWindow)
        val mockBinding = Mockito.mock(ActivityPluginBinding::class.java)
        Mockito.`when`(mockBinding.activity).thenReturn(mockActivity)
        plugin.onAttachedToActivity(mockBinding)
        plugin.onMethodCall(
            MethodCall("enableCaptureProtection", null),
            Mockito.mock(MethodChannel.Result::class.java)
        )

        val mockResult: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)
        plugin.onMethodCall(MethodCall("isCaptureProtectionEnabled", null), mockResult)

        Mockito.verify(mockResult).success(true)
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

    // App switcher protection on Android has no custom overlay - it's a thin
    // FLAG_SECURE toggle, kept on for the entire enabled lifetime (see the
    // "App switcher protection" comment in SecureScreenPrivacyPlugin.kt for
    // why: none of a custom overlay view, RenderEffect blur, or PixelCopy
    // capture protects the live gesture-nav "swipe up and hold" recents
    // peek, so there is nothing left for those techniques to add over
    // FLAG_SECURE alone).

    @Test
    fun onMethodCall_enableAppSwitcherProtection_withNoActivity_returnsFalse() {
        val plugin = SecureScreenPrivacyPlugin()

        val call = MethodCall("enableAppSwitcherProtection", mapOf("mode" to "color"))
        val mockResult: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)
        plugin.onMethodCall(call, mockResult)

        Mockito.verify(mockResult).success(false)
    }

    @Test
    fun onMethodCall_enableAppSwitcherProtection_withActivity_addsFlagSecureAndReturnsTrue() {
        val plugin = SecureScreenPrivacyPlugin()
        val (_, mockWindow) = attachActivity(plugin)

        // blurIntensity/color/imageBackgroundColor are accepted (matching the
        // real Dart call shape) but Android ignores them - this is verified
        // by the fact that no mode-specific rendering ever runs, only
        // FLAG_SECURE is added, regardless of which values are passed here.
        val call = MethodCall(
            "enableAppSwitcherProtection",
            mapOf("mode" to "color", "blurIntensity" to "medium", "color" to 0xFF000000)
        )
        val mockResult: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)
        plugin.onMethodCall(call, mockResult)

        Mockito.verify(mockWindow).addFlags(eq(WindowManager.LayoutParams.FLAG_SECURE))
        Mockito.verify(mockResult).success(true)
    }

    @Test
    fun onMethodCall_isAppSwitcherProtectionEnabled_defaultsToFalse() {
        val plugin = SecureScreenPrivacyPlugin()

        val call = MethodCall("isAppSwitcherProtectionEnabled", null)
        val mockResult: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)
        plugin.onMethodCall(call, mockResult)

        Mockito.verify(mockResult).success(false)
    }

    @Test
    fun onMethodCall_isAppSwitcherProtectionEnabled_reflectsEnabledState() {
        val plugin = SecureScreenPrivacyPlugin()
        attachActivity(plugin)
        plugin.onMethodCall(
            MethodCall("enableAppSwitcherProtection", mapOf("mode" to "color")),
            Mockito.mock(MethodChannel.Result::class.java)
        )

        val mockResult: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)
        plugin.onMethodCall(MethodCall("isAppSwitcherProtectionEnabled", null), mockResult)

        Mockito.verify(mockResult).success(true)
    }

    @Test
    fun onMethodCall_disableAppSwitcherProtection_clearsFlagSecureAndReturnsTrue() {
        val plugin = SecureScreenPrivacyPlugin()
        val (_, mockWindow) = attachActivity(plugin)
        plugin.onMethodCall(
            MethodCall("enableAppSwitcherProtection", mapOf("mode" to "color")),
            Mockito.mock(MethodChannel.Result::class.java)
        )

        val mockResult: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)
        plugin.onMethodCall(MethodCall("disableAppSwitcherProtection", null), mockResult)

        Mockito.verify(mockWindow).clearFlags(eq(WindowManager.LayoutParams.FLAG_SECURE))
        Mockito.verify(mockResult).success(true)

        val isEnabledResult: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)
        plugin.onMethodCall(MethodCall("isAppSwitcherProtectionEnabled", null), isEnabledResult)
        Mockito.verify(isEnabledResult).success(false)
    }

    @Test
    fun onMethodCall_disableAppSwitcherProtection_withCaptureProtectionEnabled_leavesFlagSecureOn() {
        val plugin = SecureScreenPrivacyPlugin()
        val (_, mockWindow) = attachActivity(plugin)
        plugin.onMethodCall(MethodCall("enableCaptureProtection", null), Mockito.mock(MethodChannel.Result::class.java))
        plugin.onMethodCall(
            MethodCall("enableAppSwitcherProtection", mapOf("mode" to "color")),
            Mockito.mock(MethodChannel.Result::class.java)
        )

        plugin.onMethodCall(MethodCall("disableAppSwitcherProtection", null), Mockito.mock(MethodChannel.Result::class.java))

        Mockito.verify(mockWindow, Mockito.never()).clearFlags(eq(WindowManager.LayoutParams.FLAG_SECURE))
    }

    @Test
    fun onMethodCall_disableCaptureProtection_withAppSwitcherProtectionEnabled_leavesFlagSecureOn() {
        val plugin = SecureScreenPrivacyPlugin()
        val (_, mockWindow) = attachActivity(plugin)
        plugin.onMethodCall(
            MethodCall("enableAppSwitcherProtection", mapOf("mode" to "color")),
            Mockito.mock(MethodChannel.Result::class.java)
        )
        plugin.onMethodCall(MethodCall("enableCaptureProtection", null), Mockito.mock(MethodChannel.Result::class.java))

        plugin.onMethodCall(MethodCall("disableCaptureProtection", null), Mockito.mock(MethodChannel.Result::class.java))

        Mockito.verify(mockWindow, Mockito.never()).clearFlags(eq(WindowManager.LayoutParams.FLAG_SECURE))

        val isEnabledResult: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)
        plugin.onMethodCall(MethodCall("isAppSwitcherProtectionEnabled", null), isEnabledResult)
        Mockito.verify(isEnabledResult).success(true)
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
    // (WindowManager.addScreenRecordingCallback, Activity.
    // registerScreenCaptureCallback) needs a real Activity/WindowManager and
    // is not exercised here - manual/example app verification only.

    @Test
    fun screenRecordingRegistrationPathForSdkInt_belowApi34_returnsUnsupported() {
        assertEquals(ScreenRecordingRegistrationPath.UNSUPPORTED, screenRecordingRegistrationPathForSdkInt(24))
        assertEquals(ScreenRecordingRegistrationPath.UNSUPPORTED, screenRecordingRegistrationPathForSdkInt(33))
    }

    @Test
    fun screenRecordingRegistrationPathForSdkInt_api34_returnsActivityScreenCaptureCallback() {
        assertEquals(
            ScreenRecordingRegistrationPath.ACTIVITY_SCREEN_CAPTURE_CALLBACK,
            screenRecordingRegistrationPathForSdkInt(34)
        )
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
}

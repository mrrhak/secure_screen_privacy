/// A single detected screenshot event.
///
/// Carries only a timestamp, no file path: on Android this avoids requiring
/// any storage/media read permission, and on iOS
/// `UIApplication.userDidTakeScreenshotNotification` provides no file path
/// at all, so a path field would always be null there.
class ScreenshotEvent {
  const ScreenshotEvent(this.timestamp);

  /// When the screenshot was detected, per the native platform's clock.
  final DateTime timestamp;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ScreenshotEvent &&
          runtimeType == other.runtimeType &&
          timestamp == other.timestamp;

  @override
  int get hashCode => timestamp.hashCode;
}

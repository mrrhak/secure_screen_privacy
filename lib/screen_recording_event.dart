/// A screen recording state transition.
///
/// See the README for platform-specific reliability caveats — in particular,
/// on Android 14 (API 34) [isRecording] can only ever be reported as `true`
/// (no OS "stopped" signal exists on that API level alone); cancelling and
/// re-subscribing to `screenRecordingEvents` is the only way to reset it.
class ScreenRecordingEvent {
  const ScreenRecordingEvent(this.isRecording, this.timestamp);

  /// Whether the screen is currently being recorded or mirrored.
  final bool isRecording;

  /// When this state was detected, per the native platform's clock.
  final DateTime timestamp;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ScreenRecordingEvent &&
          runtimeType == other.runtimeType &&
          isRecording == other.isRecording &&
          timestamp == other.timestamp;

  @override
  int get hashCode => Object.hash(isRecording, timestamp);
}

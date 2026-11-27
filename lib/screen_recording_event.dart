/// A screen recording state transition.
///
/// See the README for platform-specific caveats — in particular, Android
/// only reports recording on Android 15 (API 35) and newer; older versions
/// emit no events at all.
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

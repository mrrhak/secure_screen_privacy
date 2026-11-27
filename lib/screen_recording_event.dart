/// Whether the screen is being recorded, as far as the platform can tell.
enum ScreenRecordingState {
  /// The screen is being recorded or mirrored.
  recording,

  /// The screen is not being recorded or mirrored.
  notRecording,

  /// The platform can't tell. Sent once on subscribe on Android 14 (API 34)
  /// and below, which have no screen-recording signal, and on Android 15+
  /// when the host app removed the `DETECT_SCREEN_RECORDING` permission.
  /// No further events follow.
  unknown,
}

/// A screen recording state change.
///
/// See the README for platform-specific caveats: in particular, Android
/// only detects recording on Android 15 (API 35) and newer. Older versions
/// send a single [ScreenRecordingState.unknown] event on subscribe.
class ScreenRecordingEvent {
  const ScreenRecordingEvent(this.state, this.timestamp);

  /// Whether the screen is being recorded, not recorded, or unknown.
  final ScreenRecordingState state;

  /// True only when [state] is [ScreenRecordingState.recording]. False for
  /// both [ScreenRecordingState.notRecording] and
  /// [ScreenRecordingState.unknown]; check [state] to tell those apart.
  bool get isRecording => state == ScreenRecordingState.recording;

  /// When this state was detected, per the native platform's clock.
  final DateTime timestamp;

  @override
  String toString() =>
      'ScreenRecordingEvent(state: ${state.name}, timestamp: $timestamp)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ScreenRecordingEvent &&
          runtimeType == other.runtimeType &&
          state == other.state &&
          timestamp == other.timestamp;

  @override
  int get hashCode => Object.hash(state, timestamp);
}

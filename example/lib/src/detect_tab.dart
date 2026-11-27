import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:secure_screen_privacy/secure_screen_privacy.dart';

import 'background.dart';

/// Screenshot and screen recording detection, with one shared timeline.
class DetectTab extends StatefulWidget {
  const DetectTab({super.key, required this.plugin});

  final SecureScreenPrivacy plugin;

  @override
  State<DetectTab> createState() => _DetectTabState();
}

enum _EventKind { screenshot, recordingStarted, recordingStopped, unknown }

class _TimelineEntry {
  const _TimelineEntry(this.kind, this.time);

  final _EventKind kind;
  final DateTime time;
}

class _DetectTabState extends State<DetectTab> {
  // Subscribing to a stream starts native detection; cancelling stops it.
  // There is no separate start/stop method.
  StreamSubscription<ScreenshotEvent>? _screenshots;
  StreamSubscription<ScreenRecordingEvent>? _recordings;
  ScreenRecordingState? _recordingState;
  int _screenshotCount = 0;
  final List<_TimelineEntry> _timeline = [];

  static const _maxEntries = 30;

  @override
  void dispose() {
    _screenshots?.cancel();
    _recordings?.cancel();
    super.dispose();
  }

  void _add(_EventKind kind, DateTime time) {
    if (!mounted) return;
    setState(() {
      _timeline.insert(0, _TimelineEntry(kind, time));
      if (_timeline.length > _maxEntries) _timeline.removeLast();
    });
  }

  void _toggleScreenshots(bool listen) {
    if (listen) {
      _screenshots = widget.plugin.screenshotEvents.listen((event) {
        _screenshotCount++;
        _add(_EventKind.screenshot, event.timestamp);
      });
    } else {
      _screenshots?.cancel();
      _screenshots = null;
    }
    setState(() {});
  }

  void _toggleRecordings(bool listen) {
    if (listen) {
      _recordings = widget.plugin.screenRecordingEvents.listen((event) {
        setState(() => _recordingState = event.state);
        _add(switch (event.state) {
          ScreenRecordingState.recording => _EventKind.recordingStarted,
          ScreenRecordingState.notRecording => _EventKind.recordingStopped,
          ScreenRecordingState.unknown => _EventKind.unknown,
        }, event.timestamp);
      });
    } else {
      _recordings?.cancel();
      _recordings = null;
      _recordingState = null;
    }
    setState(() {});
  }

  String get _recordingSubtitle {
    if (_recordings == null) return 'Off';
    return switch (_recordingState) {
      ScreenRecordingState.recording => 'Recording now',
      ScreenRecordingState.notRecording => 'Not recording',
      ScreenRecordingState.unknown => "This device can't tell",
      null => 'Waiting for the first state...',
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isRecording = _recordingState == ScreenRecordingState.recording;
    return ListView(
      padding: const EdgeInsets.only(top: 8, bottom: 24),
      children: [
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionHeader(
                icon: Icons.photo_camera_outlined,
                title: 'Screenshots',
                subtitle: 'Get told when the user takes a screenshot.',
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Listen for screenshots'),
                subtitle: Text(
                  _screenshots == null
                      ? 'Off'
                      : 'Listening: $_screenshotCount so far',
                ),
                value: _screenshots != null,
                onChanged: _toggleScreenshots,
              ),
              const NoteBox(
                'Android 14+ reports screenshots of this app only. Android 13 '
                'and older watch new images, so a saved photo can also count. '
                'A screenshot is reported even when blocking is on.',
              ),
            ],
          ),
        ),
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionHeader(
                icon: Icons.videocam_outlined,
                title: 'Screen recording',
                subtitle:
                    'Get told when recording or mirroring starts and stops.',
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Listen for screen recording'),
                subtitle: Text(_recordingSubtitle),
                secondary: _recordings == null
                    ? null
                    : Icon(
                        isRecording
                            ? Icons.fiber_manual_record
                            : Icons.stop_circle_outlined,
                        color: isRecording ? Colors.red : null,
                      ),
                value: _recordings != null,
                onChanged: _toggleRecordings,
              ),
              const NoteBox(
                'Needs Android 15 or newer. Older Android versions send one '
                '"can\'t tell" event. The current state is sent as soon as '
                'you start listening, then only when it changes.',
              ),
            ],
          ),
        ),
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: SectionHeader(
                      icon: Icons.timeline,
                      title: 'Timeline',
                      subtitle: _timeline.isEmpty
                          ? 'Turn on a listener, then take a screenshot or '
                                'start a recording.'
                          : '${_timeline.length} events, newest first',
                    ),
                  ),
                  if (_timeline.isNotEmpty)
                    TextButton(
                      onPressed: () => setState(_timeline.clear),
                      child: const Text('Clear'),
                    ),
                ],
              ),
              for (final entry in _timeline)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: CircleAvatar(
                    radius: 18,
                    backgroundColor: _colorFor(
                      entry.kind,
                    ).withValues(alpha: 0.15),
                    child: Icon(
                      _iconFor(entry.kind),
                      size: 18,
                      color: _colorFor(entry.kind),
                    ),
                  ),
                  title: Text(_labelFor(entry.kind)),
                  trailing: Text(
                    _formatTime(entry.time),
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  static IconData _iconFor(_EventKind kind) => switch (kind) {
    _EventKind.screenshot => Icons.photo_camera,
    _EventKind.recordingStarted => Icons.fiber_manual_record,
    _EventKind.recordingStopped => Icons.stop,
    _EventKind.unknown => Icons.help_outline,
  };

  static Color _colorFor(_EventKind kind) => switch (kind) {
    _EventKind.screenshot => Colors.indigo,
    _EventKind.recordingStarted => Colors.red,
    _EventKind.recordingStopped => Colors.teal,
    _EventKind.unknown => Colors.grey,
  };

  static String _labelFor(_EventKind kind) => switch (kind) {
    _EventKind.screenshot => 'Screenshot taken',
    _EventKind.recordingStarted => 'Recording started',
    _EventKind.recordingStopped => 'Recording stopped',
    _EventKind.unknown => "Recording state: can't tell",
  };

  static String _formatTime(DateTime time) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
  }
}

/// Visual style shown in the OS app switcher / recent preview while
/// app switcher protection is enabled.
enum AppSwitcherProtectionMode {
  /// Blurs a snapshot of the current screen.
  blur,

  /// Shows a static image supplied by the host app, on
  /// `imageBackgroundColor`. Without the image asset it shows just that
  /// color.
  image,

  /// Shows a solid color.
  color,

  /// Shows a static image supplied by the host app over a live blur of the
  /// current screen. Without the image asset it shows just the blur.
  imageBlur,
}

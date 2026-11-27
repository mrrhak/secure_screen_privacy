/// Visual style shown in the OS app switcher / recent preview while
/// app switcher protection is enabled.
enum AppSwitcherProtectionMode {
  /// Blurs a snapshot of the current screen.
  blur,

  /// Shows a static image supplied by the host app.
  image,

  /// Shows a solid color.
  color,

  /// Shows a static image supplied by the host app over a live blurred
  /// snapshot of the current screen, falling back to [imageBackgroundColor]
  /// wherever the blur isn't ready yet or isn't available at all.
  imageBlur,
}

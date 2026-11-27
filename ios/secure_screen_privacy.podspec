Pod::Spec.new do |s|
  s.name             = 'secure_screen_privacy'
  s.version          = '0.0.1'
  s.summary          = 'Capture protection and app switcher/recents privacy overlays.'
  s.description      = <<-DESC
Flutter plugin for capture protection (block screenshots/recording) and app
switcher/recents privacy overlays on iOS.
                       DESC
  s.homepage         = 'https://github.com/mrrhak/secure_screen_privacy'
  s.license          = { :file => '../LICENSE' }
  s.author           = 'Mrr Hak'
  s.source           = { :path => '.' }
  s.source_files = 'secure_screen_privacy/Sources/secure_screen_privacy/**/*.swift'
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'

  # Privacy manifest: declares ProcessInfo.systemUptime (screenshot dedupe).
  s.resource_bundles = {'secure_screen_privacy_privacy' => ['secure_screen_privacy/Sources/secure_screen_privacy/PrivacyInfo.xcprivacy']}
end

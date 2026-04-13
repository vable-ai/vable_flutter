#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint vable_flutter.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'vable_flutter'
  s.version          = '0.0.1'
  s.summary          = 'Vable AI Flutter plugin for iOS and Android'
  s.description      = <<-DESC
Flutter plugin for Vable AI SDK - provides real-time AI voice chat with context-aware capabilities.
                       DESC
  s.homepage         = 'https://vable.ai'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Vable AI' => 'support@vable.ai' }
  s.source           = { :path => '.' }
  s.source_files = 'Sources/vable_flutter/**/*.swift'
  s.dependency 'Flutter'
  s.dependency 'VableAI', '>= 0.0.1'
  s.platform = :ios, '13.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
    # Point directly at the xcframework slices so the VableAI module is resolvable
    # at compile time. PODS_ROOT is defined in every pod xcconfig; PODS_XCFRAMEWORKS_BUILD_DIR
    # is only in the aggregate app xcconfig and cannot be used here.
    'FRAMEWORK_SEARCH_PATHS' => '$(inherited) $(PODS_ROOT)/VableAI/VableAI.xcframework/ios-arm64 $(PODS_ROOT)/VableAI/VableAI.xcframework/ios-arm64_x86_64-simulator'
  }
  s.swift_version = '5.0'

  # If your plugin requires a privacy manifest, for example if it uses any
  # required reason APIs, update the PrivacyInfo.xcprivacy file to describe your
  # plugin's privacy impact, and then uncomment this line. For more information,
  # see https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
  # s.resource_bundles = {'vable_flutter_privacy' => ['Resources/PrivacyInfo.xcprivacy']}
end
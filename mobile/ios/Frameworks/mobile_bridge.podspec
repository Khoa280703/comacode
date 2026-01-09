Pod::Spec.new do |s|
  s.name             = 'mobile_bridge'
  s.version          = '0.1.0'
  s.summary          = 'Rust FFI bridge for Comacode mobile'
  s.homepage         = 'https://github.com/comacode/comacode'
  s.license          = { :type => 'MIT' }
  s.author           = { 'Comacode Team' => 'dev@comacode.com' }
  s.source           = { :path => '.' }
  s.ios.deployment_target = '13.0'

  # Static library - force load all symbols at link time
  s.vendored_libraries = 'mobile_bridge.framework/mobile_bridge'
  s.xcconfig = { 'OTHER_LDFLAGS' => '-force_load $(PODS_ROOT)/mobile_bridge/mobile_bridge.framework/mobile_bridge' }

  # Public headers (empty for FFI-only)
  s.public_header_files = 'mobile_bridge.framework/Headers/*.h'
end

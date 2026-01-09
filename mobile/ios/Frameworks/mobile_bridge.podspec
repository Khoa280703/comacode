Pod::Spec.new do |s|
  s.name             = 'mobile_bridge'
  s.version          = '0.1.0'
  s.summary          = 'Rust FFI bridge for Comacode mobile'
  s.homepage         = 'https://github.com/comacode/comacode'
  s.license          = { :type => 'MIT' }
  s.author           = { 'Comacode Team' => 'dev@comacode.com' }
  s.source           = { :path => '.' }
  s.ios.deployment_target = '13.0'

  s.vendored_frameworks = 'mobile_bridge.framework'
end

require 'json'

package = JSON.parse(File.read(File.join(__dir__, 'package.json')))

Pod::Spec.new do |s|
  s.name         = package['name'].split('/')[1..-1].join('/')
  s.version      = package['version']
  s.summary      = package['description']
  s.description  = package['description']
  s.homepage     = package['repository']['url']
  s.license      = package['license']
  s.platform     = :ios, '13.4'
  s.author       = package['author']
  s.source       = { git: 'https://github.com/kesha-antonov/react-native-background-downloader.git', tag: 'main' }

  s.source_files = 'ios/**/*.{h,m,mm,swift}'
  # React Native Core dependency
  install_modules_dependencies(s)

  s.dependency 'MMKV', '>= 2.1.0'
  
  # C++ standard library settings for new architecture
  s.pod_target_xcconfig = {
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17',
    'CLANG_CXX_LIBRARY' => 'libc++',
    'OTHER_CFLAGS' => '$(inherited) -std=gnu++17 -x objective-c++',
    'OTHER_CPLUSPLUSFLAGS' => '$(inherited) -std=gnu++17 -DFOLLY_NO_CONFIG -DFOLLY_MOBILE=1 -DFOLLY_USE_LIBCPP=1',
    'HEADER_SEARCH_PATHS' => '$(inherited)'
  }
  
  # Ensure C++ files are compiled properly
  s.requires_arc = true
end

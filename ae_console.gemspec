# coding: utf-8
lib = File.expand_path('../src', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'ae_console/version'

Gem::Specification.new do |spec|
  spec.name          = 'ae_console'
  spec.version       = AE::ConsolePlugin::VERSION
  spec.authors       = ['Andreas Eisenbarth']
  spec.email         = ['aerilius@gmail.com']

  spec.summary       = %q{A better Ruby Console and IDE for integrated development in SketchUp.}
  spec.description   = %q{This is a powerful Ruby Console with IDE features like code highlighting, autocompletion and a code editor. It lets you open multiple independent instances of the console and remembers the command history over sessions.}
  spec.homepage      = 'https://github.com/Aerilius/sketchup-console-plus/.'
  spec.license       = 'MIT'

  # Prevent pushing this gem to RubyGems.org. To allow pushes either set the 'allowed_push_host'
  # to allow pushing to a single host or delete this section to allow pushing to any host.
  if spec.respond_to?(:metadata)
    spec.metadata['allowed_push_host'] = "TODO: Set to 'http://mygemserver.com'"
  else
    raise 'RubyGems 2.0 or newer is required to protect against public gem pushes.'
  end

  spec.files         = `git ls-files -z`.split("\x0").reject{ |f|
    f.match(%r{^(test|spec|features)/}) || !File.exist?(f)
  }
  spec.bindir        = 'exe'
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ['src']

  spec.add_development_dependency 'bundler', '~> 1.13'
  spec.add_development_dependency 'rake', '~> 10.0'
  spec.add_development_dependency 'minitest', '~> 5.0'
  spec.add_development_dependency 'sketchup-api-stubs', '~> 0'
  spec.add_development_dependency 'rubyzip', '>= 1.0.0'
end

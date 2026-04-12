# frozen_string_literal: true

require_relative 'lib/keep_alive/version'

Gem::Specification.new do |spec|
  spec.name          = 'keep_alive'
  spec.version       = KeepAlive::VERSION
  spec.authors       = ['Vitalii Lazebnyi']
  spec.email         = ['author@example.com']

  spec.summary       = 'Keep-Alive High Concurrency Load Testing Framework'
  spec.description   = 'A performance testing tool for HTTP/HTTPS.'
  spec.homepage      = 'https://github.com/VitaliiLazebnyi/keep-alive'
  spec.required_ruby_version = '>= 4.0'

  spec.metadata['allowed_push_host'] = 'https://rubygems.org'
  spec.metadata['source_code_uri']   = spec.homepage

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").reject do |f|
      (f == __FILE__) ||
        f.match(%r{\A(?:spec/|\.git)})
    end
  end
  spec.bindir        = 'bin'
  spec.executables   = ['keep_alive']
  spec.require_paths = ['lib']

  spec.add_dependency 'async', '~> 2.39'
  spec.add_dependency 'async-http', '~> 0.95'
  spec.add_dependency 'falcon', '~> 0.55'
  spec.add_dependency 'rack', '~> 3.2'
  spec.add_dependency 'rackup', '~> 2.3'
  spec.add_dependency 'sorbet-runtime', '~> 0.6'

  spec.add_development_dependency 'memory_profiler', '~> 1.1'
  spec.add_development_dependency 'rake', '~> 13.3'
  spec.add_development_dependency 'rspec', '~> 3.13'
  spec.add_development_dependency 'rubocop', '~> 1.86'
  spec.add_development_dependency 'rubocop-md', '~> 2.0'
  spec.add_development_dependency 'rubocop-performance', '~> 1.26'
  spec.add_development_dependency 'rubocop-rake', '~> 0.7'
  spec.add_development_dependency 'rubocop-rspec', '~> 3.9'
  spec.add_development_dependency 'rubocop-thread_safety', '~> 0.7'
  spec.add_development_dependency 'ruby-prof', '~> 2.0'
  spec.add_development_dependency 'simplecov', '~> 0.22'
  spec.add_development_dependency 'sorbet', '~> 0.6'
end

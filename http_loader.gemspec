# frozen_string_literal: true

require_relative 'lib/http_loader/version'

Gem::Specification.new do |spec|
  spec.name          = 'http_loader'
  spec.version       = HttpLoader::VERSION
  spec.authors       = ['Vitalii Lazebnyi']
  spec.email         = ['vitalii.lazebnyi.github@gmail.com']

  spec.summary       = 'Keep-Alive High Concurrency Load Testing Framework'
  spec.description   = 'A performance testing tool for HTTP/HTTPS.'
  spec.homepage      = 'https://github.com/VitaliiLazebnyi/http_loader'
  spec.license       = 'MIT'
  spec.required_ruby_version = '>= 4.0'
  spec.metadata['allowed_push_host']     = 'https://rubygems.org'
  spec.metadata['source_code_uri']       = 'https://github.com/VitaliiLazebnyi/http_loader'
  spec.metadata['bug_tracker_uri']       = 'https://github.com/VitaliiLazebnyi/http_loader/issues'
  spec.metadata['changelog_uri']         = 'https://github.com/VitaliiLazebnyi/http_loader/blob/main/CHANGELOG.md'
  spec.metadata['rubygems_mfa_required'] = 'true'

  spec.cert_chain  = ['certs/http_loader-public_cert.pem']
  spec.signing_key = File.expand_path('~/.gem/gem-private_key.pem') if $PROGRAM_NAME.end_with?('gem')

  spec.files = %w[
    BUGS.md
    Gemfile
    LICENSE.txt
    PERFORMANCE_REPORT.md
    README.md
    REQUIREMENTS.md
    http_loader.gemspec
  ] + Dir.glob('{lib,bin,certs}/**/*', base: __dir__).select do |f|
    File.file?(File.expand_path(f, __dir__))
  end
  spec.bindir        = 'bin'
  spec.executables   = ['http_loader']
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
  spec.add_development_dependency 'yard', '~> 0.9'
  spec.add_development_dependency 'yard-sorbet', '~> 0.8'
end

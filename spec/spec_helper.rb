# typed: false
# frozen_string_literal: true

require 'simplecov'
SimpleCov.start do
  add_filter '/spec/'
  enable_coverage :branch
end

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))
require 'http_loader/server'
require 'http_loader/client'
require 'http_loader/harness'

Dir[File.join(__dir__, 'support', '**', '*.rb')].each { |f| require f }

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
end
require 'sorbet-runtime'
T::Configuration.inline_type_error_handler = ->(_, _) {}
T::Configuration.call_validation_error_handler = ->(_, _) {}

# typed: true
# frozen_string_literal: true

require 'http_loader/client/config'
require 'http_loader/harness/config'

module ConfigHelpers
  def build_client(**)
    HttpLoader::Client.new(HttpLoader::Client::Config.new(**))
  end

  def build_harness(**)
    HttpLoader::Harness.new(HttpLoader::Harness::Config.new(**))
  end
end

RSpec.configure do |config|
  config.include ConfigHelpers
end

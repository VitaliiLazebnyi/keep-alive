# typed: strong
# frozen_string_literal: true

require 'sorbet-runtime'
require_relative 'keep_alive/version'
require_relative 'keep_alive/server'
require_relative 'keep_alive/client'
require_relative 'keep_alive/harness'

# KeepAlive is the main namespace for the high-concurrency Ruby load testing framework.
module KeepAlive
end

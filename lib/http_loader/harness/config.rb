# typed: strong
# frozen_string_literal: true

require 'sorbet-runtime'

module KeepAlive
  class Harness
    # Config parameters for Harness manager execution natively.
    class Config < T::Struct
      const :connections, Integer
      const :target_urls, T::Array[String], default: []
      const :use_https, T::Boolean, default: false
      const :client_args, T::Array[String], default: []
      const :export_json, T.nilable(String), default: nil
      const :target_duration, Float, default: 0.0
    end
  end
end

# typed: strong
# frozen_string_literal: true

require 'sorbet-runtime'

module KeepAlive
  class Client
    # Config parameters for Client connections.
    class Config < T::Struct
      const :connections, Integer
      const :target_urls, T::Array[String], default: []
      const :use_https, T::Boolean, default: false
      const :verbose, T::Boolean, default: false
      const :ping, T::Boolean, default: true
      const :ping_period, Integer, default: 5
      const :keep_alive_timeout, Float, default: 0.0
      const :connections_per_second, Integer, default: 0
      const :max_concurrent_connections, Integer, default: 1000
      const :reopen_closed_connections, T::Boolean, default: false
      const :reopen_interval, Float, default: 5.0
      const :read_timeout, Float, default: 0.0
      const :user_agent, String, default: 'Keep-Alive Test'
      const :jitter, Float, default: 1.0
      const :track_status_codes, T::Boolean, default: false
      const :ramp_up, Float, default: 0.0
      const :bind_ips, T::Array[String], default: []
      const :proxy_pool, T::Array[String], default: []
      const :qps_per_connection, Integer, default: 0
      const :headers, T::Hash[String, String], default: {}
      const :slowloris_delay, Float, default: 0.0
    end
  end
end

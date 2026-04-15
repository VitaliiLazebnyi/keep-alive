# typed: false
# frozen_string_literal: true

require 'sorbet-runtime'

module KeepAlive
  # Extracted arguments parsers for strict metric compliance.
  module CliArgs
    # ClientParser configures OptionParser mapping specifically for Client configurations
    class ClientParser
      def self.parse(opts, options)
        parse_core(opts, options)
        parse_ping(opts, options)
        parse_timeouts(opts, options)
      end

      def self.parse_core(opts, options)
        opts.on('--connections_count=COUNT', Integer, 'Total') { |v| options[:connections] = v }
        opts.on('--https', 'Use HTTPS natively') { options[:use_https] = true }
        opts.on('--url=URL', String, 'URLs') { |v| options[:target_urls] = v.split(',') }
        opts.on('--verbose', 'Verbose logging') { options[:verbose] = true }
      end

      def self.parse_ping(opts, options)
        opts.on('--[no-]ping', 'Ping') { |v| options[:ping] = v }
        opts.on('--ping_period=SECONDS', Integer, 'Ping period') { |v| options[:ping_period] = v }
      end

      def self.parse_timeouts(opts, options)
        opts.on('--keep_alive_timeout=S', Float, 'Keep') { |v| options[:keep_alive_timeout] = v }
        opts.on('--connections_per_second=R', Integer, 'Rate') { |v| options[:connections_per_second] = v }
        opts.on('--max_concurrent_connections=C', Integer, 'Max') { |v| options[:max_concurrent_connections] = v }
        parse_advanced(opts, options)
      end

      def self.parse_advanced(opts, options)
        opts.on('--reopen_closed_connections', 'Reopen') { options[:reopen_closed_connections] = true }
        opts.on('--reopen_interval=S', Float, 'Reopen delay') { |v| options[:reopen_interval] = v }
        opts.on('--read_timeout=S', Float, 'Read timeout') { |v| options[:read_timeout] = v }
        parse_tracking(opts, options)
      end

      def self.parse_tracking(opts, options)
        opts.on('--user_agent=A', String, 'User Agent') { |v| options[:user_agent] = v }
        opts.on('--jitter=F', Float, 'Randomize sleep') { |v| options[:jitter] = v }
        opts.on('--track_status_codes', 'Track HTTP codes') { options[:track_status_codes] = true }
        parse_endpoints(opts, options)
      end

      def self.parse_endpoints(opts, options)
        opts.on('--ramp_up=S', Float, 'Smoothly scale') { |val| options[:ramp_up] = val }
        opts.on('--bind_ips=IPS', String, 'IPs') { |val| options[:bind_ips] = val.split(',') }
        opts.on('--proxy_pool=U', String, 'URI pool') { |val| options[:proxy_pool] = val.split(',') }
        parse_slowloris(opts, options)
      end

      def self.parse_slowloris(opts, options)
        opts.on('--qps_per_connection=R', Integer, 'Active QPS') { |val| options[:qps_per_connection] = val }
        opts.on('--headers=LIST', String, 'Headers') do |val|
          val.split(',').each do |pair|
            key, value = pair.split(':', 2)
            options[:headers][key.strip] = value.strip if key && value
          end
        end
        parse_slowloris_delays(opts, options)
      end

      def self.parse_slowloris_delays(opts, options)
        opts.on('--slowloris_delay=S', Float, 'Gap') { |v| options[:slowloris_delay] = v }
        opts.on('--export_json=FILE', String) { nil }
        opts.on('--target_duration=S', Float) { nil }
      end
    end

    # HarnessParser strictly parses orchestrator arguments ignoring explicitly mapped client arguments dynamically.
    class HarnessParser
      def self.parse(opts, options)
        opts.on('--connections_count=C', Integer) { |v| options[:connections] = v }
        opts.on('--https') { options[:use_https] = true }
        opts.on('--url=URL', String) { |v| options[:target_urls] = v.split(',') }
        opts.on('--export_json=FILE', String) { |v| options[:export_json] = v }
        opts.on('--target_duration=S', Float) { |v| options[:target_duration] = v }
        ignore_core_args(opts)
      end

      def self.ignore_core_args(opts)
        opts.on('--verbose') { nil }
        opts.on('--[no-]ping') { nil }
        opts.on('--ping_period=S', Integer) { nil }
        opts.on('--keep_alive_timeout=S', Float) { nil }
        opts.on('--connections_per_second=R', Integer) { nil }
        ignore_time_args(opts)
      end

      def self.ignore_time_args(opts)
        opts.on('--max_concurrent_connections=C', Integer) { nil }
        opts.on('--reopen_closed_connections') { nil }
        opts.on('--reopen_interval=S', Float) { nil }
        opts.on('--read_timeout=S', Float) { nil }
        opts.on('--user_agent=A', String) { nil }
        ignore_advanced_args(opts)
      end

      def self.ignore_advanced_args(opts)
        opts.on('--jitter=F', Float) { nil }
        opts.on('--track_status_codes') { nil }
        opts.on('--ramp_up=S', Float) { nil }
        opts.on('--bind_ips=IPS', String) { nil }
        opts.on('--proxy_pool=U', String) { nil }
        ignore_payload_args(opts)
      end

      def self.ignore_payload_args(opts)
        opts.on('--qps_per_connection=R', Integer) { nil }
        opts.on('--headers=LIST', String) { nil }
        opts.on('--slowloris_delay=S', Float) { nil }
      end
    end
  end
end

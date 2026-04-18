# typed: strong
# frozen_string_literal: true

require 'sorbet-runtime'
require 'optparse'

# Primary namespace for the load testing framework.
module HttpLoader
  # Extracted arguments parsers for strict metric compliance.
  module CliArgs
    # ClientParser configures OptionParser mapping specifically for Client configurations
    class ClientParser
      extend T::Sig

      # Orchestrator to parse all client-specific options in sequence.
      #
      # @param opts [OptionParser] the active parser instance
      # @param options [Hash] the configuration map to populate
      # @return [void]
      sig { params(opts: OptionParser, options: T::Hash[Symbol, Object]).void }
      def self.parse(opts, options)
        parse_core(opts, options)
        parse_ping(opts, options)
        parse_timeouts(opts, options)
        nil
      end

      # Parses core connectivity and URL parameters.
      #
      # @param opts [OptionParser] the active parser instance
      # @param options [Hash] the configuration map to populate
      # @return [void]
      sig { params(opts: OptionParser, options: T::Hash[Symbol, Object]).void }
      def self.parse_core(opts, options)
        opts.on('--connections_count=COUNT', Integer, 'Total') { |v| options[:connections] = T.cast(v, Integer) }
        opts.on('--https', 'Use HTTPS natively') { options[:use_https] = true }
        opts.on('--url=URL', String, 'URLs') { |v| options[:target_urls] = T.cast(v, String).split(',') }
        opts.on('--verbose', 'Verbose logging') { options[:verbose] = true }
        nil
      end

      # Parses ping enablement and intervals.
      #
      # @param opts [OptionParser] the active parser instance
      # @param options [Hash] the configuration map to populate
      # @return [void]
      sig { params(opts: OptionParser, options: T::Hash[Symbol, Object]).void }
      def self.parse_ping(opts, options)
        opts.on('--[no-]ping', 'Ping') { |v| options[:ping] = T.cast(v, T::Boolean) }
        opts.on('--ping_period=SECONDS', Integer, 'Ping period') { |v| options[:ping_period] = T.cast(v, Integer) }
        nil
      end

      # Parses timeout, rate-limiting, and concurrency thresholds.
      #
      # @param opts [OptionParser] the active parser instance
      # @param options [Hash] the configuration map to populate
      # @return [void]
      sig { params(opts: OptionParser, options: T::Hash[Symbol, Object]).void }
      def self.parse_timeouts(opts, options)
        opts.on('--http_loader_timeout=S', Float, 'Keep') { |v| options[:http_loader_timeout] = T.cast(v, Float) }
        opts.on('--connections_per_second=R', Integer, 'Rate') { |v| options[:connections_per_second] = T.cast(v, Integer) }
        opts.on('--max_concurrent_connections=C', Integer, 'Max') { |v| options[:max_concurrent_connections] = T.cast(v, Integer) }
        parse_advanced(opts, options)
        nil
      end

      # Parses advanced connection lifecycle controls like reopen logic.
      #
      # @param opts [OptionParser] the active parser instance
      # @param options [Hash] the configuration map to populate
      # @return [void]
      sig { params(opts: OptionParser, options: T::Hash[Symbol, Object]).void }
      def self.parse_advanced(opts, options)
        opts.on('--reopen_closed_connections', 'Reopen') { options[:reopen_closed_connections] = true }
        opts.on('--reopen_interval=S', Float, 'Reopen delay') { |v| options[:reopen_interval] = T.cast(v, Float) }
        opts.on('--read_timeout=S', Float, 'Read timeout') { |v| options[:read_timeout] = T.cast(v, Float) }
        parse_tracking(opts, options)
        nil
      end

      # Parses tracking and obfuscation parameters like jitter and user agents.
      #
      # @param opts [OptionParser] the active parser instance
      # @param options [Hash] the configuration map to populate
      # @return [void]
      sig { params(opts: OptionParser, options: T::Hash[Symbol, Object]).void }
      def self.parse_tracking(opts, options)
        opts.on('--user_agent=A', String, 'User Agent') { |v| options[:user_agent] = T.cast(v, String) }
        opts.on('--jitter=F', Float, 'Randomize sleep') { |v| options[:jitter] = T.cast(v, Float) }
        opts.on('--track_status_codes', 'Track HTTP codes') { options[:track_status_codes] = true }
        parse_endpoints(opts, options)
        nil
      end

      # Parses IP binding, proxying, and ramp-up behavior.
      #
      # @param opts [OptionParser] the active parser instance
      # @param options [Hash] the configuration map to populate
      # @return [void]
      sig { params(opts: OptionParser, options: T::Hash[Symbol, Object]).void }
      def self.parse_endpoints(opts, options)
        opts.on('--ramp_up=S', Float, 'Smoothly scale') { |v| options[:ramp_up] = T.cast(v, Float) }
        opts.on('--bind_ips=IPS', String, 'IPs') { |v| options[:bind_ips] = T.cast(v, String).split(',') }
        opts.on('--proxy_pool=U', String, 'URI pool') { |v| options[:proxy_pool] = T.cast(v, String).split(',') }
        parse_slowloris(opts, options)
        nil
      end

      # Parses parameters triggering the slowloris strategy.
      #
      # @param opts [OptionParser] the active parser instance
      # @param options [Hash] the configuration map to populate
      # @return [void]
      sig { params(opts: OptionParser, options: T::Hash[Symbol, Object]).void }
      def self.parse_slowloris(opts, options)
        opts.on('--qps_per_connection=R', Integer, 'QPS') { |v| options[:qps_per_connection] = T.cast(v, Integer) }
        opts.on('--headers=L', String, 'Headers') { |v| parse_headers(T.cast(v, String), options) }
        parse_slowloris_delays(opts, options)
        nil
      end

      # Parses individual headers.
      #
      # @param val [String] the headers list string
      # @param options [Hash] the configuration map to populate
      # @return [void]
      sig { params(val: String, options: T::Hash[Symbol, Object]).void }
      def self.parse_headers(val, options)
        val.split(',').each do |pair|
          k, v = pair.split(':', 2)
          headers = T.cast(options[:headers], T::Hash[String, String])
          headers[k.strip] = v.strip if k && v
        end
      end

      # Parses granular delay configs specifically for slowloris payloads.
      #
      # @param opts [OptionParser] the active parser instance
      # @param options [Hash] the configuration map to populate
      # @return [void]
      sig { params(opts: OptionParser, options: T::Hash[Symbol, Object]).void }
      def self.parse_slowloris_delays(opts, options)
        opts.on('--slowloris_delay=S', Float, 'Gap') do |v|
          options[:slowloris_delay] = T.cast(v, Float)
        end
        opts.on('--export_json=FILE', String) { nil }
        opts.on('--target_duration=S', Float) { nil }
        nil
      end
    end

    # HarnessParser strictly parses orchestrator arguments ignoring explicitly mapped client arguments dynamically.
    class HarnessParser
      extend T::Sig

      # Orchestrator to parse harness structural args while ignoring client ones.
      #
      # @param opts [OptionParser] the active parser instance
      # @param options [Hash] the configuration map to populate
      # @return [void]
      sig { params(opts: OptionParser, options: T::Hash[Symbol, Object]).void }
      def self.parse(opts, options)
        opts.on('--connections_count=C', Integer) { |v| options[:connections] = T.cast(v, Integer) }
        opts.on('--https') { options[:use_https] = true }
        opts.on('--url=U', String) { |v| options[:target_urls] = T.cast(v, String).split(',') }
        opts.on('--export_json=FILE', String) { |v| options[:export_json] = T.cast(v, String) }
        opts.on('--target_duration=S', Float) { |v| options[:target_duration] = T.cast(v, Float) }
        ignore_core_args(opts)
        nil
      end

      # Binds OptionParser NO-OP lambdas for core args.
      #
      # @param opts [OptionParser] the active parser instance
      # @return [void]
      sig { params(opts: OptionParser).void }
      def self.ignore_core_args(opts)
        opts.on('--verbose') { nil }
        opts.on('--[no-]ping') { nil }
        opts.on('--ping_period=S', Integer) { nil }
        opts.on('--http_loader_timeout=S', Float) { nil }
        opts.on('--connections_per_second=R', Integer) { nil }
        ignore_time_args(opts)
        nil
      end

      # Binds OptionParser NO-OP lambdas for timing variables.
      #
      # @param opts [OptionParser] the active parser instance
      # @return [void]
      sig { params(opts: OptionParser).void }
      def self.ignore_time_args(opts)
        opts.on('--max_concurrent_connections=C', Integer) { nil }
        opts.on('--reopen_closed_connections') { nil }
        opts.on('--reopen_interval=S', Float) { nil }
        opts.on('--read_timeout=S', Float) { nil }
        opts.on('--user_agent=A', String) { nil }
        ignore_advanced_args(opts)
        nil
      end

      # Binds OptionParser NO-OP lambdas for advanced connection variables.
      #
      # @param opts [OptionParser] the active parser instance
      # @return [void]
      sig { params(opts: OptionParser).void }
      def self.ignore_advanced_args(opts)
        opts.on('--jitter=F', Float) { nil }
        opts.on('--track_status_codes') { nil }
        opts.on('--ramp_up=S', Float) { nil }
        opts.on('--bind_ips=IPS', String) { nil }
        opts.on('--proxy_pool=U', String) { nil }
        ignore_payload_args(opts)
        nil
      end

      # Binds OptionParser NO-OP lambdas for slowloris and HTTP headers variables.
      #
      # @param opts [OptionParser] the active parser instance
      # @return [void]
      sig { params(opts: OptionParser).void }
      def self.ignore_payload_args(opts)
        opts.on('--qps_per_connection=R', Integer) { nil }
        opts.on('--headers=LIST', String) { nil }
        opts.on('--slowloris_delay=S', Float) { nil }
        nil
      end
    end
  end
end

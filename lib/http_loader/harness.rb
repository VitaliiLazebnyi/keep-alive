# typed: strong
# frozen_string_literal: true

require 'sorbet-runtime'
require 'fileutils'
require_relative 'harness/config'
require_relative 'harness/resource_monitor'
require_relative 'harness/telemetry'
require_relative 'harness/process_manager'
require_relative 'harness/formatter'

module KeepAlive
  # Harness orchestrates the entire load testing lifecycle seamlessly and securely.
  class Harness
    extend T::Sig
    include Formatter

    sig { params(config: Config).void }
    def initialize(config)
      @config = config
      @start_time = T.let(Time.now.utc, Time)
      @peak_connections = T.let(0, Integer)
      log_dir = T.let(File.expand_path('../../logs', __dir__), String)
      @telemetry = T.let(Telemetry.new(log_dir, config.export_json), Telemetry)
      @pm = T.let(ProcessManager.new(config), ProcessManager)
      @monitor = T.let(ResourceMonitor.new, ResourceMonitor)
    end

    sig { void }
    def start
      $stdout.sync = true
      print_startup_banner
      bump_file_limits

      run_lifecycle
    end

    private

    sig { void }
    def run_lifecycle
      @pm.spawn_processes
      trap('INT') do
        puts "\n[Harness] Caught interrupt, cleaning up processes..."
        @pm.cleanup
        exit(0)
      end
      monitor_resources
    ensure
      @telemetry.export!(@peak_connections, @start_time)
      @pm.cleanup
    end

    sig { void }
    def monitor_resources
      print_table_header
      @start_time = Time.now.utc

      loop do
        break if duration_exceeded?

        tick_result = tick_failed?
        break if tick_result

        @telemetry.check_bottlenecks!
        sleep(2)
      end
    end

    sig { returns(T::Boolean) }
    def duration_exceeded?
      elapsed = Time.now.utc - @start_time
      return false unless @config.target_duration.positive? && elapsed >= @config.target_duration

      puts "[Harness] Target duration mathematically reached (#{@config.target_duration}s). auto-shutdown."
      true
    end

    sig { returns(T::Boolean) }
    def tick_failed?
      active_c, c_cpu, c_th, c_m = extract_client_stats
      @peak_connections = [@peak_connections, active_c].max

      return true if missing_socket?(active_c, c_cpu, c_th, c_m)
      return true if @pm.missing_process?

      print_combined_stats(active_c, c_cpu, c_th, c_m)
      false
    end

    sig { void }
    def bump_file_limits
      Process.setrlimit(Process::RLIMIT_NOFILE, @config.connections + 1024)
    rescue Errno::EPERM
      puts '[Harness] Warning: Could not set RLIMIT_NOFILE automatically.'
    end

    sig { params(active: Integer, c_cpu: String, c_th: Integer, c_m: String).returns(T::Boolean) }
    def missing_socket?(active, c_cpu, c_th, c_m)
      return false unless @config.target_urls.any? && @peak_connections.positive? && active.zero?

      log_table_row(
        t: Time.now.utc.strftime('%H:%M:%S'), ac: active, sc: 'EXTERNAL', sm: 'N/A',
        sk: 'N/A', cc: "#{c_cpu}% / #{c_th}T", cm: c_m, ck: 'N/A'
      )
      puts "\n[Harness] \u26A0\uFE0F EXTERNAL SERVER DISCONNECTED!"
      true
    end
  end
end

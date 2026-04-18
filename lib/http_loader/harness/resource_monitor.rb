# typed: strong
# frozen_string_literal: true

require 'sorbet-runtime'
require 'open3'

# Primary namespace for the load testing framework.
module HttpLoader
  class Harness
    # Monitors CPU, memory, and established connections for running processes.
    class ResourceMonitor
      extend T::Sig

      # Connects system resource metrics trackers mapping natively OS limits.
      #
      # @return [void]
      sig { void }
      def initialize
        @cpu_prev = T.let({}, T::Hash[Integer, T::Hash[Symbol, T.untyped]])
      end

      # Generates fully mapped array structure containing instantaneous memory, threads, and cpu overhead natively.
      #
      # @param pid [Integer, nil] mapped external system trace identifier
      # @return [Array<String, String, Float, Integer>] combined telemetry matrix structurally evaluating overhead
      sig { params(pid: T.nilable(Integer)).returns([String, String, Float, Integer]) }
      def process_stats(pid)
        return ['EXTERNAL', 'EXTERNAL', 0.0, 0] if pid.nil?

        if File.exist?("/proc/#{pid}/stat") && File.exist?("/proc/#{pid}/statm")
          native_linux_stats(pid)
        else
          fallback_ps_stats(pid)
        end
      rescue StandardError
        fallback_ps_stats(T.must(pid))
      end

      # Aggregates physical network sockets representing valid ESTABLISHED system patterns cleanly without collision.
      #
      # @param pid [Integer, nil] OS map matching tracking subsystem explicitly
      # @return [Integer] sum total connected target bound structures natively
      sig { params(pid: T.nilable(Integer)).returns(Integer) }
      def count_established_connections(pid)
        return 0 if pid.nil?

        if File.directory?("/proc/#{pid}/fd")
          count_linux_connections(pid)
        else
          count_lsof_connections(pid)
        end
      rescue StandardError
        0
      end

      private

      # Reads extremely fast native `/proc/` structures uniquely optimized against Linux kernel metrics organically.
      #
      # @param pid [Integer] targeted local subsystem identifier explicitly queried
      # @return [Array<String, String, Float, Integer>] Linux optimal explicit mapping payload explicitly formatted
      sig { params(pid: Integer).returns([String, String, Float, Integer]) }
      def native_linux_stats(pid)
        rss_kb = read_rss_kb(pid)
        cpu_perc = read_cpu_perc(pid)
        [cpu_perc.to_s, "#{(rss_kb / 1024.0).round(2)} MB", rss_kb, read_threads(pid)]
      end

      # Pulls explicit paging metric memory utilization representing unswapped allocation statically.
      #
      # @param pid [Integer] system explicit tracked application structure
      # @return [Float] calculated unbuffered resident kilobyte limits accurately
      sig { params(pid: Integer).returns(Float) }
      def read_rss_kb(pid)
        rss_pages = T.must(File.read("/proc/#{pid}/statm").split[1]).to_i
        (rss_pages * fetch_page_size) / 1024.0
      end

      # Maps current elapsed execution loops into relative temporal performance representations accurately.
      #
      # @param pid [Integer] physical subsystem integer map
      # @return [Float] percentage scale explicitly normalized natively
      sig { params(pid: Integer).returns(Float) }
      def read_cpu_perc(pid)
        stat_array = File.read("/proc/#{pid}/stat").split
        calculate_cpu(pid, T.must(stat_array[13]).to_f + T.must(stat_array[14]).to_f)
      end

      # Scrapes raw `/proc/$PID/status` natively extracting precise context thread sizes directly via regex bindings.
      #
      # @param pid [Integer] process index executed explicitly
      # @return [Integer] count describing parallel subsystem bindings organically
      sig { params(pid: Integer).returns(Integer) }
      def read_threads(pid)
        File.read("/proc/#{pid}/status").match(/Threads:\s+(\d+)/)&.[](1)&.to_i || 1
      end

      # Discovers OS bound kernel limits specifically regarding internal RAM memory boundary allocations universally.
      #
      # @return [Integer] memory integer sizing parameter bound physically
      sig { returns(Integer) }
      def fetch_page_size
        return 4096 unless File.exist?('/usr/bin/getconf')

        out, _s = Open3.capture2('getconf PAGE_SIZE')
        out.to_i > 0.0 ? out.to_i : 4096
      rescue StandardError
        4096
      end

      # Performs numerical differentials tracking performance deviations over discrete timelines.
      #
      # @param pid [Integer] specific tracked executable index bound to the process.
      # @param total_ticks [Float] sum evaluation counting unscaled processing metric counts effectively
      # @return [Float] finalized percentage representing consumption exactly.
      sig { params(pid: Integer, total_ticks: Float).returns(Float) }
      def calculate_cpu(pid, total_ticks)
        now = Time.now.utc
        prev = @cpu_prev[pid]
        @cpu_prev[pid] = { ticks: total_ticks, time: now }
        return 0.0 unless prev

        time_diff = now - T.cast(prev[:time], Time)
        return 0.0 unless time_diff > 0.0

        (((total_ticks - T.cast(prev[:ticks], Float)) / 100.0) / time_diff * 100).round(1)
      end

      # Evaluates older fallback UNIX command line execution structures safely yielding basic analysis outputs.
      #
      # @param pid [Integer] tracked internal map universally evaluated.
      # @return [Array<String, String, Float, Integer>] subset output simulating mapped natively structures dynamically.
      sig { params(pid: Integer).returns([String, String, Float, Integer]) }
      def fallback_ps_stats(pid)
        out, _s = Open3.capture2('ps', '-o', '%cpu,rss', '-p', pid.to_s)
        lines = out.strip.split("\n")
        return ['N/A', 'N/A', 0.0, 0] if lines.size < 2

        cpu, rss_kb_str = T.must(lines[1]).strip.split(/\s+/)
        rss_kb_val = T.must(rss_kb_str).to_f

        [T.must(cpu), "#{(rss_kb_val / 1024.0).round(2)} MB", rss_kb_val, fallback_threads_count(pid)]
      rescue StandardError
        ['N/A', 'N/A', 0.0, 0]
      end

      # Inspects process lists securely filtering exact instances cleanly.
      #
      # @param pid [Integer] target
      # @return [Integer] thread size safely
      sig { params(pid: Integer).returns(Integer) }
      def fallback_threads_count(pid)
        out, _s = Open3.capture2("ps -M -p #{pid}")
        [out.strip.split("\n").size - 1, 0].max
      rescue StandardError
        1
      end

      # Inspects fast Linux specific raw sockets natively resolving bounds cleanly.
      #
      # @param pid [Integer] physical identifier dynamically mapped logically
      # @return [Integer] count explicitly returned and evaluated
      sig { params(pid: Integer).returns(Integer) }
      def count_linux_connections(pid)
        Dir.glob("/proc/#{pid}/fd/*").count do |fd_path|
          File.readlink(fd_path).start_with?('socket:[')
        rescue StandardError
          false
        end
      end

      # Leverages legacy UNIX tooling safely generating mapped logic structures universally.
      #
      # @param pid [Integer] ID
      # @return [Integer] connections count actively evaluated
      sig { params(pid: Integer).returns(Integer) }
      def count_lsof_connections(pid)
        out, _s = Open3.capture2("lsof -p #{pid} -n -P")
        out.scan('ESTABLISHED').count
      end
    end
  end
end

# typed: strong
# frozen_string_literal: true

require 'sorbet-runtime'
require 'open3'

module KeepAlive
  class Harness
    # Monitors CPU, memory, and established connections for running processes.
    class ResourceMonitor
      extend T::Sig

      sig { void }
      def initialize
        @cpu_prev = T.let({}, T::Hash[Integer, T::Hash[Symbol, T.untyped]])
      end

      sig { params(pid: T.nilable(Integer)).returns([String, String, Float, Integer]) }
      def process_stats(pid)
        return ['EXTERNAL', 'EXTERNAL', 0.0, 0] if pid.nil?

        if File.exist?("/proc/#{pid}/stat") && File.exist?("/proc/#{pid}/statm")
          native_linux_stats(pid)
        else
          fallback_ps_stats(pid)
        end
      rescue StandardError
        fallback_ps_stats(pid)
      end

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

      sig { params(pid: Integer).returns([String, String, Float, Integer]) }
      def native_linux_stats(pid)
        rss_kb = read_rss_kb(pid)
        cpu_perc = read_cpu_perc(pid)
        [cpu_perc.to_s, "#{(rss_kb / 1024.0).round(2)} MB", rss_kb, read_threads(pid)]
      end

      sig { params(pid: Integer).returns(Float) }
      def read_rss_kb(pid)
        rss_pages = T.must(File.read("/proc/#{pid}/statm").split[1]).to_i
        (rss_pages * fetch_page_size) / 1024.0
      end

      sig { params(pid: Integer).returns(Float) }
      def read_cpu_perc(pid)
        stat_array = File.read("/proc/#{pid}/stat").split
        calculate_cpu(pid, T.must(stat_array[13]).to_f + T.must(stat_array[14]).to_f)
      end

      sig { params(pid: Integer).returns(Integer) }
      def read_threads(pid)
        File.read("/proc/#{pid}/status").match(/Threads:\s+(\d+)/)&.[](1)&.to_i || 1
      end

      sig { returns(Integer) }
      def fetch_page_size
        return 4096 unless File.exist?('/usr/bin/getconf')

        out, _s = Open3.capture2('getconf PAGE_SIZE')
        out.to_i.positive? ? out.to_i : 4096
      rescue StandardError
        4096
      end

      sig { params(pid: Integer, total_ticks: Float).returns(Float) }
      def calculate_cpu(pid, total_ticks)
        prev = @cpu_prev[pid]
        now = Time.now.utc
        cpu_perc = 0.0

        if prev && (time_diff = now - prev[:time]).positive?
          cpu_perc = (((total_ticks - prev[:ticks]) / 100.0) / time_diff * 100).round(1)
        end

        @cpu_prev[pid] = { ticks: total_ticks, time: now }
        cpu_perc
      end

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

      sig { params(pid: Integer).returns(Integer) }
      def fallback_threads_count(pid)
        out, _s = Open3.capture2("ps -M -p #{pid}")
        [out.strip.split("\n").size - 1, 0].max
      rescue StandardError
        1
      end

      sig { params(pid: Integer).returns(Integer) }
      def count_linux_connections(pid)
        Dir.glob("/proc/#{pid}/fd/*").count do |fd_path|
          File.readlink(fd_path).start_with?('socket:[')
        rescue StandardError
          false
        end
      end

      sig { params(pid: Integer).returns(Integer) }
      def count_lsof_connections(pid)
        out, _s = Open3.capture2("lsof -p #{pid} -n -P")
        out.scan('ESTABLISHED').count
      end
    end
  end
end

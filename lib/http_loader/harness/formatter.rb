# typed: strong
# frozen_string_literal: true

require 'sorbet-runtime'

# Primary namespace for the load testing framework.
module HttpLoader
  class Harness
    # Formatter handles printing load test statistics dynamically and robustly.
    module Formatter
      extend T::Sig

      # Prints an initial banner announcing URL and mode configurations.
      #
      # @return [void]
      sig { void }
      def print_startup_banner
        harness = T.cast(self, HttpLoader::Harness)
        Kernel.puts "[Harness] Starting test with #{harness.config.connections} connections to #{startup_target_msg(harness)}"
      end

      # Yields formatted message describing targeted context
      # 
      # @param harness [HttpLoader::Harness] reference to local context
      # @return [String] formatted descriptor based on URLs count
      sig { params(harness: HttpLoader::Harness).returns(String) }
      def startup_target_msg(harness)
        urls = harness.config.target_urls
        return "**MULTIPLE TARGETS** (#{urls.size} URLs)." if urls.size > 1
        return "**EXTERNAL URL** #{urls.first}." if urls.size == 1

        harness.config.use_https ? '**HTTPS**.' : '**HTTP**.'
      end

      # Outputs the top layer header frame for the metrics table.
      #
      # @return [void]
      sig { void }
      def print_table_header
        Kernel.puts '[Harness] Monitoring resources (Press Ctrl+C to stop)...'
        Kernel.puts '-' * 125
        Kernel.puts 'Time (UTC) | Real Conns  | Srv CPU/Thrds    | Srv Mem        | Srv Mem/Conn   | Cli CPU/Thrds    | Cli Mem        | Cli Mem/Conn  '
        Kernel.puts '-' * 125
      end

      # Safely renders formatting table rows via string padding strategies.
      #
      # @param params [Hash] keyword arguments containing metric fields
      # @return [void]
      sig { params(params: T::Hash[Symbol, T.untyped]).void }
      def log_table_row(params)
        Kernel.puts Kernel.format(
          '%<t>-10s | %<ac>-11s | %<sc>-16s | %<sm>-14s | %<sk>-14s | %<cc>-16s | %<cm>-14s | %<ck>-14s',
          t: params[:t], ac: params[:ac], sc: params[:sc], sm: params[:sm],
          sk: params[:sk], cc: params[:cc], cm: params[:cm], ck: params[:ck]
        )
      end

      # Computes KB overhead proportionally to established sockets natively.
      #
      # @param kilo [Float] total kilobyte footprint
      # @param connections [Integer] observed connections count natively reported
      # @param pid [Integer, nil] identifier validating process presence locally
      # @return [String] formatted descriptor of bytes/connection logic
      sig { params(kilo: Float, connections: Integer, pid: T.nilable(Integer)).returns(String) }
      def format_kb_conn(kilo, connections, pid)
        return 'EXTERNAL' if pid.nil?
        return 'N/A' if connections.zero? || connections.negative?

        "#{(kilo / connections).round(2)} KB"
      end

      # Prints single row multiplexing both internal and external telemetry simultaneously.
      #
      # @param active [Integer] connections sum actively executing logic
      # @param c_cpu [String] client CPU utilization value
      # @param c_th [Integer] aggregated client thread count
      # @param c_m [String] client heap usage marker
      # @return [void]
      sig { params(active: Integer, c_cpu: String, c_th: Integer, c_m: String).void }
      def print_combined_stats(active, c_cpu, c_th, c_m)
        harness = T.cast(self, HttpLoader::Harness)
        s_cpu, s_mem, s_th, s_conn = extract_server_stats
        _cc, _cm, c_kb, _ct = harness.monitor.process_stats(harness.pm.client_pid)
        c_conn = format_kb_conn(c_kb, active, harness.pm.client_pid)

        log_table_row(
          t: Time.now.utc.strftime('%H:%M:%S'), ac: active.to_s,
          sc: "#{s_cpu}% / #{s_th}", sm: s_mem, sk: s_conn,
          cc: "#{c_cpu}% / #{c_th}", cm: c_m, ck: c_conn
        )
      end

      # Polls target server analytics resolving metric aggregations consistently.
      #
      # @return [Array<String, String, Integer, String>] data frame array for the internal server metrics
      sig { returns([String, String, Integer, String]) }
      def extract_server_stats
        harness = T.cast(self, HttpLoader::Harness)
        s_cpu, s_mem, s_kb, s_th = harness.monitor.process_stats(harness.pm.server_pid)
        active_s = harness.monitor.count_established_connections(harness.pm.server_pid)
        s_conn = format_kb_conn(s_kb, active_s, harness.pm.server_pid)
        [s_cpu, s_mem, s_th, s_conn]
      end

      # Polls target client processes tracking load execution limits systematically.
      #
      # @return [Array<Integer, String, Integer, String>] extracted client variables dataset
      sig { returns([Integer, String, Integer, String]) }
      def extract_client_stats
        harness = T.cast(self, HttpLoader::Harness)
        c_cpu, c_mem, _c_kb, c_th = harness.monitor.process_stats(harness.pm.client_pid)
        active_c = harness.monitor.count_established_connections(harness.pm.client_pid)
        [active_c, c_cpu, c_th, c_mem]
      end
    end
  end
end

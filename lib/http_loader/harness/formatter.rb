# typed: strong
# frozen_string_literal: true

require 'sorbet-runtime'

module KeepAlive
  class Harness
    # Formatter handles printing load test statistics dynamically and robustly.
    module Formatter
      extend T::Sig
      extend T::Helpers

      requires_ancestor { KeepAlive::Harness }

      sig { void }
      def print_startup_banner
        msg = if @config.target_urls.size > 1
                "**MULTIPLE TARGETS** (#{@config.target_urls.size} URLs)."
              elsif @config.target_urls.size == 1
                "**EXTERNAL URL** #{@config.target_urls.first}."
              elsif @config.use_https
                '**HTTPS**.'
              else
                '**HTTP**.'
              end
        puts "[Harness] Starting test with #{@config.connections} connections to #{msg}"
      end

      sig { void }
      def print_table_header
        puts '[Harness] Monitoring resources (Press Ctrl+C to stop)...'
        puts '-' * 125
        puts 'Time (UTC) | Real Conns  | Srv CPU/Thrds    | Srv Mem        | Srv Mem/Conn   | ' \
             'Cli CPU/Thrds    | Cli Mem        | Cli Mem/Conn  '
        puts '-' * 125
      end

      sig { params(params: T::Hash[Symbol, T.untyped]).void }
      def log_table_row(params)
        puts format('%<t>-10s | %<ac>-11s | %<sc>-16s | %<sm>-14s | %<sk>-14s | %<cc>-16s | %<cm>-14s | %<ck>-14s',
                    t: params[:t], ac: params[:ac], sc: params[:sc], sm: params[:sm],
                    sk: params[:sk], cc: params[:cc], cm: params[:cm], ck: params[:ck])
      end

      sig { params(kilo: Float, connections: Integer, pid: T.nilable(Integer)).returns(String) }
      def format_kb_conn(kilo, connections, pid)
        return 'EXTERNAL' if pid.nil?
        return 'N/A' if connections.zero? || connections.negative?

        "#{(kilo / connections).round(2)} KB"
      end

      sig { params(active: Integer, c_cpu: String, c_th: Integer, c_m: String).void }
      def print_combined_stats(active, c_cpu, c_th, c_m)
        s_cpu, s_mem, s_th, s_conn = extract_server_stats
        _cc, _cm, c_kb, _ct = @monitor.process_stats(@pm.client_pid)
        c_conn = format_kb_conn(c_kb, active, @pm.client_pid)

        log_table_row(
          t: Time.now.utc.strftime('%H:%M:%S'), ac: active.to_s,
          sc: "#{s_cpu}% / #{s_th}", sm: s_mem, sk: s_conn,
          cc: "#{c_cpu}% / #{c_th}", cm: c_m, ck: c_conn
        )
      end

      sig { returns([String, String, Integer, String]) }
      def extract_server_stats
        s_cpu, s_mem, s_kb, s_th = @monitor.process_stats(@pm.server_pid)
        active_s = @monitor.count_established_connections(@pm.server_pid)
        s_conn = format_kb_conn(s_kb, active_s, @pm.server_pid)
        [s_cpu, s_mem, s_th, s_conn]
      end

      sig { returns([Integer, String, Integer, String]) }
      def extract_client_stats
        c_cpu, c_mem, _c_kb, c_th = @monitor.process_stats(@pm.client_pid)
        active_c = @monitor.count_established_connections(@pm.client_pid)
        [active_c, c_cpu, c_th, c_mem]
      end
    end
  end
end
